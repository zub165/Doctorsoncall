import json

from django.contrib.auth import authenticate
from django.utils.dateparse import parse_date, parse_time
from django.conf import settings
from django.utils import timezone
from django.utils.http import urlsafe_base64_encode, urlsafe_base64_decode
from django.utils.encoding import force_bytes, force_str
from django.contrib.auth.tokens import PasswordResetTokenGenerator
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
    Plan,
    Provider,
    Role,
    Speciality,
    Timezone,
    PatientDocument,
    PatientShare,
    PatientSubscription,
    PatientVital,
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
    PlanSerializer,
    ProviderListSerializer,
    RegisterSerializer,
    RoleSerializer,
    SpecialitySerializer,
    TimezoneSerializer,
    PatientDocumentSerializer,
    PatientShareSerializer,
    PatientSubscriptionSerializer,
    PatientVitalSerializer,
)


def _is_staffish(user):
    return bool(getattr(user, "is_staff", False) or getattr(user, "is_superuser", False))


def _get_patient_for_user(user):
    return Patient.objects.filter(user=user).first()


_pw_reset_tokens = PasswordResetTokenGenerator()


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
@permission_classes([AllowAny])
def feedback_submit(request):
    text = request.data.get("feedback") or request.data.get("message")
    if not text:
        return _error({"feedback": ["required"]})
    user = request.user if getattr(request, "user", None) and request.user.is_authenticated else None
    Feedback.objects.create(user=user, feedback=str(text).strip()[:5000])
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


class PlanViewSet(viewsets.ModelViewSet):
    queryset = Plan.objects.all()
    serializer_class = PlanSerializer
    permission_classes = [_ReadAnyWriteAdmin]

    def list(self, request, *args, **kwargs):
        want_fixture = (request.query_params.get("fixture") or "").strip().lower() in (
            "1",
            "true",
            "yes",
            "y",
        )
        if want_fixture and not Plan.objects.exists():
            Plan.objects.create(
                plan_name="Basic",
                duration="Monthly",
                price="9.99",
                number_appointments="1",
                ai_bot="no",
                discount="",
            )
            Plan.objects.create(
                plan_name="Plus",
                duration="Monthly",
                price="29.99",
                number_appointments="3",
                ai_bot="yes",
                discount="",
            )
            Plan.objects.create(
                plan_name="Premium",
                duration="Monthly",
                price="49.99",
                number_appointments="Unlimited",
                ai_bot="yes",
                discount="",
            )
        return super().list(request, *args, **kwargs)


class RoleViewSet(viewsets.ModelViewSet):
    queryset = Role.objects.all()
    serializer_class = RoleSerializer
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


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def vitals_list(request):
    """
    GET: list vitals
      - staff: all vitals (latest 200)
      - patient: their own vitals (latest 200)

    POST: create vitals for current patient
      accepts: height_cm, weight_kg, temperature_c, bp_sys, bp_dia, pulse_bpm,
               resp_min, spo2, glucose_mgdl, notes
    """
    user = request.user
    is_staff = _is_staffish(user)
    patient = _get_patient_for_user(user)

    if request.method == "GET":
        qs = PatientVital.objects.all()
        if not is_staff:
            if not patient:
                return _success({"vitals": []})
            qs = qs.filter(patient=patient)
        ser = PatientVitalSerializer(qs[:200], many=True)
        return _success({"vitals": ser.data})

    # POST
    if not patient and not is_staff:
        return _error(
            {"detail": ["Patient profile not found"]},
            status.HTTP_400_BAD_REQUEST,
        )

    # Staff can optionally pass patient_id; otherwise use self patient
    target_patient = patient
    if is_staff:
        pid = request.data.get("patient_id") or request.data.get("patient")
        if pid:
            target_patient = Patient.objects.filter(id=pid).first()
    if not target_patient:
        return _error({"detail": ["patient_id required"]}, status.HTTP_400_BAD_REQUEST)

    v = PatientVital.objects.create(
        patient=target_patient,
        recorded_by=user,
        height_cm=request.data.get("height_cm") or None,
        weight_kg=request.data.get("weight_kg") or None,
        temperature_c=request.data.get("temperature_c") or None,
        bp_sys=request.data.get("bp_sys") or None,
        bp_dia=request.data.get("bp_dia") or None,
        pulse_bpm=request.data.get("pulse_bpm") or None,
        resp_min=request.data.get("resp_min") or None,
        spo2=request.data.get("spo2") or None,
        glucose_mgdl=request.data.get("glucose_mgdl") or None,
        notes=str(request.data.get("notes") or "").strip(),
    )
    return _success({"vital": PatientVitalSerializer(v).data}, message="Created")


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


@api_view(["POST"])
@permission_classes([AllowAny])
def password_reset_request(request):
    """
    Send a password reset email.
    Body: { email }
    Always returns success to avoid user enumeration.
    """
    from django.core.mail import send_mail

    email = str(request.data.get("email") or "").strip()
    if not email:
        return _error({"email": ["required"]})

    user = User.objects.filter(email__iexact=email).first()
    if user:
        uid = urlsafe_base64_encode(force_bytes(user.pk))
        token = _pw_reset_tokens.make_token(user)
        link = request.build_absolute_uri(f"/reset-password/{uid}/{token}/")
        body = (
            "You requested a password reset for Doctor On Call.\n\n"
            f"Reset link: {link}\n\n"
            "If you did not request this, ignore this email."
        )
        try:
            send_mail(
                subject="Reset your Doctor On Call password",
                message=body,
                from_email=getattr(settings, "DEFAULT_FROM_EMAIL", None),
                recipient_list=[email],
                fail_silently=True,
            )
        except Exception:
            pass

    return _success(message="If that email exists, a reset link has been sent.")


@api_view(["POST"])
@permission_classes([AllowAny])
def password_reset_confirm(request):
    """
    Confirm password reset.
    Body: { uid, token, new_password }
    """
    uid = str(request.data.get("uid") or "").strip()
    token = str(request.data.get("token") or "").strip()
    new_password = str(request.data.get("new_password") or "").strip()
    if not uid or not token or not new_password:
        return _error({"detail": ["uid, token, new_password required"]})
    if len(new_password) < 8:
        return _error({"new_password": ["min 8 chars"]})
    try:
        user_id = force_str(urlsafe_base64_decode(uid))
        user = User.objects.filter(pk=user_id).first()
    except Exception:
        user = None
    if not user or not _pw_reset_tokens.check_token(user, token):
        return _error({"detail": ["Invalid or expired reset link"]}, status.HTTP_400_BAD_REQUEST)
    user.set_password(new_password)
    user.save()
    return _success(message="Password reset OK")


@api_view(["GET", "POST"])
@permission_classes([AllowAny])
def password_reset_page(request, uid, token):
    """
    Minimal HTML password reset page (for users coming from email).
    """
    if request.method == "GET":
        html = f"""<!doctype html>
<html>
<head><meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Reset password</title></head>
<body style="font-family: system-ui, -apple-system, sans-serif; padding: 24px; max-width: 520px; margin: 0 auto;">
  <h2>Reset your password</h2>
  <p>Enter a new password for your Doctor On Call account.</p>
  <form method="post" style="display: grid; gap: 12px;">
    <input type="password" name="new_password" placeholder="New password (min 8 chars)" minlength="8" required
      style="padding: 12px; border: 1px solid #ddd; border-radius: 10px; font-size: 16px;" />
    <button type="submit" style="padding: 12px; border-radius: 10px; border: 0; background: #d32f2f; color: white; font-weight: 700;">
      Reset password
    </button>
  </form>
</body>
</html>"""
        return Response(html, content_type="text/html")

    pw = str(request.data.get("new_password") or request.POST.get("new_password") or "").strip()
    if len(pw) < 8:
        return Response("Password too short", status=400, content_type="text/plain")
    try:
        user_id = force_str(urlsafe_base64_decode(uid))
        user = User.objects.filter(pk=user_id).first()
    except Exception:
        user = None
    if not user or not _pw_reset_tokens.check_token(user, token):
        return Response("Invalid or expired reset link", status=400, content_type="text/plain")
    user.set_password(pw)
    user.save()
    return Response("Password reset OK. You can close this tab and sign in.", content_type="text/plain")


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
        want_fixture = (request.query_params.get("fixture") or "").strip().lower() in (
            "1",
            "true",
            "yes",
            "y",
        )
        if want_fixture and not qs.exists():
            # Create a small demo set so mobile UI isn't empty in dev/demo.
            today = timezone.now().date()
            Invoices.objects.create(
                patient=patient,
                name="Consultation fee",
                email=getattr(request.user, "email", "") or "",
                amount="49.00",
                invoice_date=today,
            )
            Invoices.objects.create(
                patient=patient,
                name="Lab panel (screening)",
                email=getattr(request.user, "email", "") or "",
                amount="89.00",
                invoice_date=today,
            )
            Invoices.objects.create(
                patient=patient,
                name="Follow-up visit",
                email=getattr(request.user, "email", "") or "",
                amount="29.00",
                invoice_date=today,
            )
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
    """`GET|POST /api/medical-records/` — list/create."""
    user = request.user

    # Authorization: staff + providers can view all or a specific patient_id.
    patient_id = request.query_params.get("patient_id") or request.data.get("patient_id")
    qs = MedicalRecord.objects.select_related("patient").all()
    if _is_staffish(user) or user.provider_profiles.exists():
        if patient_id:
            qs = qs.filter(patient_id=patient_id)
    else:
        p = _get_patient_for_user(user)
        if not p:
            return _success({"results": []})
        qs = qs.filter(patient=p)

    if request.method == "GET":
        ser = MedicalRecordSerializer(qs[:200], many=True)
        return _success({"results": ser.data})

    # POST create (minimal)
    if not (_is_staffish(user) or user.provider_profiles.exists()):
        p = _get_patient_for_user(user)
        if not p:
            return _error({"patient": ["No patient profile found for this user."]})
        patient_id = p.id

    ser = MedicalRecordSerializer(
        data={
            "patient": patient_id,
            "source_url": request.data.get("source_url") or "",
            "source_system": request.data.get("source_system") or "",
            "title": request.data.get("title") or "",
            "raw_payload": request.data.get("raw_payload") or "",
            "ai_summary": request.data.get("ai_summary") or "",
            "merged_by": user.id if (_is_staffish(user) or user.provider_profiles.exists()) else None,
        }
    )
    if ser.is_valid():
        obj = ser.save()
        return _success({"record": MedicalRecordSerializer(obj).data}, message="Created")
    return _error(ser.errors)


@api_view(["GET", "PATCH", "DELETE"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def medical_record_detail(request, record_id):
    """`GET|PATCH|DELETE /api/medical-records/<id>/`"""
    user = request.user
    rec = MedicalRecord.objects.filter(id=record_id).first()
    if not rec:
        return _error({"record": ["not found"]}, status.HTTP_404_NOT_FOUND)

    # Authorization
    if not (_is_staffish(user) or user.provider_profiles.exists()):
        p = _get_patient_for_user(user)
        if not p or rec.patient_id != p.id:
            return _error({"detail": ["forbidden"]}, status.HTTP_403_FORBIDDEN)

    if request.method == "GET":
        return _success({"record": MedicalRecordSerializer(rec).data})

    if request.method == "DELETE":
        rec.delete()
        return _success(message="Deleted")

    # PATCH
    ser = MedicalRecordSerializer(rec, data=request.data, partial=True)
    if ser.is_valid():
        ser.save(merged_by=user if (_is_staffish(user) or user.provider_profiles.exists()) else rec.merged_by)
        return _success({"record": ser.data}, message="Updated")
    return _error(ser.errors)


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def medical_records_ai_assist(request):
    """`POST /api/medical-records/ai-assist/` body: query, optional record_ids, optional kind."""
    body = request.data if isinstance(request.data, dict) else {}
    q = str(body.get("query") or body.get("prompt") or "")
    if not q.strip():
        return _error({"query": ["query (or prompt) is required"]})

    kind = str(body.get("kind") or "").strip().lower()
    soap_mode = kind in ("soap", "doctor_soap", "soap_note")

    # Call local Ollama (no streaming).
    base = (getattr(settings, "OLLAMA_BASE_URL", "") or "").strip() or "http://127.0.0.1:11434"
    model = (getattr(settings, "OLLAMA_MODEL", "") or "").strip() or "llama3.1"
    url = base.rstrip("/") + "/api/generate"

    if soap_mode:
        system = (
            "You help clinicians structure visit documentation. Output ONLY valid JSON, no markdown, "
            'no prose before or after. Use exactly these keys: "subjective", "objective", '
            '"assessment", "plan". Strings only. Be concise; do not invent facts not stated '
            "in the input. Flag generic red-flag symptoms if explicitly mentioned."
        )
    else:
        system = (
            "You are a medical assistant. Provide general information only, not a diagnosis. "
            "If symptoms sound severe (chest pain, trouble breathing, stroke signs, severe bleeding), "
            "recommend urgent/emergency care. Keep it concise with bullet points and next steps."
        )
    prompt = f"{system}\n\nUSER:\n{q}\n\nASSISTANT:\n"

    try:
        payload = json.dumps(
            {
                "model": model,
                "prompt": prompt,
                "stream": False,
            }
        ).encode("utf-8")
        req = Request(
            url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8", errors="ignore")
        out = json.loads(raw) if raw else {}
        answer = str(out.get("response") or "").strip()
        if not answer:
            answer = "No response from model."

        soap_json = {}
        if soap_mode and answer:
            try:
                s = answer.strip()
                lb = s.find("{")
                rb = s.rfind("}")
                if lb >= 0 and rb > lb:
                    soap_json = json.loads(s[lb : rb + 1])
                    if not isinstance(soap_json, dict):
                        soap_json = {}
            except Exception:
                soap_json = {}

        payload = {
            "answer": answer,
            "summary": answer,
            "model": model,
            "kind": "soap" if soap_mode else "general",
        }
        if soap_mode and soap_json:
            payload["soap"] = {
                "subjective": str(soap_json.get("subjective", "")).strip(),
                "objective": str(soap_json.get("objective", "")).strip(),
                "assessment": str(soap_json.get("assessment", "")).strip(),
                "plan": str(soap_json.get("plan", "")).strip(),
            }

        return _success(payload, message="AI assist")
    except HTTPError as e:
        try:
            msg = e.read().decode("utf-8", errors="ignore")
        except Exception:
            msg = str(e)
        return Response(
            {"status": "error", "message": "Ollama error", "detail": msg},
            status=status.HTTP_502_BAD_GATEWAY,
        )
    except URLError as e:
        return Response(
            {"status": "error", "message": "Ollama unreachable", "detail": str(e)},
            status=status.HTTP_502_BAD_GATEWAY,
        )
    except Exception as e:
        return Response(
            {"status": "error", "message": "AI error", "detail": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )


HIPAA_DISCLAIMER = (
    "Disclaimer: This feature is for care coordination only and does not provide medical advice. "
    "Do not share highly sensitive information unless necessary. "
    "AI summaries may be incomplete or incorrect; clinicians must verify against source records. "
    "If you have an emergency, call local emergency services."
)


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def shares_mine(request):
    """Patient view: shares created by the logged-in patient."""
    user = request.user
    p = _get_patient_for_user(user)
    if not p:
        return _success({"results": [], "disclaimer": HIPAA_DISCLAIMER})
    qs = PatientShare.objects.filter(patient=p)[:200]
    ser = PatientShareSerializer(qs, many=True)
    return _success({"results": ser.data, "disclaimer": HIPAA_DISCLAIMER})


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def shares_inbox(request):
    """Provider/staff view: shares sent to this provider."""
    user = request.user
    if _is_staffish(user):
        qs = PatientShare.objects.all()[:200]
    else:
        prov = Provider.objects.filter(user=user).first()
        if not prov:
            return _error({"detail": ["Only providers can access inbox."]}, status.HTTP_403_FORBIDDEN)
        qs = PatientShare.objects.filter(provider=prov)[:200]
    ser = PatientShareSerializer(qs, many=True)
    return _success({"results": ser.data, "disclaimer": HIPAA_DISCLAIMER})


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def shares_create(request):
    """
    Patient creates a share. Body:
      - provider_id (required)
      - patient_note (optional)
      - include_patient_email (optional bool)
    """
    user = request.user
    p = _get_patient_for_user(user)
    if not p:
        return _error({"patient": ["No patient profile found for this user."]})
    try:
        provider_id = int(request.data.get("provider_id"))
    except (TypeError, ValueError):
        return _error({"provider_id": ["invalid"]})
    prov = Provider.objects.filter(id=provider_id).first()
    if not prov:
        return _error({"provider_id": ["not found"]}, status.HTTP_404_NOT_FOUND)

    note = str(request.data.get("patient_note") or request.data.get("note") or "").strip()[:8000]
    include_email = bool(request.data.get("include_patient_email") in (True, "true", "1", 1, "yes"))
    client_summary = request.data.get("ai_summary") or request.data.get("summary") or ""
    if not isinstance(client_summary, str):
        client_summary = json.dumps(client_summary)
    client_summary = str(client_summary).strip()

    # If the client already generated OCR+AI summary (privacy mode),
    # accept it directly and do not attempt LLM generation server-side.
    if client_summary:
        share = PatientShare.objects.create(
            patient=p,
            provider=prov,
            patient_note=note,
            ai_summary=client_summary[:20000],
            include_patient_email=include_email,
            status=PatientShare.Status.SENT,
        )
        ser = PatientShareSerializer(share)
        return _success(
            {"share": ser.data, "disclaimer": HIPAA_DISCLAIMER},
            message="Shared",
        )

    # Build an AI context from the patient's most recent records + their note.
    recent = MedicalRecord.objects.filter(patient=p).order_by("-id")[:10]
    recent_text = "\n".join(
        [f"- {r.title}: {(r.ai_summary or r.raw_payload or '')}"[:2000] for r in recent]
    ).strip()
    ctx = f"PATIENT NOTE:\n{note}\n\nRECENT RECORDS:\n{recent_text}\n"
    q = (
        "Summarize this patient's shared information for the clinician. "
        "Use bullet points, highlight urgent red flags, and list follow-up questions."
    )

    base = (getattr(settings, "OLLAMA_BASE_URL", "") or "").strip() or "http://127.0.0.1:11434"
    model = (getattr(settings, "OLLAMA_MODEL", "") or "").strip() or "llama3.1"
    url = base.rstrip("/") + "/api/generate"
    system = (
        "You are a medical assistant. Provide general information only, not a diagnosis. "
        "Keep it concise. Do not invent facts. If data is missing, say so."
    )
    prompt = f"{system}\n\nTASK:\n{q}\n\nDATA:\n{ctx}\n\nASSISTANT:\n"
    summary = ""
    try:
        payload = json.dumps({"model": model, "prompt": prompt, "stream": False}).encode("utf-8")
        req = Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
        with urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8", errors="ignore")
        out = json.loads(raw) if raw else {}
        summary = str(out.get("response") or "").strip()
    except Exception as e:
        summary = f"(AI unavailable) {e}"

    share = PatientShare.objects.create(
        patient=p,
        provider=prov,
        patient_note=note,
        ai_summary=summary[:20000],
        include_patient_email=include_email,
        status=PatientShare.Status.SENT,
    )
    ser = PatientShareSerializer(share)
    return _success({"share": ser.data, "disclaimer": HIPAA_DISCLAIMER}, message="Shared")


@api_view(["DELETE"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def shares_delete(request, share_id: int):
    """Provider/staff can delete a share from server (or patient deletes their own)."""
    user = request.user
    share = PatientShare.objects.filter(id=share_id).first()
    if not share:
        return _error({"share": ["not found"]}, status.HTTP_404_NOT_FOUND)
    if _is_staffish(user):
        share.delete()
        return _success(message="Deleted")
    prov = Provider.objects.filter(user=user).first()
    pat = _get_patient_for_user(user)
    if (prov and share.provider_id == prov.id) or (pat and share.patient_id == pat.id):
        share.delete()
        return _success(message="Deleted")
    return _error({"detail": ["forbidden"]}, status.HTTP_403_FORBIDDEN)


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def shares_email_patient(request, share_id: int):
    """Provider/staff can email the summary to the patient (if consented)."""
    from django.core.mail import send_mail

    user = request.user
    share = PatientShare.objects.select_related("patient").filter(id=share_id).first()
    if not share:
        return _error({"share": ["not found"]}, status.HTTP_404_NOT_FOUND)

    if not (_is_staffish(user) or Provider.objects.filter(user=user, id=share.provider_id).exists()):
        return _error({"detail": ["forbidden"]}, status.HTTP_403_FORBIDDEN)

    patient_email = share.patient.email if share.include_patient_email else ""
    if not patient_email:
        return _error({"email": ["Patient did not consent to email sharing."]}, status.HTTP_400_BAD_REQUEST)

    subject = "Your shared medical summary"
    body = f"{HIPAA_DISCLAIMER}\n\nSUMMARY:\n{share.ai_summary}\n\nPATIENT NOTE:\n{share.patient_note}\n"
    try:
        send_mail(subject, body, None, [patient_email], fail_silently=False)
        return _success(message="Email sent")
    except Exception as e:
        return _error({"email": [str(e)]}, status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["PATCH"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def patient_me_update(request):
    """
    Patient updates their own profile.

    Body supports a subset of Patient fields:
      - name, date_of_birth, email, city, country, birth_place, identity_no

    NOTE: This is consent-based and intended for the patient's own account.
    """
    user = request.user
    patient = Patient.objects.filter(user=user).first()
    if not patient:
        # Create minimal profile if missing (mirrors appointment_create behavior).
        email = (user.email or "").strip() or "unknown@example.com"
        patient = Patient.objects.create(
            user=user,
            name=user.get_full_name() or user.username,
            date_of_birth="Unknown",
            email=email,
            profile_status="self-created",
        )

    allowed = {"name", "date_of_birth", "email", "city", "country", "birth_place", "identity_no"}
    patch = {k: v for k, v in (request.data or {}).items() if k in allowed}
    ser = PatientSerializer(patient, data=patch, partial=True)
    if ser.is_valid():
        obj = ser.save()
        return _success({"patient": PatientSerializer(obj).data}, message="Updated")
    return _error(ser.errors)


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def billing_status(request):
    """Return active subscription (if any) for current patient."""
    p = Patient.objects.filter(user=request.user).first()
    if not p:
        return _success({"active": None})
    sub = (
        PatientSubscription.objects.filter(patient=p, status=PatientSubscription.Status.ACTIVE)
        .select_related("plan")
        .first()
    )
    return _success({"active": PatientSubscriptionSerializer(sub).data if sub else None})


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def billing_checkout(request):
    """
    Create a Stripe Checkout session for a plan.
    Body: { plan_id }
    Returns: { url }
    """
    import stripe

    if not getattr(settings, "STRIPE_SECRET_KEY", ""):
        return _error({"billing": ["Stripe is not configured on server."]}, status.HTTP_501_NOT_IMPLEMENTED)

    p = Patient.objects.filter(user=request.user).first()
    if not p:
        return _error({"patient": ["No patient profile"]}, status.HTTP_404_NOT_FOUND)
    try:
        plan_id = int(request.data.get("plan_id"))
    except (TypeError, ValueError):
        return _error({"plan_id": ["invalid"]})
    plan = Plan.objects.filter(id=plan_id).first()
    if not plan:
        return _error({"plan_id": ["not found"]}, status.HTTP_404_NOT_FOUND)

    # Amount handling: plan.price is stored as string (legacy). Assume USD, monthly unless duration says otherwise.
    try:
        amount_cents = int(round(float(str(plan.price).replace("$", "").strip()) * 100))
    except Exception:
        return _error({"price": ["Plan price invalid. Use numeric like 49 or 49.00"]})
    if amount_cents <= 0:
        return _error({"price": ["Plan price must be > 0"]})

    stripe.api_key = settings.STRIPE_SECRET_KEY
    frontend = (getattr(settings, "FRONTEND_BASE_URL", "") or "").rstrip("/") or "https://docsoncalls.com"
    success_url = frontend + "/?billing=success"
    cancel_url = frontend + "/?billing=cancel"

    # Customer identity: use patient email when available.
    customer_email = (p.email or "").strip() or (request.user.email or "").strip()

    session = stripe.checkout.Session.create(
        mode="payment",
        success_url=success_url,
        cancel_url=cancel_url,
        customer_email=customer_email or None,
        line_items=[
            {
                "price_data": {
                    "currency": "usd",
                    "product_data": {"name": f"DocOnCalls plan: {plan.plan_name}"},
                    "unit_amount": amount_cents,
                },
                "quantity": 1,
            }
        ],
        metadata={
            "patient_id": str(p.id),
            "plan_id": str(plan.id),
        },
    )

    PatientSubscription.objects.create(
        patient=p,
        plan=plan,
        status=PatientSubscription.Status.PENDING,
        stripe_session_id=session.id,
    )
    return _success({"url": session.url, "session_id": session.id}, message="Checkout created")


@api_view(["POST"])
@permission_classes([AllowAny])
def billing_webhook(request):
    """Stripe webhook: marks subscription active after successful checkout."""
    import stripe

    secret = getattr(settings, "STRIPE_WEBHOOK_SECRET", "").strip()
    if not secret:
        return Response({"ok": False, "message": "Webhook secret not configured"}, status=200)

    payload = request.body
    sig_header = request.headers.get("Stripe-Signature", "")
    try:
        event = stripe.Webhook.construct_event(payload, sig_header, secret)
    except Exception:
        return Response({"ok": False}, status=400)

    etype = event.get("type")
    if etype == "checkout.session.completed":
        obj = event["data"]["object"]
        session_id = obj.get("id", "")
        md = obj.get("metadata") or {}
        patient_id = md.get("patient_id")
        plan_id = md.get("plan_id")
        sub = PatientSubscription.objects.filter(stripe_session_id=session_id).first()
        if sub:
            sub.status = PatientSubscription.Status.ACTIVE
            sub.stripe_customer_id = obj.get("customer") or sub.stripe_customer_id
            sub.save(update_fields=["status", "stripe_customer_id"])
        elif patient_id and plan_id:
            PatientSubscription.objects.create(
                patient_id=patient_id,
                plan_id=plan_id,
                status=PatientSubscription.Status.ACTIVE,
                stripe_session_id=session_id,
                stripe_customer_id=obj.get("customer") or "",
            )

    return Response({"ok": True}, status=200)
