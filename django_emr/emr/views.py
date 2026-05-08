import json

from django.contrib.auth import authenticate
from django.utils.dateparse import parse_date, parse_time
from django.conf import settings
from django.utils import timezone
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from rest_framework import status, viewsets
from rest_framework.authentication import SessionAuthentication, TokenAuthentication
from rest_framework.authtoken.models import Token
from rest_framework.decorators import (
    api_view,
    authentication_classes,
    permission_classes,
)
from rest_framework.permissions import AllowAny, IsAuthenticated, SAFE_METHODS
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.permissions import BasePermission
from rest_framework.response import Response

from accounts.models import User
from .models import (
    Appointment,
    Country,
    Feedback,
    General,
    Hospital,
    ImportInbox,
    Invoices,
    MedicalRecord,
    NutritionEntry,
    Patient,
    Provider,
    Speciality,
    Timezone,
    PatientDocument,
)
from .serializers import (
    AppointmentSerializer,
    AppointmentExpandedSerializer,
    CountrySerializer,
    FeedbackSerializer,
    GeneralSerializer,
    HospitalSerializer,
    ImportInboxSerializer,
    InvoicesSerializer,
    MedicalRecordSerializer,
    NutritionEntrySerializer,
    PatientSerializer,
    ProviderListSerializer,
    RegisterSerializer,
    SpecialitySerializer,
    TimezoneSerializer,
    PatientDocumentSerializer,
)


def _is_staffish(user):
    return bool(getattr(user, "is_staff", False) or getattr(user, "is_superuser", False))


def _get_patient_for_user(user):
    return Patient.objects.filter(user=user).first()


def _extract_text_from_upload(uploaded_file, content_type_hint=""):
    """
    Best-effort text extraction:
    - PDF: PyPDF2 (text-layer only)
    - text/*: decode
    - images: pytesseract if available

    Returns: (text, status, error_message)
    """
    name = (getattr(uploaded_file, "name", "") or "").lower()
    ctype = (content_type_hint or getattr(uploaded_file, "content_type", "") or "").lower()

    try:
        raw = uploaded_file.read()
    finally:
        try:
            uploaded_file.seek(0)
        except Exception:
            pass

    # text
    if ctype.startswith("text/") or name.endswith(".txt"):
        try:
            return raw.decode("utf-8", errors="ignore"), PatientDocument.Status.TEXT_EXTRACTED, ""
        except Exception as e:
            return "", PatientDocument.Status.ERROR, str(e)

    # pdf (text layer)
    if ctype == "application/pdf" or name.endswith(".pdf"):
        try:
            import io
            from PyPDF2 import PdfReader

            reader = PdfReader(io.BytesIO(raw))
            parts = []
            for p in reader.pages[:50]:
                try:
                    parts.append(p.extract_text() or "")
                except Exception:
                    parts.append("")
            text = "\n".join([x for x in parts if x]).strip()
            if text:
                return text, PatientDocument.Status.TEXT_EXTRACTED, ""
            return "", PatientDocument.Status.TEXT_EXTRACTED, "No text layer found (OCR required for scanned PDFs)."
        except Exception as e:
            return "", PatientDocument.Status.ERROR, f"PDF extract failed: {e}"

    # image OCR
    if ctype.startswith("image/") or any(name.endswith(x) for x in (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff")):
        try:
            from PIL import Image
            import io
            import pytesseract

            img = Image.open(io.BytesIO(raw))
            text = (pytesseract.image_to_string(img) or "").strip()
            return text, PatientDocument.Status.OCR_DONE, ""
        except Exception as e:
            return "", PatientDocument.Status.ERROR, (
                "OCR failed. Ensure Pillow + pytesseract are installed and `tesseract` is available on the server. "
                f"Details: {e}"
            )

    return "", PatientDocument.Status.ERROR, "Unsupported file type for extraction."


def _summarize_text_stub(text: str) -> str:
    """
    Minimal summary scaffold (no external LLM dependency).
    Replace with a real LLM call when ready.
    """
    t = (text or "").strip()
    if not t:
        return "No text extracted from this document."
    # Keep it bounded for storage/UI.
    t = t[:20000]
    lines = [ln.strip() for ln in t.splitlines() if ln.strip()]
    head = "\n".join(lines[:30])
    return (
        "AI Summary (basic):\n"
        "- This is a server-side scaffold summary (no external LLM configured).\n"
        "- Extracted highlights (first lines):\n\n"
        f"{head}"
    )


@api_view(["GET", "POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def patient_documents(request):
    """
    GET: list documents visible to current user
    POST: upload a patient document (multipart form-data: file, optional patient_id)
    """
    user = request.user
    if request.method == "GET":
        patient_id = request.query_params.get("patient_id")
        qs = PatientDocument.objects.all()
        if _is_staffish(user) or user.provider_profiles.exists():
            if patient_id:
                qs = qs.filter(patient_id=patient_id)
        else:
            p = _get_patient_for_user(user)
            if not p:
                return _success({"results": []})
            qs = qs.filter(patient=p)
        ser = PatientDocumentSerializer(qs[:200], many=True, context={"request": request})
        return _success({"results": ser.data})

    # POST upload
    f = request.FILES.get("file")
    if not f:
        return _error({"file": ["file is required"]})
    patient_id = request.data.get("patient_id") or request.query_params.get("patient_id")
    patient = None
    if patient_id and (_is_staffish(user) or user.provider_profiles.exists()):
        patient = Patient.objects.filter(id=patient_id).first()
    if patient is None:
        patient = _get_patient_for_user(user)
    if patient is None:
        return _error({"patient": ["No patient profile found for this user."]})

    doc = PatientDocument.objects.create(
        patient=patient,
        uploaded_by=user if user.is_authenticated else None,
        file=f,
        original_name=getattr(f, "name", "") or "",
        content_type=getattr(f, "content_type", "") or "",
        size_bytes=getattr(f, "size", 0) or 0,
        status=PatientDocument.Status.UPLOADED,
    )
    ser = PatientDocumentSerializer(doc, context={"request": request})
    return _success({"document": ser.data}, message="Uploaded")


@api_view(["GET", "POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def patient_document_detail(request, doc_id):
    """
    GET: document detail
    POST: process (extract/OCR + summarize)
    """
    user = request.user
    doc = PatientDocument.objects.filter(id=doc_id).first()
    if not doc:
        return _error({"document": ["not found"]}, status.HTTP_404_NOT_FOUND)

    # Authorization
    if not (_is_staffish(user) or user.provider_profiles.exists()):
        p = _get_patient_for_user(user)
        if not p or doc.patient_id != p.id:
            return _error({"detail": ["forbidden"]}, status.HTTP_403_FORBIDDEN)

    if request.method == "GET":
        ser = PatientDocumentSerializer(doc, context={"request": request})
        # include a short preview for UI convenience
        preview = (doc.extracted_text or "")[:4000]
        return _success({"document": ser.data, "text_preview": preview})

    # Process
    try:
        text, st, err = _extract_text_from_upload(doc.file, doc.content_type)
        doc.extracted_text = text or ""
        doc.status = st
        doc.error_message = err or ""
        if st != PatientDocument.Status.ERROR:
            doc.ai_summary = _summarize_text_stub(doc.extracted_text)
            doc.status = PatientDocument.Status.SUMMARIZED
        doc.processed_at = timezone.now()
        doc.save()
    except Exception as e:
        doc.status = PatientDocument.Status.ERROR
        doc.error_message = str(e)
        doc.processed_at = timezone.now()
        doc.save()

    ser = PatientDocumentSerializer(doc, context={"request": request})
    preview = (doc.extracted_text or "")[:4000]
    return _success({"document": ser.data, "text_preview": preview}, message="Processed")


def _success(data=None, message="OK"):
    return Response(
        {"status": "success", "message": message, "data": data or {}},
        status=status.HTTP_200_OK,
    )


def _error(errors, status_code=status.HTTP_400_BAD_REQUEST):
    return Response(
        {"status": "error", "errors": errors},
        status=status_code,
    )


def _normalized_portal(body):
    raw = body.get("portal") or body.get("role") or ""
    return str(raw).lower().strip()


def _portal_allows_login(portal, user):
    """Enforce Patient / Doctor / Administrator lanes (mobile sends `portal` + `role`)."""
    if not portal:
        return True, None
    if portal in ("patient", "user"):
        if user.provider_profiles.exists():
            return False, (
                "This portal is for patients. Use Doctor sign-in for clinical accounts."
            )
        # Patients no longer require admin approval to sign in.
        # Admins can still edit patient records or credentials via Django Admin.
        return True, None
    if portal in ("doctor", "provider", "physician"):
        if not user.provider_profiles.exists():
            return False, (
                "This portal is for doctors only. "
                "This account is not linked to a provider profile yet."
            )
        p = user.provider_profiles.first()
        if p:
            status_raw = (p.status or "").lower().strip()
            if status_raw in ("pending", "inactive") or not bool(p.is_verified):
                return False, "Your doctor registration is pending admin approval."
        return True, None
    if portal in ("administrator", "admin", "staff"):
        if not (user.is_staff or user.is_superuser):
            return False, (
                "This portal is for administrators only. "
                "Your account does not have staff privileges."
            )
        return True, None
    return True, None


@api_view(["GET"])
@permission_classes([AllowAny])
def health(request):
    return _success({"ok": True}, message="Service healthy")


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([AllowAny])
def doctor_on_call_me(request):
    """
    Resolve role for the mobile app.
    - admin: is_staff or is_superuser
    - doctor: has Provider profile
    - patient: default (may or may not have Patient profile)
    """
    user = request.user
    if not user.is_authenticated:
        return _success(
            {
                "is_authenticated": False,
                "role": "guest",
            }
        )

    role = "patient"
    if user.is_staff or user.is_superuser:
        role = "admin"
    elif user.provider_profiles.exists():
        role = "doctor"

    provider = user.provider_profiles.first()
    patient = Patient.objects.filter(user=user).first()
    return _success(
        {
            "is_authenticated": True,
            "role": role,
            "user": {
                "id": user.id,
                "username": user.username,
                "email": user.email,
                "full_name": user.get_full_name() or user.username,
                "is_staff": user.is_staff,
                "is_superuser": user.is_superuser,
            },
            "doctor": ProviderListSerializer(provider).data if provider else None,
            "patient": PatientSerializer(patient).data if patient else None,
        }
    )


@api_view(["POST"])
@permission_classes([AllowAny])
def auth_login(request):
    """
    Accept identity under username, user, email, login, identifier (mirrors common Django patterns).
    """
    body = request.data if request.data else {}
    if not isinstance(body, dict):
        body = dict(body)
    if not body and request.body:
        try:
            body = json.loads(request.body)
        except json.JSONDecodeError:
            body = {}

    password = body.get("password") or body.get("Password")
    identity = (
        body.get("username")
        or body.get("user")
        or body.get("email")
        or body.get("Email")
        or body.get("login")
        or body.get("identifier")
    )

    if not identity or not password:
        return _error({"non_field_errors": ["identity and password required"]})

    user_obj = None
    if "@" in str(identity):
        user_obj = User.objects.filter(email__iexact=identity).first()
        username = user_obj.username if user_obj else None
    else:
        username = identity

    user = authenticate(request, username=username or identity, password=password)
    if user is None and user_obj:
        user = authenticate(request, username=user_obj.username, password=password)
    if user is None:
        try:
            u = User.objects.get(email__iexact=identity)
            user = authenticate(request, username=u.username, password=password)
        except User.DoesNotExist:
            pass

    if user is None:
        return Response(
            {"status": "error", "message": "Invalid credentials"},
            status=status.HTTP_401_UNAUTHORIZED,
        )

    portal = _normalized_portal(body)
    allowed, deny_message = _portal_allows_login(portal, user)
    if not allowed:
        return Response(
            {"status": "error", "message": deny_message},
            status=status.HTTP_403_FORBIDDEN,
        )

    token, _ = Token.objects.get_or_create(user=user)
    return Response(
        {
            "status": "success",
            "message": "Login successful",
            "data": {
                "user_id": user.id,
                "username": user.username,
                "email": user.email,
                "full_name": user.get_full_name() or user.username,
                "role": "staff" if user.is_staff else "user",
                "is_staff": user.is_staff,
                "is_superuser": user.is_superuser,
                "is_authenticated": True,
                "token": token.key,
                "auth_type": "session+token",
            },
        },
        status=status.HTTP_200_OK,
    )


@api_view(["POST"])
@permission_classes([AllowAny])
def auth_register(request):
    payload = request.data if request.data else {}
    if not payload and request.body:
        try:
            payload = json.loads(request.body)
        except json.JSONDecodeError:
            payload = {}

    ser = RegisterSerializer(data=payload)
    if not ser.is_valid():
        return _error(ser.errors, status.HTTP_400_BAD_REQUEST)

    user = ser.save()
    # Create a minimal patient profile immediately active (no approval gate).
    # Providers (doctors) must apply via a separate flow.
    portal = str(ser.validated_data.get("portal") or "").lower().strip()
    if portal in ("patient", "user", ""):
        Patient.objects.get_or_create(
            user=user,
            defaults={
                "name": user.get_full_name() or user.username,
                "date_of_birth": "Unknown",
                "email": user.email,
                "profile_status": "approved",
            },
        )
    token, _ = Token.objects.get_or_create(user=user)
    return Response(
        {
            "status": "success",
            "message": "Registered",
            "data": {
                "user_id": user.id,
                "username": user.username,
                "email": user.email,
                "token": token.key,
            },
        },
        status=status.HTTP_201_CREATED,
    )


@api_view(["POST"])
@permission_classes([AllowAny])
def auth_register_admin(request):
    """
    Admin registration is protected by a secret code so normal users cannot self-register as staff.
    Set env var ADMIN_REGISTER_CODE.
    """
    payload = request.data if request.data else {}
    if not payload and request.body:
        try:
            payload = json.loads(request.body)
        except json.JSONDecodeError:
            payload = {}

    code = str(payload.get("admin_code") or payload.get("code") or "").strip()
    expected = (getattr(settings, "ADMIN_REGISTER_CODE", "") or "").strip()
    if not expected:
        return Response(
            {"status": "error", "message": "Admin registration is disabled."},
            status=status.HTTP_403_FORBIDDEN,
        )
    if not code or code != expected:
        return Response(
            {"status": "error", "message": "Invalid admin code."},
            status=status.HTTP_403_FORBIDDEN,
        )

    ser = RegisterSerializer(data=payload)
    if not ser.is_valid():
        return _error(ser.errors, status.HTTP_400_BAD_REQUEST)
    user = ser.save()
    user.is_staff = True
    user.save(update_fields=["is_staff"])
    token, _ = Token.objects.get_or_create(user=user)
    return Response(
        {
            "status": "success",
            "message": "Admin registered",
            "data": {"user_id": user.id, "username": user.username, "email": user.email, "token": token.key},
        },
        status=status.HTTP_201_CREATED,
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def provider_apply(request):
    """
    Doctor/provider application.
    Creates Provider row linked to current user, status=pending, is_verified=false.
    """
    if request.user.provider_profiles.exists():
        return _success({"created": False}, message="Provider profile already exists")

    full_name = str(request.data.get("full_name") or "").strip()
    email = str(request.data.get("email") or request.user.email or "").strip()
    phone = str(request.data.get("phone_number") or "").strip()
    speciality_id = request.data.get("speciality_id")

    if not full_name:
        return _error({"full_name": ["required"]})
    if not email:
        return _error({"email": ["required"]})
    if not phone:
        return _error({"phone_number": ["required"]})
    try:
        speciality_id = int(speciality_id)
    except (TypeError, ValueError):
        return _error({"speciality_id": ["invalid"]})

    provider = Provider.objects.create(
        user=request.user,
        full_name=full_name,
        email=email,
        phone_number=phone,
        speciality_id=speciality_id,
        gender=str(request.data.get("gender") or "").strip() or None,
        license_number=(str(request.data.get("license_number") or "").strip() or None),
        qualifications=str(request.data.get("qualifications") or "").strip(),
        bio=str(request.data.get("bio") or "").strip(),
        status=Provider.Status.PENDING,
        is_verified=False,
    )
    return _success({"provider_id": provider.id}, message="Submitted (pending approval)")


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def registrations_pending(request):
    """Admin view: list pending patient + provider registrations."""
    if not (request.user.is_staff or request.user.is_superuser):
        return Response(
            {"status": "error", "message": "Admin only"},
            status=status.HTTP_403_FORBIDDEN,
        )
    patients = Patient.objects.filter(profile_status__in=["pending", "submitted", "awaiting-approval"]).select_related("user")[:500]
    providers = Provider.objects.filter(status__in=[Provider.Status.PENDING, Provider.Status.INACTIVE]).select_related("user")[:500]
    return _success(
        {
            "patients": PatientSerializer(patients, many=True).data,
            "providers": ProviderListSerializer(providers, many=True).data,
        }
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def registrations_approve(request):
    """Admin action: approve a patient or provider registration."""
    if not (request.user.is_staff or request.user.is_superuser):
        return Response(
            {"status": "error", "message": "Admin only"},
            status=status.HTTP_403_FORBIDDEN,
        )
    kind = str(request.data.get("kind") or request.data.get("type") or "").lower().strip()
    try:
        rid = int(request.data.get("id"))
    except (TypeError, ValueError):
        return _error({"id": ["invalid"]})

    if kind in ("patient", "patients"):
        p = Patient.objects.filter(id=rid).first()
        if not p:
            return _error({"detail": ["Not found"]}, status.HTTP_404_NOT_FOUND)
        p.profile_status = "approved"
        p.save(update_fields=["profile_status"])
        return _success({"approved": True})

    if kind in ("provider", "doctor", "physician"):
        pr = Provider.objects.filter(id=rid).first()
        if not pr:
            return _error({"detail": ["Not found"]}, status.HTTP_404_NOT_FOUND)
        pr.status = Provider.Status.ACTIVE
        pr.is_verified = True
        pr.save(update_fields=["status", "is_verified"])
        return _success({"approved": True})

    return _error({"kind": ["use patient or provider"]})


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def import_submit(request):
    """
    Patient submits an external API link + payload to Import Inbox.
    Admin will review/edit/merge later.
    """
    url = str(request.data.get("source_url") or request.data.get("url") or "").strip()
    if not url:
        return _error({"source_url": ["required"]})
    patient_email = str(request.data.get("patient_email") or request.user.email or "").strip()
    patient_hint = str(request.data.get("patient_hint") or "").strip()
    raw_payload = request.data.get("raw_payload") or request.data.get("payload") or ""
    ai_summary = request.data.get("ai_summary") or ""
    if not isinstance(raw_payload, str):
        raw_payload = json.dumps(raw_payload)
    if not isinstance(ai_summary, str):
        ai_summary = json.dumps(ai_summary)

    obj = ImportInbox.objects.create(
        submitted_by=request.user,
        patient_email=patient_email,
        patient_hint=patient_hint,
        source_url=url,
        raw_payload=raw_payload[:200000],
        ai_summary=ai_summary[:200000],
        status=ImportInbox.Status.PENDING,
    )
    return _success({"import_id": obj.id}, message="Submitted")


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def import_pending(request):
    if not (request.user.is_staff or request.user.is_superuser):
        return Response(
            {"status": "error", "message": "Admin only"},
            status=status.HTTP_403_FORBIDDEN,
        )
    qs = ImportInbox.objects.filter(status=ImportInbox.Status.PENDING).order_by("-id")[:500]
    return _success({"imports": ImportInboxSerializer(qs, many=True).data})


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def import_merge(request):
    """
    Admin merges an import into a Patient's MedicalRecord.
    Requires patient_email to match an existing Patient.
    """
    if not (request.user.is_staff or request.user.is_superuser):
        return Response(
            {"status": "error", "message": "Admin only"},
            status=status.HTTP_403_FORBIDDEN,
        )
    try:
        import_id = int(request.data.get("import_id"))
    except (TypeError, ValueError):
        return _error({"import_id": ["invalid"]})
    obj = ImportInbox.objects.filter(id=import_id).first()
    if not obj:
        return _error({"detail": ["Not found"]}, status.HTTP_404_NOT_FOUND)
    if obj.status != ImportInbox.Status.PENDING:
        return _error({"detail": ["Already processed"]})

    email = str(request.data.get("patient_email") or obj.patient_email or "").strip()
    if not email:
        return _error({"patient_email": ["required"]})
    patient = Patient.objects.filter(email__iexact=email).first()
    if not patient:
        return _error({"patient_email": ["No patient found for this email"]}, status.HTTP_404_NOT_FOUND)

    title = str(request.data.get("title") or "").strip() or "Imported record"
    raw_payload = request.data.get("raw_payload") or obj.raw_payload or ""
    ai_summary = request.data.get("ai_summary") or obj.ai_summary or ""
    if not isinstance(raw_payload, str):
        raw_payload = json.dumps(raw_payload)
    if not isinstance(ai_summary, str):
        ai_summary = json.dumps(ai_summary)

    rec = MedicalRecord.objects.create(
        patient=patient,
        source_url=obj.source_url,
        source_system=str(request.data.get("source_system") or "").strip(),
        title=title,
        raw_payload=raw_payload[:200000],
        ai_summary=ai_summary[:200000],
        merged_by=request.user,
    )
    obj.status = ImportInbox.Status.MERGED
    obj.merged_patient = patient
    obj.merged_record = rec
    obj.merged_by = request.user
    obj.save(update_fields=["status", "merged_patient", "merged_record", "merged_by"])
    return _success({"medical_record": MedicalRecordSerializer(rec).data}, message="Merged")


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def auth_logout(request):
    Token.objects.filter(user=request.user).delete()
    return _success(message="Logged out")


@api_view(["GET"])
@permission_classes([AllowAny])
def auth_password_policy(request):
    return _success(
        {
            "min_length": 8,
            "username_no_spaces": True,
            "note": "Match client validation with RegisterSerializer / User model.",
        }
    )


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([AllowAny])
def user_data(request):
    user = request.user
    if user.is_authenticated:
        return _success(
            {
                "user_id": user.id,
                "username": user.username,
                "email": user.email,
                "first_name": user.first_name,
                "last_name": user.last_name,
                "is_authenticated": True,
            }
        )
    return _success(
        {
            "user_id": None,
            "username": None,
            "email": None,
            "first_name": None,
            "last_name": None,
            "is_authenticated": False,
        }
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def feedback_submit(request):
    text = request.data.get("feedback") or request.data.get("message")
    if not text:
        return _error({"feedback": ["required"]})
    Feedback.objects.create(user=request.user, feedback=text[:255])
    return _success(message="Feedback submitted")


@api_view(["GET"])
@permission_classes([AllowAny])
def hospitals_list(request):
    qs = Hospital.objects.all()
    q = (request.GET.get("q") or "").strip()
    facility = (request.GET.get("facility_type") or "").strip().lower()
    if q:
        qs = qs.filter(name__icontains=q) | qs.filter(address__icontains=q)
    if facility:
        qs = qs.filter(facility_type__icontains=facility)
    qs = qs[:500]
    return _success({"results": HospitalSerializer(qs, many=True).data})


@api_view(["GET"])
@permission_classes([AllowAny])
def hospitals_search(request):
    # For now, reuse list filtering by `q` / `facility_type`. Later you can
    # add geo radius filtering using lat/lon if needed.
    return hospitals_list(request)


@api_view(["GET"])
@permission_classes([AllowAny])
def hospital_detail(request, hospital_id):
    h = Hospital.objects.filter(id=hospital_id).first()
    if not h:
        return Response(
            {"status": "error", "errors": {"hospital": ["not found"]}},
            status=status.HTTP_404_NOT_FOUND,
        )
    return _success(HospitalSerializer(h).data)


@api_view(["GET"])
@permission_classes([AllowAny])
def hospital_ai_wait_time(request, hospital_id):
    h = Hospital.objects.filter(id=hospital_id).first()
    if not h:
        return Response(
            {"status": "error", "errors": {"hospital": ["not found"]}},
            status=status.HTTP_404_NOT_FOUND,
        )
    return _success(
        {
            "hospital_id": h.id,
            "estimated_wait_minutes": h.wait_time_minutes,
            "rating": h.rating,
            "ai_rating": h.ai_rating,
            "is_open": h.is_open,
        }
    )


@api_view(["POST"])
@permission_classes([AllowAny])
def hospitals_seed_demo(request):
    """
    Create demo hospitals so the Flutter list is not empty.
    Safe to call multiple times (won't duplicate by name+address).
    """
    if Hospital.objects.exists():
        return _success({"created": 0, "note": "Hospitals already exist"})

    demo = [
        {
            "name": "Cupertino General Hospital",
            "address": "123 Main St, Cupertino, CA",
            "facility_type": "Emergency Room",
            "latitude": 37.3230,
            "longitude": -122.0322,
            "rating": 4.2,
            "ai_rating": 4.4,
            "wait_time_minutes": 18,
            "is_open": True,
        },
        {
            "name": "Westside Urgent Care",
            "address": "930 Cole St, San Francisco, CA",
            "facility_type": "Urgent Care",
            "latitude": 37.7692,
            "longitude": -122.4492,
            "rating": 4.0,
            "ai_rating": 4.1,
            "wait_time_minutes": 0,
            "is_open": True,
        },
        {
            "name": "Bayview Medical Center",
            "address": "500 Bay Rd, San Jose, CA",
            "facility_type": "Hospital",
            "latitude": 37.3382,
            "longitude": -121.8863,
            "rating": 3.8,
            "ai_rating": 3.9,
            "wait_time_minutes": 42,
            "is_open": True,
        },
    ]

    created = 0
    for row in demo:
        Hospital.objects.create(**row)
        created += 1

    return _success({"created": created})


@api_view(["POST"])
@permission_classes([AllowAny])
def providers_seed_demo(request):
    """
    Create demo providers so booking can work immediately.
    Safe to call multiple times (won't duplicate by email).
    """
    if Provider.objects.exists():
        return _success({"created": 0, "note": "Providers already exist"})

    # Ensure speciality exists (required FK).
    country = Country.objects.first()
    if not country:
        country = Country.objects.create(country_code="US", country_name="United States", image="")
    spec = Speciality.objects.first()
    if not spec:
        spec = Speciality.objects.create(
            speciality_name="General Practice",
            speciality_image="",
            country=country,
        )

    def _mk_user(username, email):
        u = User.objects.filter(username=username).first()
        if u:
            return u
        return User.objects.create_user(username=username, email=email, password="DemoPass2026!")

    demo = [
        {
            "username": "demo_provider1",
            "full_name": "Dr. Demo One",
            "email": "demo_provider1@example.com",
            "phone_number": "+14085550101",
            "status": "active",
            "consultation_fee": "50.00",
        },
        {
            "username": "demo_provider2",
            "full_name": "Dr. Demo Two",
            "email": "demo_provider2@example.com",
            "phone_number": "+14085550102",
            "status": "active",
            "consultation_fee": "75.00",
        },
    ]

    created = 0
    for row in demo:
        u = _mk_user(row["username"], row["email"])
        Provider.objects.create(
            user=u,
            full_name=row["full_name"],
            email=row["email"],
            phone_number=row["phone_number"],
            speciality=spec,
            status=row["status"],
            consultation_fee=row["consultation_fee"],
        )
        created += 1

    return _success({"created": created})


@api_view(["GET"])
@permission_classes([AllowAny])
def provider_types(request):
    """
    Return provider (consultation) types supported by the backend.
    (Based on Provider.consultation_type choices.)
    """
    items = [{"value": v, "label": l} for v, l in Provider.ConsultationType.choices]
    return _success({"types": items})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def reference_seed_all(request):
    """
    Seed full reference datasets used by the mobile app.

    - Countries: code + name
    - Specialities: broad medical speciality catalog

    Idempotent: will not duplicate existing rows.
    Restricted to staff/superusers.
    """
    if not (request.user.is_staff or request.user.is_superuser):
        return Response(
            {"status": "error", "message": "Admin only"},
            status=status.HTTP_403_FORBIDDEN,
        )

    countries = [
        ("AF", "Afghanistan"),
        ("AL", "Albania"),
        ("DZ", "Algeria"),
        ("AS", "American Samoa"),
        ("AD", "Andorra"),
        ("AO", "Angola"),
        ("AI", "Anguilla"),
        ("AQ", "Antarctica"),
        ("AG", "Antigua and Barbuda"),
        ("AR", "Argentina"),
        ("AM", "Armenia"),
        ("AW", "Aruba"),
        ("AU", "Australia"),
        ("AT", "Austria"),
        ("AZ", "Azerbaijan"),
        ("BS", "Bahamas"),
        ("BH", "Bahrain"),
        ("BD", "Bangladesh"),
        ("BB", "Barbados"),
        ("BY", "Belarus"),
        ("BE", "Belgium"),
        ("BZ", "Belize"),
        ("BJ", "Benin"),
        ("BM", "Bermuda"),
        ("BT", "Bhutan"),
        ("BO", "Bolivia"),
        ("BA", "Bosnia and Herzegovina"),
        ("BW", "Botswana"),
        ("BR", "Brazil"),
        ("BN", "Brunei"),
        ("BG", "Bulgaria"),
        ("BF", "Burkina Faso"),
        ("BI", "Burundi"),
        ("KH", "Cambodia"),
        ("CM", "Cameroon"),
        ("CA", "Canada"),
        ("CV", "Cape Verde"),
        ("KY", "Cayman Islands"),
        ("CF", "Central African Republic"),
        ("TD", "Chad"),
        ("CL", "Chile"),
        ("CN", "China"),
        ("CO", "Colombia"),
        ("KM", "Comoros"),
        ("CG", "Congo - Brazzaville"),
        ("CD", "Congo - Kinshasa"),
        ("CR", "Costa Rica"),
        ("CI", "Côte d’Ivoire"),
        ("HR", "Croatia"),
        ("CU", "Cuba"),
        ("CY", "Cyprus"),
        ("CZ", "Czechia"),
        ("DK", "Denmark"),
        ("DJ", "Djibouti"),
        ("DM", "Dominica"),
        ("DO", "Dominican Republic"),
        ("EC", "Ecuador"),
        ("EG", "Egypt"),
        ("SV", "El Salvador"),
        ("GQ", "Equatorial Guinea"),
        ("ER", "Eritrea"),
        ("EE", "Estonia"),
        ("SZ", "Eswatini"),
        ("ET", "Ethiopia"),
        ("FJ", "Fiji"),
        ("FI", "Finland"),
        ("FR", "France"),
        ("GF", "French Guiana"),
        ("PF", "French Polynesia"),
        ("GA", "Gabon"),
        ("GM", "Gambia"),
        ("GE", "Georgia"),
        ("DE", "Germany"),
        ("GH", "Ghana"),
        ("GI", "Gibraltar"),
        ("GR", "Greece"),
        ("GL", "Greenland"),
        ("GD", "Grenada"),
        ("GP", "Guadeloupe"),
        ("GU", "Guam"),
        ("GT", "Guatemala"),
        ("GN", "Guinea"),
        ("GW", "Guinea-Bissau"),
        ("GY", "Guyana"),
        ("HT", "Haiti"),
        ("HN", "Honduras"),
        ("HK", "Hong Kong SAR China"),
        ("HU", "Hungary"),
        ("IS", "Iceland"),
        ("IN", "India"),
        ("ID", "Indonesia"),
        ("IR", "Iran"),
        ("IQ", "Iraq"),
        ("IE", "Ireland"),
        ("IL", "Israel"),
        ("IT", "Italy"),
        ("JM", "Jamaica"),
        ("JP", "Japan"),
        ("JO", "Jordan"),
        ("KZ", "Kazakhstan"),
        ("KE", "Kenya"),
        ("KI", "Kiribati"),
        ("KW", "Kuwait"),
        ("KG", "Kyrgyzstan"),
        ("LA", "Laos"),
        ("LV", "Latvia"),
        ("LB", "Lebanon"),
        ("LS", "Lesotho"),
        ("LR", "Liberia"),
        ("LY", "Libya"),
        ("LI", "Liechtenstein"),
        ("LT", "Lithuania"),
        ("LU", "Luxembourg"),
        ("MO", "Macao SAR China"),
        ("MG", "Madagascar"),
        ("MW", "Malawi"),
        ("MY", "Malaysia"),
        ("MV", "Maldives"),
        ("ML", "Mali"),
        ("MT", "Malta"),
        ("MQ", "Martinique"),
        ("MR", "Mauritania"),
        ("MU", "Mauritius"),
        ("MX", "Mexico"),
        ("MD", "Moldova"),
        ("MC", "Monaco"),
        ("MN", "Mongolia"),
        ("ME", "Montenegro"),
        ("MA", "Morocco"),
        ("MZ", "Mozambique"),
        ("MM", "Myanmar (Burma)"),
        ("NA", "Namibia"),
        ("NP", "Nepal"),
        ("NL", "Netherlands"),
        ("NZ", "New Zealand"),
        ("NI", "Nicaragua"),
        ("NE", "Niger"),
        ("NG", "Nigeria"),
        ("NO", "Norway"),
        ("OM", "Oman"),
        ("PK", "Pakistan"),
        ("PA", "Panama"),
        ("PG", "Papua New Guinea"),
        ("PY", "Paraguay"),
        ("PE", "Peru"),
        ("PH", "Philippines"),
        ("PL", "Poland"),
        ("PT", "Portugal"),
        ("PR", "Puerto Rico"),
        ("QA", "Qatar"),
        ("RO", "Romania"),
        ("RU", "Russia"),
        ("RW", "Rwanda"),
        ("SA", "Saudi Arabia"),
        ("SN", "Senegal"),
        ("RS", "Serbia"),
        ("SC", "Seychelles"),
        ("SL", "Sierra Leone"),
        ("SG", "Singapore"),
        ("SK", "Slovakia"),
        ("SI", "Slovenia"),
        ("ZA", "South Africa"),
        ("KR", "South Korea"),
        ("ES", "Spain"),
        ("LK", "Sri Lanka"),
        ("SD", "Sudan"),
        ("SE", "Sweden"),
        ("CH", "Switzerland"),
        ("SY", "Syria"),
        ("TW", "Taiwan"),
        ("TZ", "Tanzania"),
        ("TH", "Thailand"),
        ("TN", "Tunisia"),
        ("TR", "Turkey"),
        ("UG", "Uganda"),
        ("UA", "Ukraine"),
        ("AE", "United Arab Emirates"),
        ("GB", "United Kingdom"),
        ("US", "United States"),
        ("UY", "Uruguay"),
        ("UZ", "Uzbekistan"),
        ("VE", "Venezuela"),
        ("VN", "Vietnam"),
        ("YE", "Yemen"),
        ("ZM", "Zambia"),
        ("ZW", "Zimbabwe"),
    ]

    specialities = [
        "Addiction Medicine",
        "Allergy & Immunology",
        "Audiology",
        "Anesthesiology",
        "Bariatric Surgery",
        "Cardiac Electrophysiology",
        "Cardiology",
        "Cardiothoracic Surgery",
        "Chiropractic",
        "Clinical Neurophysiology",
        "Colorectal Surgery",
        "Critical Care Medicine",
        "Dermatology",
        "Diabetology",
        "Diagnostic Radiology",
        "Dietitian / Nutritionist",
        "Emergency Medical Services (EMS)",
        "Emergency Medicine",
        "Family Planning",
        "Endocrinology",
        "Forensic Medicine",
        "Genetics",
        "Family Medicine",
        "Gastroenterology",
        "Gastrointestinal Surgery",
        "General Practice",
        "General Surgery",
        "Hand Surgery",
        "Geriatrics",
        "Hematology",
        "Hematology/Oncology",
        "Hepatology",
        "Infectious Disease",
        "Internal Medicine",
        "Interventional Cardiology",
        "Interventional Radiology",
        "Maternal-Fetal Medicine",
        "Nephrology",
        "Neonatology",
        "Neurology",
        "Neurocritical Care",
        "Neurosurgery",
        "Nuclear Medicine",
        "Obstetrics & Gynecology",
        "Occupational Medicine",
        "Occupational Therapy (OT)",
        "Optometry",
        "Oncology",
        "Ophthalmology",
        "Oral Medicine",
        "Orthopedics",
        "Orthopedic Spine Surgery",
        "Orthopedic Sports Medicine",
        "Otolaryngology (ENT)",
        "Palliative Care",
        "Pain Management",
        "Pathology",
        "Pediatric Cardiology",
        "Pediatric Endocrinology",
        "Pediatric Gastroenterology",
        "Pediatric Hematology/Oncology",
        "Pediatric Infectious Disease",
        "Pediatric Nephrology",
        "Pediatric Neurology",
        "Pediatric Pulmonology",
        "Pediatric Surgery",
        "Pediatric Urology",
        "Pediatrics",
        "Pharmacy",
        "Physical Medicine & Rehabilitation",
        "Physical Therapy (PT)",
        "Plastic Surgery",
        "Podiatry",
        "Psychiatry",
        "Psychology",
        "Pulmonology",
        "Radiation Oncology",
        "Radiology",
        "Reproductive Endocrinology & Infertility",
        "Rheumatology",
        "Sleep Medicine",
        "Speech-Language Pathology",
        "Sports Medicine",
        "Thoracic Surgery",
        "Trauma Surgery",
        "Urgent Care",
        "Urology",
        "Vascular Surgery",
        "Wound Care",
        "Dentistry",
        "Oral & Maxillofacial Surgery",
        "Orthodontics",
        "Nursing",
        "Physiotherapy",
        "Nutrition & Dietetics",
    ]

    created_countries = 0
    created_specialities = 0

    for code, name in countries:
        code_norm = (code or "").strip().upper()
        name_norm = (name or "").strip()
        if not code_norm or not name_norm:
            continue
        obj, created = Country.objects.get_or_create(
            country_code=code_norm,
            defaults={"country_name": name_norm, "image": ""},
        )
        if not created and obj.country_name != name_norm:
            obj.country_name = name_norm
            obj.save(update_fields=["country_name"])
        if created:
            created_countries += 1

    default_country = Country.objects.filter(country_code="US").first() or Country.objects.first()
    for s in specialities:
        name = (s or "").strip()
        if not name:
            continue
        _, created = Speciality.objects.get_or_create(
            speciality_name=name,
            defaults={"speciality_image": "", "country": default_country},
        )
        if created:
            created_specialities += 1

    return _success(
        {
            "countries_created": created_countries,
            "specialities_created": created_specialities,
            "countries_total": Country.objects.count(),
            "specialities_total": Speciality.objects.count(),
        }
    )


@api_view(["GET"])
@permission_classes([AllowAny])
def osm_search(request):
    return _success(
        {
            "results": [],
            "lat": request.GET.get("lat"),
            "lon": request.GET.get("lon"),
        }
    )


@api_view(["GET"])
@permission_classes([AllowAny])
def osm_status(request):
    return _success({"status": "ok"})


@api_view(["GET"])
@permission_classes([AllowAny])
def courses_v1(request):
    courses = [
        {
            "id": "pc-healthy-eating",
            "title": "Healthy Eating Basics",
            "category": "Preventive care",
            "minutes": 12,
            "level": "Beginner",
            "summary": "Simple plate method, portion sizes, reading labels, and hydration.",
            "tags": ["nutrition", "weight", "blood pressure", "cholesterol"],
            "resources": [
                {"title": "USDA MyPlate", "url": "https://www.myplate.gov/"},
                {"title": "NIH Nutrition", "url": "https://www.nhlbi.nih.gov/health-topics/heart-healthy-eating"},
                {"title": "MedlinePlus: Nutrition", "url": "https://medlineplus.gov/nutrition.html"},
            ],
        },
        {
            "id": "pc-physical-activity",
            "title": "Physical Activity for Everyone",
            "category": "Preventive care",
            "minutes": 10,
            "level": "Beginner",
            "summary": "Weekly targets, safe progression, stretching, and injury prevention.",
            "tags": ["fitness", "heart", "weight", "sleep"],
            "resources": [
                {"title": "CDC: Physical Activity", "url": "https://www.cdc.gov/physicalactivity/basics/index.htm"},
                {"title": "WHO: Physical Activity", "url": "https://www.who.int/news-room/fact-sheets/detail/physical-activity"},
            ],
        },
        {
            "id": "pc-blood-pressure",
            "title": "Blood Pressure: Home Monitoring",
            "category": "Preventive care",
            "minutes": 8,
            "level": "Beginner",
            "summary": "How to measure correctly, when to recheck, and warning signs.",
            "tags": ["hypertension", "heart", "monitoring"],
            "resources": [
                {"title": "AHA: Home BP Monitoring", "url": "https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/monitoring-your-blood-pressure-at-home"},
                {"title": "CDC: High Blood Pressure", "url": "https://www.cdc.gov/bloodpressure/index.htm"},
            ],
        },
        {
            "id": "pc-diabetes-prevention",
            "title": "Diabetes Prevention (Prediabetes)",
            "category": "Preventive care",
            "minutes": 14,
            "level": "Beginner",
            "summary": "Risk factors, A1c basics, food swaps, and activity plan.",
            "tags": ["diabetes", "a1c", "nutrition", "weight"],
            "resources": [
                {"title": "CDC: Prediabetes", "url": "https://www.cdc.gov/diabetes/basics/prediabetes.html"},
                {"title": "NIH: Diabetes", "url": "https://www.niddk.nih.gov/health-information/diabetes"},
            ],
        },
        {
            "id": "pc-vaccines-adults",
            "title": "Adult Vaccines Checklist",
            "category": "Preventive care",
            "minutes": 9,
            "level": "Beginner",
            "summary": "Common adult vaccines and how to ask your clinician what you need.",
            "tags": ["immunization", "flu", "covid", "tdap"],
            "resources": [
                {"title": "CDC: Adult Immunization Schedule", "url": "https://www.cdc.gov/vaccines/schedules/hcp/imz/adult.html"},
                {"title": "MedlinePlus: Vaccines", "url": "https://medlineplus.gov/vaccines.html"},
            ],
        },
        {
            "id": "pc-cancer-screening",
            "title": "Cancer Screening Overview",
            "category": "Preventive care",
            "minutes": 11,
            "level": "Beginner",
            "summary": "General screening concepts and preparing questions for your clinician.",
            "tags": ["screening", "colon", "breast", "cervical"],
            "resources": [
                {"title": "USPSTF Recommendations", "url": "https://www.uspreventiveservicestaskforce.org/"},
                {"title": "CDC: Cancer Screening", "url": "https://www.cdc.gov/cancer/dcpc/prevention/screening.htm"},
            ],
        },
        {
            "id": "pc-sleep",
            "title": "Sleep Hygiene",
            "category": "Preventive care",
            "minutes": 8,
            "level": "Beginner",
            "summary": "Routine, light/caffeine tips, and when to seek help for sleep apnea.",
            "tags": ["sleep", "stress", "energy"],
            "resources": [
                {"title": "NIH: Sleep", "url": "https://www.nhlbi.nih.gov/health-topics/sleep-deprivation-and-deficiency"},
                {"title": "MedlinePlus: Sleep", "url": "https://medlineplus.gov/sleepdisorders.html"},
            ],
        },
        {
            "id": "pc-stress",
            "title": "Stress & Anxiety Self-Care",
            "category": "Preventive care",
            "minutes": 10,
            "level": "Beginner",
            "summary": "Breathing, grounding, and when to seek urgent mental health support.",
            "tags": ["mental health", "stress", "anxiety"],
            "resources": [
                {"title": "NIMH: Coping with Stress", "url": "https://www.nimh.nih.gov/health/topics/caring-for-your-mental-health"},
                {"title": "MedlinePlus: Stress", "url": "https://medlineplus.gov/stress.html"},
            ],
        },
        {
            "id": "pc-smoking-cessation",
            "title": "Quit Smoking: First Steps",
            "category": "Preventive care",
            "minutes": 9,
            "level": "Beginner",
            "summary": "Triggers, nicotine replacement basics, and a 7‑day quit plan.",
            "tags": ["smoking", "lungs", "heart"],
            "resources": [
                {"title": "Smokefree.gov", "url": "https://smokefree.gov/"},
                {"title": "CDC: Quit Smoking", "url": "https://www.cdc.gov/tobacco/quit_smoking/index.htm"},
            ],
        },
        {
            "id": "pc-medication-safety",
            "title": "Medication Safety",
            "category": "Preventive care",
            "minutes": 7,
            "level": "Beginner",
            "summary": "How to keep an accurate medication list and avoid common interactions.",
            "tags": ["medications", "safety", "allergies"],
            "resources": [
                {"title": "MedlinePlus: Medicines", "url": "https://medlineplus.gov/druginformation.html"},
                {"title": "FDA: Safe Use", "url": "https://www.fda.gov/drugs/special-features/safe-use-medicines"},
            ],
        },
        {
            "id": "hm-preventive-care-checklist",
            "title": "Health Maintenance Checklist",
            "category": "Health maintenance",
            "minutes": 10,
            "level": "Beginner",
            "summary": "A simple checklist to prepare for annual visits and keep your records up to date.",
            "tags": ["preventive care", "checklist", "annual exam"],
            "resources": [
                {"title": "USPSTF Preventive Care", "url": "https://www.uspreventiveservicestaskforce.org/"},
                {"title": "MedlinePlus: Checkups", "url": "https://medlineplus.gov/ency/article/007465.htm"},
            ],
        },
        {
            "id": "cbt-basics",
            "title": "Cognitive Behavioral Therapy (CBT) Basics",
            "category": "Cognitive therapy",
            "minutes": 15,
            "level": "Beginner",
            "summary": "Understand thoughts-feelings-behaviors cycles and common CBT tools.",
            "tags": ["cbt", "anxiety", "depression", "stress"],
            "resources": [
                {"title": "NHS: CBT", "url": "https://www.nhs.uk/mental-health/talking-therapies-medicine-treatments/talking-therapies-and-counselling/cognitive-behavioural-therapy-cbt/"},
                {"title": "APA: Psychotherapy", "url": "https://www.apa.org/topics/psychotherapy"},
                {"title": "NIMH: Depression", "url": "https://www.nimh.nih.gov/health/topics/depression"},
            ],
        },
        {
            "id": "rehab-pt-ot",
            "title": "PT/OT: Getting Started",
            "category": "Rehabilitation",
            "minutes": 12,
            "level": "Beginner",
            "summary": "What to expect in physical and occupational therapy and how to prepare.",
            "tags": ["pt", "ot", "rehab", "mobility"],
            "resources": [
                {"title": "APTA: Physical Therapy", "url": "https://www.choosept.com/"},
                {"title": "AOTA: Occupational Therapy", "url": "https://www.aota.org/consumers"},
            ],
        },
    ]
    return _success({"courses": courses})


class _ReadAnyWriteAdmin(BasePermission):
    def has_permission(self, request, view):
        if request.method in SAFE_METHODS:
            return True
        return bool(
            request.user
            and request.user.is_authenticated
            and (request.user.is_staff or request.user.is_superuser)
        )


class CountryViewSet(viewsets.ModelViewSet):
    queryset = Country.objects.all()
    serializer_class = CountrySerializer
    permission_classes = [_ReadAnyWriteAdmin]


class SpecialityViewSet(viewsets.ModelViewSet):
    queryset = Speciality.objects.all()
    serializer_class = SpecialitySerializer
    permission_classes = [_ReadAnyWriteAdmin]


class ProviderViewSet(viewsets.ModelViewSet):
    queryset = Provider.objects.select_related("speciality").all()
    serializer_class = ProviderListSerializer
    permission_classes = [_ReadAnyWriteAdmin]


class PatientViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Patient.objects.select_related("user").all()
    serializer_class = PatientSerializer
    permission_classes = [IsAuthenticated]


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def patients_providers(request):
    """Aggregate patients linked to providers / specialities (simplified)."""
    providers = Provider.objects.all()[:50]
    data = ProviderListSerializer(providers, many=True).data
    return _success({"providers": data})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def appointment_list(request):
    patient = Patient.objects.filter(user=request.user).first()
    if not patient:
        return _success({"appointments": []})
    qs = Appointment.objects.filter(patient=patient).select_related("provider", "patient")[:200]
    return _success({"appointments": AppointmentExpandedSerializer(qs, many=True).data})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def appointment_all(request):
    if not (request.user.is_staff or request.user.is_superuser):
        return Response(
            {"status": "error", "message": "Admin only"},
            status=status.HTTP_403_FORBIDDEN,
        )
    qs = (
        Appointment.objects.select_related("provider", "patient")
        .order_by("-id")[:500]
    )
    return _success({"appointments": AppointmentExpandedSerializer(qs, many=True).data})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def appointment_create(request):
    patient = Patient.objects.filter(user=request.user).first()
    if not patient:
        # Auto-create a minimal patient profile so booking works immediately
        # after registration / login (mobile-first).
        email = (request.user.email or "").strip()
        if not email:
            email = f"{request.user.username}@example.com"
        patient = Patient.objects.create(
            user=request.user,
            name=request.user.get_full_name() or request.user.username,
            date_of_birth="Unknown",
            email=email,
            profile_status="auto-created",
        )
    try:
        provider_id = int(request.data.get("provider_id"))
    except (TypeError, ValueError):
        return _error({"provider_id": ["invalid"]})

    d = parse_date(str(request.data.get("date", "")))
    raw_time = str(request.data.get("time", ""))
    t = parse_time(raw_time)
    if t is None and len(raw_time) == 5:
        t = parse_time(raw_time + ":00")

    if not d or not t:
        return _error(
            {"detail": ["Invalid date (YYYY-MM-DD) or time (HH:MM or HH:MM:SS)"]},
            status.HTTP_400_BAD_REQUEST,
        )

    appt = Appointment.objects.create(
        patient=patient,
        provider_id=provider_id,
        date=d,
        time=t,
    )
    return _success({"appointment": AppointmentSerializer(appt).data}, message="Created")


@api_view(["GET"])
@permission_classes([AllowAny])
def vitals_stub(request):
    return _success({"vitals": [], "note": "Wire Vitals model / devices here"})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def er_wait_times(request):
    """
    Proxy ER wait-time analytics from the nginx-upstream API (default: api.mywaitime.com/api/).

    Upstream contract (documented in FRONTEND_API_DOCUMENTATION.md):
      GET /api/hospitals/wait-times/?hospital_id={uuid}
    """
    base = (getattr(settings, "MYWAITIME_UPSTREAM_API_BASE", "") or "").strip()
    if not base:
        base = "https://api.mywaitime.com/api/"
    if not base.endswith("/"):
        base += "/"

    upstream_path = "hospitals/wait-times/"
    params = {}
    hospital_id = request.query_params.get("hospital_id") or request.query_params.get("id")
    if hospital_id:
        params["hospital_id"] = hospital_id

    url = base + upstream_path
    if params:
        url += "?" + urlencode(params)

    auth = request.headers.get("Authorization", "")
    headers = {"Accept": "application/json"}
    if auth:
        headers["Authorization"] = auth

    req = Request(url, headers=headers, method="GET")
    try:
        with urlopen(req, timeout=15) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                data = json.loads(raw) if raw else {}
            except json.JSONDecodeError:
                data = {"raw": raw}
            return Response(data, status=resp.status)
    except HTTPError as e:
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            body = ""
        return Response(
            {"status": "error", "message": "Upstream error", "upstream_status": e.code, "body": body},
            status=status.HTTP_502_BAD_GATEWAY,
        )
    except URLError as e:
        return Response(
            {"status": "error", "message": "Upstream unreachable", "detail": str(e)},
            status=status.HTTP_502_BAD_GATEWAY,
        )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def change_password(request):
    pw = request.data.get("new_password")
    if not pw or len(pw) < 8:
        return _error({"new_password": ["min 8 chars"]})
    request.user.set_password(pw)
    request.user.save()
    return _success(message="Password changed")


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def replicate_token_env(request):
    import os

    token = os.environ.get("REPLICATE_TOKEN", "")
    if not token:
        # Don't treat "not configured" as a server error.
        return Response(
            {
                "success": False,
                "configured": False,
                "message": "Replicate token is not configured on the server (REPLICATE_TOKEN not set).",
            },
            status=status.HTTP_200_OK,
        )

    # Avoid returning the raw secret in API responses.
    masked = token
    if len(masked) > 10:
        masked = masked[:4] + "…" + masked[-4:]
    else:
        masked = "configured"
    return Response(
        {
            "success": True,
            "configured": True,
            "replicate_token_masked": masked,
        },
        status=status.HTTP_200_OK,
    )


class NutritionEntryViewSet(viewsets.ModelViewSet):
    serializer_class = NutritionEntrySerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return NutritionEntry.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def invoices_list(request):
    if request.method == "GET":
        patient = Patient.objects.filter(user=request.user).first()
        if not patient:
            return _success({"invoices": []})
        qs = Invoices.objects.filter(patient=patient)[:100]
        return _success({"invoices": InvoicesSerializer(qs, many=True).data})
    elif request.method == "POST":
        patient = Patient.objects.filter(user=request.user).first()
        if not patient:
            return _error({"patient": ["No patient profile"]}, status.HTTP_404_NOT_FOUND)
        ser = InvoicesSerializer(data=request.data)
        if ser.is_valid():
            ser.save(patient=patient)
            return _success({"invoice": ser.data}, message="Created")
        return _error(ser.errors)


@api_view(["GET"])
@permission_classes([AllowAny])
def timezone_list(request):
    qs = Timezone.objects.all()[:200]
    return _success({"timezones": TimezoneSerializer(qs, many=True).data})


@api_view(["GET", "POST", "PUT", "DELETE"])
@permission_classes([IsAuthenticated])
def general_settings(request, key=None):
    if request.method == "GET":
        if key:
            try:
                obj = General.objects.get(key=key)
                return _success({"key": obj.key, "value": obj.value})
            except General.DoesNotExist:
                return _error({"detail": ["Not found"]}, status.HTTP_404_NOT_FOUND)
        qs = General.objects.all()[:100]
        return _success({"settings": GeneralSerializer(qs, many=True).data})
    elif request.method == "POST":
        key = request.data.get("key")
        value = request.data.get("value", "")
        if not key:
            return _error({"key": ["required"]})
        obj, _ = General.objects.update_or_create(key=key, defaults={"value": value})
        return _success({"key": obj.key, "value": obj.value}, message="Saved")


@api_view(["GET", "POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def medical_records_list(request):
    """`GET|POST /api/medical-records/` — list/create (stub for local dev)."""
    if request.method == "GET":
        sample = [
            {
                "id": "demo-1",
                "title": "Annual wellness visit",
                "record_type": "Visit summary",
                "summary": "Vitals stable. Follow up in 12 months.",
                "provider_name": "Dr. Demo",
                "facility_name": "Demo Medical",
                "recorded_at": "2026-01-15T10:00:00Z",
                "ai_highlight": "No red flags; cholesterol trending down.",
            }
        ]
        return _success({"results": sample})
    return _success({"id": "new-stub"}, message="Created (stub)")


@api_view(["GET", "PATCH", "DELETE"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def medical_record_detail(request, record_id):
    """`GET|PATCH|DELETE /api/medical-records/<id>/`"""
    if request.method == "GET":
        return _success(
            {
                "id": record_id,
                "title": "Medical record",
                "record_type": "Detail",
                "summary": "Stub detail — replace with production medical-records handler.",
                "provider_name": "Dr. Demo",
                "facility_name": "Demo Medical",
                "ai_highlight": "Key vitals within normal limits.",
            }
        )
    return _success(message="OK (stub)")


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def medical_records_ai_assist(request):
    """`POST /api/medical-records/ai-assist/` body: query, optional record_ids."""
    body = request.data if isinstance(request.data, dict) else {}
    q = str(body.get("query") or body.get("prompt") or "")
    return _success(
        {
            "summary": (
                "Local scaffold only. Deploy the full API for real AI over charts. "
                "Your question is echoed below."
            ),
            "suggestions": [
                "Book follow-up if symptoms change.",
                "Bring this summary to your next appointment.",
            ],
            "query_echo": q,
        },
        message="AI assist (stub)",
    )
