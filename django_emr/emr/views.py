import errno
import json
import socket

from django.contrib.auth import authenticate
from django.http import HttpResponse
from django.utils.dateparse import parse_date, parse_time
from django.conf import settings
from django.utils import timezone
from django.utils.http import urlsafe_base64_encode, urlsafe_base64_decode
from django.utils.encoding import force_bytes, force_str
from django.contrib.auth.tokens import PasswordResetTokenGenerator
from urllib.parse import quote, urlencode, urlparse
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

from .authentication import OptionalTokenAuthentication
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
    ProviderPayout,
    ProviderTransaction,
    Role,
    Speciality,
    Timezone,
    PatientDocument,
    PatientShare,
    PatientSubscription,
    PatientVital,
    VisitNote,
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
    PatientSelfSerializer,
    PatientSelfUpdateSerializer,
    PlanSerializer,
    ProviderListSerializer,
    ProviderPayoutSerializer,
    ProviderSelfSerializer,
    ProviderSelfUpdateSerializer,
    ProviderTransactionSerializer,
    RegisterSerializer,
    RoleSerializer,
    SpecialitySerializer,
    TimezoneSerializer,
    PatientDocumentSerializer,
    PatientShareSerializer,
    PatientSubscriptionSerializer,
    PatientVitalSerializer,
    VisitNoteSerializer,
)


def _is_staffish(user):
    return bool(getattr(user, "is_staff", False) or getattr(user, "is_superuser", False))


def _get_patient_for_user(user):
    return Patient.objects.filter(user=user).first()


def _haversine_km(lat1, lon1, lat2, lon2):
    """Great-circle distance in km."""
    from math import asin, cos, radians, sin, sqrt

    la1, lo1, la2, lo2 = map(radians, [lat1, lon1, lat2, lon2])
    dlat = la2 - la1
    dlon = lo2 - lo1
    a = sin(dlat / 2) ** 2 + cos(la1) * cos(la2) * sin(dlon / 2) ** 2
    return 6371.0 * 2 * asin(sqrt(min(1.0, a)))


def _mywaitime_api_base():
    base = (getattr(settings, "MYWAITIME_UPSTREAM_API_BASE", "") or "").strip()
    if not base:
        base = "https://api.mywaitime.com/api/"
    if not base.endswith("/"):
        base += "/"
    return base


def _parse_plan_appointment_limit(raw):
    """Plan.number_appointments → int cap per month, or None = unlimited."""
    s = (str(raw or "")).strip().lower()
    if s in ("unlimited", "∞", "inf", "none", "all"):
        return None
    try:
        return max(0, int(float(s)))
    except (TypeError, ValueError):
        return None


def _patient_subscription_allowance(patient):
    """Visits included in the patient's active App Store / Play plan (RevenueCat-backed)."""
    sub = (
        PatientSubscription.objects.filter(
            patient=patient, status=PatientSubscription.Status.ACTIVE
        )
        .select_related("plan")
        .first()
    )
    if not sub or not sub.plan_id:
        return {
            "has_subscription": False,
            "plan_name": None,
            "visits_included": None,
            "visits_used_this_month": 0,
            "visits_remaining": None,
            "covered_visit_available": False,
        }

    limit = _parse_plan_appointment_limit(sub.plan.number_appointments)
    now = timezone.now()
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    if now.month == 12:
        next_month_start = month_start.replace(year=now.year + 1, month=1)
    else:
        next_month_start = month_start.replace(month=now.month + 1)
    used = Appointment.objects.filter(
        patient=patient,
        date__gte=month_start.date(),
        date__lt=next_month_start.date(),
    ).count()
    remaining = None
    covered = True
    if limit is not None:
        remaining = max(0, limit - used)
        covered = remaining > 0

    return {
        "has_subscription": True,
        "plan_name": sub.plan.plan_name,
        "visits_included": limit,
        "visits_used_this_month": used,
        "visits_remaining": remaining,
        "covered_visit_available": covered,
    }


def _provider_offers_free_consultation(provider):
    fee = provider.consultation_fee
    return fee is None or float(fee or 0) <= 0


def _try_int_hospital_pk(hospital_id):
    try:
        return int(hospital_id)
    except (TypeError, ValueError):
        return None


def _proxy_hospital_upstream_get(request, hospital_id, subpath=""):
    """Proxy Finder/MyWaitime hospital routes for non-integer UUID ids."""
    path = f"hospitals/{hospital_id}/"
    if subpath:
        path += subpath.strip("/") + "/"
    auth = request.headers.get("Authorization", "")
    try:
        upstream = _proxy_mywaitime_get(path, {}, auth_header=auth)
    except HTTPError as e:
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            body = ""
        return Response(
            {
                "status": "error",
                "message": "Hospital not found upstream",
                "upstream_status": e.code,
                "body": body[:2000],
            },
            status=status.HTTP_404_NOT_FOUND if e.code == 404 else status.HTTP_502_BAD_GATEWAY,
        )
    except URLError as e:
        return Response(
            {"status": "error", "message": "Upstream unreachable", "detail": str(e)},
            status=status.HTTP_502_BAD_GATEWAY,
        )
    if isinstance(upstream, dict) and upstream.get("status") == "error":
        return Response(upstream, status=status.HTTP_404_NOT_FOUND)
    return Response(upstream if isinstance(upstream, dict) else {"data": upstream})


def _appointment_billing_hint(patient, provider, allowance):
    return {
        "visit_allowance": allowance,
        "provider_offers_free_consultation": (
            _provider_offers_free_consultation(provider) if provider else False
        ),
        "suggested_consultation_fee": (
            float(provider.consultation_fee)
            if provider and provider.consultation_fee is not None
            else None
        ),
        "extra_visit_note": (
            "Included in your plan — no extra charge for this booking."
            if allowance.get("covered_visit_available")
            else "Extra visit: doctor may send an invoice (platform fee applies)."
        ),
    }


def _proxy_mywaitime_get(path, params, auth_header=""):
    """GET upstream MyWaitime (or nginx :3015) JSON API."""
    base = _mywaitime_api_base()
    qs = urlencode({k: v for k, v in params.items() if v not in (None, "")})
    url = base + path.lstrip("/")
    if qs:
        url += ("&" if "?" in url else "?") + qs
    headers = {"Accept": "application/json"}
    if auth_header:
        headers["Authorization"] = auth_header
    req = Request(url, headers=headers, method="GET")
    with urlopen(req, timeout=20) as resp:
        raw = resp.read().decode("utf-8", errors="replace")
        try:
            return json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return {"status": "error", "message": "Invalid upstream JSON", "raw": raw[:500]}


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


def _email_health_payload() -> dict:
    """Safe email config summary for ops (no secrets)."""
    host = (getattr(settings, "EMAIL_HOST", "") or "").strip()
    backend = getattr(settings, "EMAIL_BACKEND", "")
    configured = bool(host) and "smtp" in backend.lower()
    return {
        "smtp_configured": configured,
        "backend": backend.rsplit(".", 1)[-1] if backend else "console",
        "host": host or None,
        "port": getattr(settings, "EMAIL_PORT", None),
        "use_tls": getattr(settings, "EMAIL_USE_TLS", None),
        "from_email": getattr(settings, "DEFAULT_FROM_EMAIL", ""),
        "support_email": getattr(settings, "SUPPORT_EMAIL", ""),
        "reset_link_base": (getattr(settings, "PUBLIC_API_BASE_URL", "") or "").rstrip("/"),
    }


@api_view(["GET"])
@permission_classes([AllowAny])
def health(request):
    payload = {"ok": True, "email": _email_health_payload()}
    return _success(payload, message="Service healthy")


def api_welcome(request):
    """Branded landing page for browsers hitting the API host (not the mobile app)."""
    base = request.build_absolute_uri("/api/").rstrip("/") + "/"
    admin_url = request.build_absolute_uri("/admin/")
    site_url = getattr(settings, "FRONTEND_BASE_URL", "https://docsoncalls.com").rstrip("/")
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Docs On Call API</title>
  <style>
    :root {{ --primary: #0d6e6e; --primary-dark: #095454; --bg: #f6fbfb; }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
      background: var(--bg); color: #1a2b2b; line-height: 1.5; }}
    header {{ background: linear-gradient(135deg, var(--primary-dark), var(--primary));
      color: #fff; padding: 2rem 1.25rem; }}
    header h1 {{ margin: 0 0 0.35rem; font-size: 1.75rem; }}
    header p {{ margin: 0; opacity: 0.92; max-width: 40rem; }}
    main {{ max-width: 720px; margin: 0 auto; padding: 1.5rem 1.25rem 3rem; }}
    .card {{ background: #fff; border: 1px solid #d8e8e8; border-radius: 14px;
      padding: 1.1rem 1.25rem; margin-bottom: 1rem; }}
    .card h2 {{ margin: 0 0 0.5rem; font-size: 1.05rem; color: var(--primary-dark); }}
    a {{ color: var(--primary); font-weight: 600; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
    ul {{ margin: 0.35rem 0 0; padding-left: 1.2rem; }}
    code {{ background: #eef5f5; padding: 0.15rem 0.4rem; border-radius: 6px; font-size: 0.9em; }}
    .pill {{ display: inline-block; background: #e8f6f6; color: var(--primary-dark);
      padding: 0.25rem 0.65rem; border-radius: 999px; font-size: 0.8rem; font-weight: 700; }}
    footer {{ text-align: center; color: #5c6b6b; font-size: 0.85rem; padding: 1rem; }}
  </style>
</head>
<body>
  <header>
    <p class="pill">Doctor On Call · Production API</p>
    <h1>Docs On Call API</h1>
    <p>JSON REST backend for the iOS/Android app. Use the mobile app to sign in — this site is for health checks and administration.</p>
  </header>
  <main>
    <div class="card">
      <h2>Quick links</h2>
      <ul>
        <li><a href="{base}health/">Health check</a> — <code>GET /api/health/</code></li>
        <li><a href="{base}">API index (JSON)</a> — DRF router</li>
        <li><a href="{admin_url}">Django Admin</a> — staff login (database)</li>
        <li><a href="{site_url}">Website</a></li>
      </ul>
    </div>
    <div class="card">
      <h2>Mobile app sign-in</h2>
      <p>Open <strong>Doctor On Call</strong> on your phone. On the login screen choose <strong>Patient</strong>, <strong>Doctor</strong>, or <strong>Admin</strong>, then enter your app account email and password.</p>
      <p>This page does not accept app passwords.</p>
    </div>
    <div class="card">
      <h2>Support &amp; privacy</h2>
      <ul>
        <li><a href="https://zub165.github.io/Doctorsoncall/privacy.html">Privacy policy</a></li>
        <li><a href="https://zub165.github.io/Doctorsoncall/delete.html">Delete account</a></li>
        <li>Support: <a href="mailto:{getattr(settings, 'SUPPORT_EMAIL', 'info@innovatorsgeneration.com')}">{getattr(settings, 'SUPPORT_EMAIL', 'info@innovatorsgeneration.com')}</a></li>
      </ul>
    </div>
  </main>
  <footer>© Docs On Call · {base}</footer>
</body>
</html>"""
    return HttpResponse(html)


@api_view(["GET"])
@authentication_classes([OptionalTokenAuthentication, SessionAuthentication])
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


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def doctor_on_call_sync_pull(request, entity):
    """
    Offline sync pull stub — returns empty page until full sync is implemented.
  Flutter sends: GET /api/doctor-on-call/sync/<entity>/?since=<cursor>
    """
    since = (request.query_params.get("since") or "").strip()
    return _success(
        {
            "results": [],
            "next_cursor": since or None,
            "server_time": timezone.now().isoformat(),
            "entity": str(entity or "").strip().lower(),
        }
    )


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def doctor_on_call_sync_push(request):
    """Offline sync push stub — accepts outbox events without persisting yet."""
    events = request.data.get("events") if isinstance(request.data, dict) else []
    if not isinstance(events, list):
        events = []
    return _success(
        {
            "accepted": len(events),
            "errors": [],
        },
        message="Sync push accepted (stub)",
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
@permission_classes([IsAuthenticated])
def admin_create_user(request):
    """Staff-only: create patient, doctor (provider), or administrator account."""
    if not _is_staffish(request.user):
        return Response(
            {"status": "error", "message": "Admin only"},
            status=status.HTTP_403_FORBIDDEN,
        )
    kind = str(request.data.get("kind") or request.data.get("type") or "").lower().strip()
    email = str(request.data.get("email") or "").strip()
    password = str(request.data.get("password") or "").strip()
    name = str(request.data.get("name") or request.data.get("full_name") or "").strip()
    if not email or not password:
        return _error({"detail": ["email and password are required"]})
    if len(password) < 8:
        return _error({"password": ["Must be at least 8 characters"]})
    if User.objects.filter(email__iexact=email).exists():
        return _error({"email": ["Email already registered."]})

    username = str(request.data.get("username") or email.split("@")[0])[:30]
    base_username = username
    n = 1
    while User.objects.filter(username=username).exists():
        username = f"{base_username}{n}"[:30]
        n += 1

    user = User.objects.create_user(
        username=username,
        email=email,
        password=password,
        first_name=name[:150] if name else "",
    )

    if kind in ("admin", "administrator", "staff"):
        user.is_staff = True
        user.save(update_fields=["is_staff"])
        return Response(
            {
                "status": "success",
                "message": "Administrator created",
                "data": {
                    "user_id": user.id,
                    "username": user.username,
                    "email": user.email,
                    "kind": "admin",
                },
            },
            status=status.HTTP_201_CREATED,
        )

    if kind in ("doctor", "provider", "physician"):
        try:
            speciality_id = int(request.data.get("speciality_id"))
        except (TypeError, ValueError):
            speciality_id = Speciality.objects.first().id if Speciality.objects.exists() else None
        if not speciality_id:
            user.delete()
            return _error({"speciality_id": ["required when no specialities exist"]})
        provider = Provider.objects.create(
            user=user,
            full_name=name or user.username,
            email=email,
            phone_number=str(request.data.get("phone_number") or "").strip() or "+10000000000",
            speciality_id=speciality_id,
            status=Provider.Status.ACTIVE,
            is_verified=True,
        )
        return Response(
            {
                "status": "success",
                "message": "Doctor created",
                "data": {
                    "user_id": user.id,
                    "provider_id": provider.id,
                    "username": user.username,
                    "email": user.email,
                    "kind": "doctor",
                },
            },
            status=status.HTTP_201_CREATED,
        )

    # Default: patient
    patient, _ = Patient.objects.get_or_create(
        user=user,
        defaults={
            "name": name or user.get_full_name() or user.username,
            "date_of_birth": str(request.data.get("date_of_birth") or "Unknown"),
            "email": email,
            "profile_status": str(request.data.get("profile_status") or "approved"),
        },
    )
    return Response(
        {
            "status": "success",
            "message": "Patient created",
            "data": {
                "user_id": user.id,
                "patient_id": patient.id,
                "username": user.username,
                "email": user.email,
                "kind": "patient",
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

    volunteer = str(request.data.get("volunteer_online_visits") or "").strip().lower() in (
        "1",
        "true",
        "yes",
        "y",
    )
    bio = str(request.data.get("bio") or "").strip()
    qualifications = str(request.data.get("qualifications") or "").strip()
    if volunteer:
        note = "Offers volunteer online telehealth visits."
        bio = f"{bio}\n\n{note}".strip() if bio else note
        qualifications = (
            f"{qualifications}\nVolunteer online visits: yes".strip()
            if qualifications
            else "Volunteer online visits: yes"
        )

    provider = Provider.objects.create(
        user=request.user,
        full_name=full_name,
        email=email,
        phone_number=phone,
        speciality_id=speciality_id,
        gender=str(request.data.get("gender") or "").strip() or None,
        license_number=(str(request.data.get("license_number") or "").strip() or None),
        qualifications=qualifications,
        bio=bio,
        consultation_fee=0 if volunteer else None,
        consultation_type=Provider.ConsultationType.VIDEO,
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


@api_view(["POST", "DELETE"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def auth_delete_account(request):
    """
    Permanently delete the authenticated user and linked patient/provider rows (CASCADE).
  Staff/superuser accounts must contact support instead of self-delete.
    """
    user = request.user
    if _is_staffish(user):
        return Response(
            {
                "status": "error",
                "message": "Staff accounts cannot be deleted in the app. Email support.",
            },
            status=status.HTTP_403_FORBIDDEN,
        )
    Token.objects.filter(user=user).delete()
    user.delete()
    return _success(message="Account deleted")


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
@authentication_classes([OptionalTokenAuthentication, SessionAuthentication])
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


def _feedback_rating_questions(reviewer_role):
    """Star-rating prompts aligned with common telehealth satisfaction surveys."""
    if reviewer_role == Feedback.ReviewerRole.PROVIDER:
        return [
            {
                "key": "overall_rating",
                "label": "Overall visit experience",
                "required": True,
            },
            {
                "key": "rating_communication",
                "label": "Patient communication during the visit",
                "required": True,
            },
            {
                "key": "rating_care_quality",
                "label": "Patient cooperation with the care plan",
                "required": True,
            },
            {
                "key": "rating_ease",
                "label": "Patient punctuality and readiness (video/audio)",
                "required": False,
            },
        ]
    if reviewer_role == Feedback.ReviewerRole.PATIENT:
        return [
            {
                "key": "overall_rating",
                "label": "Overall quality of care",
                "required": True,
            },
            {
                "key": "rating_communication",
                "label": "Doctor listened and explained clearly",
                "required": True,
            },
            {
                "key": "rating_care_quality",
                "label": "Medical advice and treatment plan",
                "required": True,
            },
            {
                "key": "rating_ease",
                "label": "Ease of the virtual visit (audio/video/platform)",
                "required": False,
            },
            {
                "key": "rating_recommend",
                "label": "Would you recommend this doctor?",
                "required": True,
            },
        ]
    return [
        {
            "key": "overall_rating",
            "label": "Overall experience",
            "required": False,
        },
    ]


def _feedback_targets_for_user(user):
    """People the signed-in user may rate (from shared appointments)."""
    patient = Patient.objects.filter(user=user).first()
    provider = Provider.objects.filter(user=user).select_related("speciality").first()
    targets = []

    if _is_staffish(user):
        appts = (
            Appointment.objects.select_related("provider", "patient")
            .order_by("-date", "-time")[:80]
        )
        seen = set()
        for a in appts:
            if a.provider_id and ("p", a.provider_id) not in seen:
                seen.add(("p", a.provider_id))
                st = Feedback.SubjectType.PROVIDER
                targets.append(
                    {
                        "subject_type": st,
                        "provider_id": a.provider_id,
                        "patient_id": a.patient_id,
                        "appointment_id": a.id,
                        "label": a.provider.full_name,
                        "subtitle": f"Patient: {a.patient.name} · {a.date}",
                        "questions": _feedback_rating_questions(Feedback.ReviewerRole.PATIENT),
                    }
                )
            if a.patient_id and ("t", a.patient_id) not in seen:
                seen.add(("t", a.patient_id))
                st = Feedback.SubjectType.PATIENT
                targets.append(
                    {
                        "subject_type": st,
                        "provider_id": a.provider_id,
                        "patient_id": a.patient_id,
                        "appointment_id": a.id,
                        "label": a.patient.name,
                        "subtitle": f"Doctor: {a.provider.full_name} · {a.date}",
                        "questions": _feedback_rating_questions(Feedback.ReviewerRole.PROVIDER),
                    }
                )
        reviewer_role = Feedback.ReviewerRole.ADMIN
        subject_hint = "Select a doctor or patient you worked with"
    elif provider:
        appts = (
            Appointment.objects.filter(provider=provider)
            .select_related("patient")
            .order_by("-date", "-time")[:50]
        )
        seen = set()
        for a in appts:
            if a.patient_id in seen:
                continue
            seen.add(a.patient_id)
            targets.append(
                {
                    "subject_type": Feedback.SubjectType.PATIENT,
                    "provider_id": provider.id,
                    "patient_id": a.patient_id,
                    "appointment_id": a.id,
                    "label": a.patient.name,
                    "subtitle": f"Visit {a.date}",
                    "questions": _feedback_rating_questions(Feedback.ReviewerRole.PROVIDER),
                }
            )
        reviewer_role = Feedback.ReviewerRole.PROVIDER
        subject_hint = "Rate a patient from your visits"
    elif patient:
        appts = (
            Appointment.objects.filter(patient=patient)
            .select_related("provider__speciality")
            .order_by("-date", "-time")[:50]
        )
        seen = set()
        for a in appts:
            if a.provider_id in seen:
                continue
            seen.add(a.provider_id)
            spec = ""
            if a.provider.speciality_id:
                spec = getattr(a.provider.speciality, "speciality_name", "") or ""
            targets.append(
                {
                    "subject_type": Feedback.SubjectType.PROVIDER,
                    "provider_id": a.provider_id,
                    "patient_id": patient.id,
                    "appointment_id": a.id,
                    "label": a.provider.full_name,
                    "subtitle": f"{spec} · Visit {a.date}".strip(" ·"),
                    "questions": _feedback_rating_questions(Feedback.ReviewerRole.PATIENT),
                }
            )
        reviewer_role = Feedback.ReviewerRole.PATIENT
        subject_hint = "Rate your doctor after a visit"
    else:
        reviewer_role = Feedback.ReviewerRole.GUEST
        subject_hint = "Sign in to rate a specific doctor or patient"

    return reviewer_role, subject_hint, targets


def _parse_star_rating(raw, field_name, required=False):
    if raw is None or raw == "":
        if required:
            return None, {field_name: ["required (1–5 stars)"]}
        return None, {}
    try:
        val = int(raw)
    except (TypeError, ValueError):
        return None, {field_name: ["must be 1–5"]}
    if val < 1 or val > 5:
        return None, {field_name: ["must be 1–5"]}
    return val, {}


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def feedback_context(request):
    """Targets (provider/patient) and star-rating questions for the signed-in role."""
    reviewer_role, subject_hint, targets = _feedback_targets_for_user(request.user)
    return _success(
        {
            "reviewer_role": reviewer_role,
            "subject_hint": subject_hint,
            "targets": targets,
            "questions": _feedback_rating_questions(reviewer_role),
            "allow_general": reviewer_role
            in (Feedback.ReviewerRole.GUEST, Feedback.ReviewerRole.ADMIN),
        }
    )


@api_view(["POST"])
@permission_classes([AllowAny])
def feedback_submit(request):
    text = (request.data.get("feedback") or request.data.get("message") or "").strip()
    user = request.user if getattr(request, "user", None) and request.user.is_authenticated else None

    subject_type = (request.data.get("subject_type") or "").strip().lower()
    provider_id = request.data.get("provider_id")
    patient_id = request.data.get("patient_id")
    appointment_id = request.data.get("appointment_id")

    patient = Patient.objects.filter(user=user).first() if user else None
    provider = Provider.objects.filter(user=user).first() if user else None
    reviewer_role = Feedback.ReviewerRole.GUEST
    if user:
        if _is_staffish(user):
            reviewer_role = Feedback.ReviewerRole.ADMIN
        elif provider:
            reviewer_role = Feedback.ReviewerRole.PROVIDER
        elif patient:
            reviewer_role = Feedback.ReviewerRole.PATIENT

    effective_reviewer = reviewer_role
    if reviewer_role == Feedback.ReviewerRole.ADMIN:
        if subject_type == Feedback.SubjectType.PROVIDER:
            effective_reviewer = Feedback.ReviewerRole.PATIENT
        elif subject_type == Feedback.SubjectType.PATIENT:
            effective_reviewer = Feedback.ReviewerRole.PROVIDER

    errors = {}
    ratings = {}
    visit_subject = subject_type in (
        Feedback.SubjectType.PROVIDER,
        Feedback.SubjectType.PATIENT,
    )
    for field, required in (
        ("overall_rating", True),
        ("rating_communication", effective_reviewer == Feedback.ReviewerRole.PATIENT),
        ("rating_care_quality", effective_reviewer in (
            Feedback.ReviewerRole.PATIENT,
            Feedback.ReviewerRole.PROVIDER,
        )),
        ("rating_ease", False),
        ("rating_recommend", effective_reviewer == Feedback.ReviewerRole.PATIENT),
    ):
        val, err = _parse_star_rating(
            request.data.get(field),
            field,
            required=required and visit_subject,
        )
        if err:
            errors.update(err)
        elif val is not None:
            ratings[field] = val

    if subject_type in (Feedback.SubjectType.PROVIDER, Feedback.SubjectType.PATIENT):
        if not user:
            errors["detail"] = ["Sign in to rate a doctor or patient."]
        if subject_type == Feedback.SubjectType.PROVIDER and not provider_id:
            errors["provider_id"] = ["required — select which doctor"]
        if subject_type == Feedback.SubjectType.PATIENT and not patient_id:
            errors["patient_id"] = ["required — select which patient"]
        if reviewer_role == Feedback.ReviewerRole.PATIENT and subject_type != Feedback.SubjectType.PROVIDER:
            errors["subject_type"] = ["Patients rate their doctor (provider)."]
        if reviewer_role == Feedback.ReviewerRole.PROVIDER and subject_type != Feedback.SubjectType.PATIENT:
            errors["subject_type"] = ["Doctors rate their patient."]
        if reviewer_role == Feedback.ReviewerRole.ADMIN and subject_type not in (
            Feedback.SubjectType.PROVIDER,
            Feedback.SubjectType.PATIENT,
        ):
            errors["subject_type"] = ["Select provider or patient subject."]
        if not ratings.get("overall_rating"):
            errors.setdefault("overall_rating", []).append("required (1–5 stars)")
        if not text and not ratings:
            errors.setdefault("feedback", []).append(
                "Add star ratings or a short written comment."
            )
    else:
        subject_type = Feedback.SubjectType.GENERAL
        if not text:
            errors["feedback"] = ["required"]

    if errors:
        return _error(errors)

    prov_obj = None
    pat_obj = None
    appt_obj = None
    if provider_id:
        prov_obj = Provider.objects.filter(pk=provider_id).first()
        if not prov_obj:
            return _error({"provider_id": ["invalid"]})
    if patient_id:
        pat_obj = Patient.objects.filter(pk=patient_id).first()
        if not pat_obj:
            return _error({"patient_id": ["invalid"]})
    if appointment_id:
        appt_obj = Appointment.objects.filter(pk=appointment_id).first()

    extra = request.data.get("responses")
    responses = extra if isinstance(extra, dict) else {}

    row = Feedback.objects.create(
        user=user,
        reviewer_role=reviewer_role,
        subject_type=subject_type or Feedback.SubjectType.GENERAL,
        provider=prov_obj,
        patient=pat_obj,
        appointment=appt_obj,
        feedback=text[:5000] if text else (f"Rating {ratings.get('overall_rating')}/5"),
        overall_rating=ratings.get("overall_rating"),
        rating_communication=ratings.get("rating_communication"),
        rating_care_quality=ratings.get("rating_care_quality"),
        rating_ease=ratings.get("rating_ease"),
        rating_recommend=ratings.get("rating_recommend"),
        responses=responses,
    )
    return _success(
        {"feedback": FeedbackSerializer(row).data},
        message="Feedback submitted",
    )


def _hospitals_catalog_near(lat, lon, radius_km=80.0):
    """
    EMR catalog facilities near (lat, lon), sorted by distance.
    Used when MyWaitime upstream is down but the app should still show nearby rows.
    """
    try:
        radius_km = float(radius_km)
    except (TypeError, ValueError):
        radius_km = 80.0
    radius_km = max(1.0, min(radius_km, 500.0))

    rows = list(Hospital.objects.all()[:500])
    scored = []
    for h in rows:
        try:
            hlat = float(h.latitude)
            hlon = float(h.longitude)
        except (TypeError, ValueError):
            continue
        if abs(hlat) < 1e-6 and abs(hlon) < 1e-6:
            continue
        dist = _haversine_km(lat, lon, hlat, hlon)
        scored.append((dist, h))
    scored.sort(key=lambda t: t[0])

    geo_note = None
    in_radius = [h for d, h in scored if d <= radius_km]
    if in_radius:
        rows = in_radius
    elif scored:
        rows = [h for _, h in scored[:50]]
        geo_note = (
            f"Live search unavailable — EMR catalog; nearest {len(rows)} "
            f"(up to {scored[0][0]:.1f} km)."
        )
    else:
        rows = []
        geo_note = "Live search unavailable — no catalog facilities with coordinates."

    payload = []
    for h in rows:
        item = dict(HospitalSerializer(h).data)
        try:
            item["distance_km"] = round(
                _haversine_km(lat, lon, float(h.latitude), float(h.longitude)), 2
            )
        except (TypeError, ValueError):
            item["distance_km"] = None
        payload.append(item)
    return payload, geo_note


def _tomtom_hospitals_near(lat, lon, radius_m=25000, limit=40):
    """
    TomTom Nearby Search (hospital / health POI). Key stays on server via _tomtom_get_json.
    Returns (list[dict], error_message).
    """
    key = (getattr(settings, "TOMTOM_API_KEY", "") or "").strip()
    if not key:
        return [], "TomTom API key not configured"

    try:
        radius_m = int(radius_m)
    except (TypeError, ValueError):
        radius_m = 25000
    radius_m = max(500, min(radius_m, 50000))
    try:
        limit = int(limit)
    except (TypeError, ValueError):
        limit = 40
    limit = max(1, min(limit, 100))

    data, err = _tomtom_get_json(
        "search/2/nearbySearch/.json",
        {
            "lat": lat,
            "lon": lon,
            "radius": radius_m,
            "limit": limit,
            # Hospital / health service POI categories (TomTom Search API).
            "categorySet": "7394,7326,7321",
        },
    )
    if err or not data:
        return [], err or "TomTom nearby search failed"

    out = []
    for item in data.get("results") or []:
        if not isinstance(item, dict):
            continue
        row = _tomtom_poi_to_hospital_row(item, lat, lon)
        if row:
            out.append(row)
    return out, None


def _tomtom_poi_to_hospital_row(item, user_lat, user_lon):
    pos = item.get("position") if isinstance(item.get("position"), dict) else {}
    poi = item.get("poi") if isinstance(item.get("poi"), dict) else {}
    addr = item.get("address") if isinstance(item.get("address"), dict) else {}
    try:
        plat = float(pos.get("lat"))
        plon = float(pos.get("lon"))
    except (TypeError, ValueError):
        return None

    tid = (item.get("id") or "").strip()
    hid = f"tomtom-{tid}" if tid else f"tomtom_{plat:.4f}_{plon:.4f}"

    dist_m = item.get("dist")
    if dist_m is not None:
        try:
            distance_km = round(float(dist_m) / 1000.0, 2)
        except (TypeError, ValueError):
            distance_km = round(_haversine_km(user_lat, user_lon, plat, plon), 2)
    else:
        distance_km = round(_haversine_km(user_lat, user_lon, plat, plon), 2)

    cats = poi.get("categories") or []
    facility = "Hospital"
    cat_blob = " ".join(str(c) for c in cats).lower()
    if "emergency" in cat_blob or " er" in cat_blob:
        facility = "Emergency Room"
    elif "urgent" in cat_blob:
        facility = "Urgent Care"
    elif "clinic" in cat_blob:
        facility = "Walk-in Clinic"

    return {
        "id": hid,
        "tomtom_id": tid or None,
        "name": (poi.get("name") or "Hospital").strip(),
        "address": (addr.get("freeformAddress") or addr.get("streetName") or "").strip(),
        "phone_number": (poi.get("phone") or "").strip(),
        "latitude": plat,
        "longitude": plon,
        "distance_km": distance_km,
        "facility_type": facility,
        "rating": 0,
        "wait_time_minutes": 0,
        "is_open": True,
    }


def _hospitals_search_degraded(lat, lon, radius_m=25000, extra=None):
    """
    When MyWaitime is down: TomTom nearby POI → EMR catalog (~80 km) → None (caller returns 502).
    """
    extra = dict(extra or {})
    rows, _tomtom_err = _tomtom_hospitals_near(lat, lon, radius_m=radius_m)
    if rows:
        return Response(
            {
                "status": "success",
                "data": rows,
                "source": "tomtom",
                "upstream_degraded": True,
                "total_found": len(rows),
                "geo_note": extra.pop(
                    "geo_note",
                    "Live MyWaitime unavailable — showing TomTom hospitals near you.",
                ),
                **extra,
            },
            status=status.HTTP_200_OK,
        )

    payload, geo_note = _hospitals_catalog_near(lat, lon, radius_km=80.0)
    if payload:
        return Response(
            {
                "status": "success",
                "data": payload,
                "source": "emr_catalog",
                "upstream_degraded": True,
                "total_found": len(payload),
                "geo_note": geo_note
                or "MyWaitime unavailable — showing EMR catalog near you.",
                **extra,
            },
            status=status.HTTP_200_OK,
        )
    return None


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

    geo_note = None
    lat_raw = request.GET.get("lat")
    lon_raw = request.GET.get("lon")
    try:
        lat = float(lat_raw) if lat_raw not in (None, "") else None
        lon = float(lon_raw) if lon_raw not in (None, "") else None
    except (TypeError, ValueError):
        lat, lon = None, None

    try:
        radius_km = float(request.GET.get("radius_km") or 150)
    except (TypeError, ValueError):
        radius_km = 150.0
    radius_km = max(1.0, min(radius_km, 500.0))

    rows = list(qs[:500])
    payload = []
    if lat is not None and lon is not None:
        scored = []
        for h in rows:
            try:
                hlat = float(h.latitude)
                hlon = float(h.longitude)
            except (TypeError, ValueError):
                continue
            if abs(hlat) < 1e-6 and abs(hlon) < 1e-6:
                continue
            dist = _haversine_km(lat, lon, hlat, hlon)
            scored.append((dist, h))
        scored.sort(key=lambda t: t[0])
        in_radius = [h for d, h in scored if d <= radius_km]
        if in_radius:
            rows = in_radius
        elif scored:
            rows = [h for _, h in scored[:50]]
            geo_note = (
                f"No facilities within {radius_km:.0f} km; showing nearest "
                f"{len(rows)} (up to {scored[0][0]:.1f} km)."
            )
        else:
            geo_note = "No facilities with map coordinates in the catalog yet."

    for h in rows:
        item = dict(HospitalSerializer(h).data)
        if lat is not None and lon is not None:
            try:
                item["distance_km"] = round(
                    _haversine_km(lat, lon, float(h.latitude), float(h.longitude)), 2
                )
            except (TypeError, ValueError):
                item["distance_km"] = None
        payload.append(item)

    return _success({"results": payload, "geo_note": geo_note, "source": "emr_catalog"})


@api_view(["GET"])
@permission_classes([AllowAny])
def hospitals_search(request):
    """
    Live hospital discovery via MyWaitime upstream (nginx :3015 or api.mywaitime.com).

    Query: lat, lon, radius_m, limit, type (all|emergency|urgent_care|clinic|general), q
    """
    lat = request.GET.get("lat")
    lon = request.GET.get("lon")
    if lat in (None, "") or lon in (None, ""):
        return _error({"lat": ["required"], "lon": ["required"]})

    params = {
        "lat": lat,
        "lon": lon,
        "radius_m": request.GET.get("radius_m") or "25000",
        "limit": request.GET.get("limit") or "40",
        "type": request.GET.get("type") or "all",
    }
    q = (request.GET.get("q") or "").strip()
    if q:
        params["q"] = q

    auth = request.headers.get("Authorization", "")
    try:
        lat_f = float(lat)
        lon_f = float(lon)
    except (TypeError, ValueError):
        return _error({"lat": ["invalid"], "lon": ["invalid"]})

    try:
        upstream = _proxy_mywaitime_get("hospitals/search/", params, auth_header=auth)
    except HTTPError as e:
        try:
            radius_m = int(params.get("radius_m") or 25000)
        except (TypeError, ValueError):
            radius_m = 25000
        degraded = _hospitals_search_degraded(
            lat_f,
            lon_f,
            radius_m=radius_m,
            extra={"upstream_status": e.code},
        )
        if degraded is not None:
            return degraded
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            body = ""
        return Response(
            {
                "status": "error",
                "message": "MyWaitime search unavailable",
                "upstream_status": e.code,
                "body": body[:2000],
            },
            status=status.HTTP_502_BAD_GATEWAY,
        )
    except URLError as e:
        try:
            radius_m = int(params.get("radius_m") or 25000)
        except (TypeError, ValueError):
            radius_m = 25000
        degraded = _hospitals_search_degraded(
            lat_f,
            lon_f,
            radius_m=radius_m,
            extra={"detail": str(e)[:500]},
        )
        if degraded is not None:
            return degraded
        return Response(
            {"status": "error", "message": "MyWaitime unreachable", "detail": str(e)},
            status=status.HTTP_502_BAD_GATEWAY,
        )

    if isinstance(upstream, dict):
        upstream.setdefault("source", "mywaitime")
    return Response(upstream if isinstance(upstream, dict) else {"data": upstream})


@api_view(["GET"])
@permission_classes([AllowAny])
def hospital_detail(request, hospital_id):
    pk = _try_int_hospital_pk(hospital_id)
    if pk is not None:
        h = Hospital.objects.filter(id=pk).first()
        if h:
            return _success(HospitalSerializer(h).data)
        return Response(
            {"status": "error", "errors": {"hospital": ["not found"]}},
            status=status.HTTP_404_NOT_FOUND,
        )
    return _proxy_hospital_upstream_get(request, hospital_id)


@api_view(["GET"])
@permission_classes([AllowAny])
def hospital_ai_wait_time(request, hospital_id):
    pk = _try_int_hospital_pk(hospital_id)
    if pk is not None:
        h = Hospital.objects.filter(id=pk).first()
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
    return _proxy_hospital_upstream_get(request, hospital_id, "ai-wait-time")


@api_view(["GET", "PATCH"])
@permission_classes([AllowAny])
def hospital_smart_wait_time(request, hospital_id):
    """Flutter/API docs: GET|PATCH /api/hospitals/<uuid>/smart-wait-time/ → Finder :3015."""
    pk = _try_int_hospital_pk(hospital_id)
    if pk is not None:
        h = Hospital.objects.filter(id=pk).first()
        if not h:
            return Response(
                {"status": "error", "errors": {"hospital": ["not found"]}},
                status=status.HTTP_404_NOT_FOUND,
            )
        return _success(
            {
                "hospital_id": h.id,
                "smart_wait_minutes": h.wait_time_minutes,
                "rating": h.rating,
                "ai_rating": h.ai_rating,
                "is_open": h.is_open,
            }
        )
    if request.method == "PATCH":
        return Response(
            {"status": "error", "message": "PATCH smart-wait-time only on live Finder hospitals"},
            status=status.HTTP_405_METHOD_NOT_ALLOWED,
        )
    return _proxy_hospital_upstream_get(request, hospital_id, "smart-wait-time")


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
            "name": "Sunshine Walk-In Clinic",
            "address": "2200 Palm Ave, Tampa, FL",
            "facility_type": "Walk-in Clinic",
            "latitude": 27.9506,
            "longitude": -82.4572,
            "rating": 4.1,
            "ai_rating": 4.2,
            "wait_time_minutes": 12,
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


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def specialities_seed_avatars(request):
    """Staff: download PNG avatars into /media/specialities/ and save URLs on each row."""
    if not _is_staffish(request.user):
        return Response(
            {"status": "error", "message": "Admin only"},
            status=status.HTTP_403_FORBIDDEN,
        )
    from .speciality_avatars import seed_speciality_avatars

    force = str(request.data.get("force", "")).lower() in ("1", "true", "yes")
    result = seed_speciality_avatars(force=force)
    return _success(result, message="Speciality avatars updated")


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


STORE_PLAN_PRODUCT_IDS = (
    "doc_basic_monthly",
    "doc_gold_monthly",
    "doc_premium_monthly",
)


class PlanViewSet(viewsets.ModelViewSet):
    queryset = Plan.objects.all()
    serializer_class = PlanSerializer
    permission_classes = [_ReadAnyWriteAdmin]

    def get_queryset(self):
        qs = Plan.objects.all().order_by("id")
        if getattr(self, "action", None) != "list":
            return qs
        show_all = (self.request.query_params.get("all") or "").strip().lower() in (
            "1",
            "true",
            "yes",
            "y",
        )
        user = self.request.user
        if show_all and user.is_authenticated and (user.is_staff or user.is_superuser):
            return qs
        return qs.filter(revenuecat_product_id__in=STORE_PLAN_PRODUCT_IDS)

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
                revenuecat_product_id="doc_basic_monthly",
                revenuecat_entitlement_id="basic",
            )
            Plan.objects.create(
                plan_name="Gold",
                duration="Monthly",
                price="29.99",
                number_appointments="3",
                ai_bot="yes",
                discount="",
                revenuecat_product_id="doc_gold_monthly",
                revenuecat_entitlement_id="gold",
            )
            Plan.objects.create(
                plan_name="Premium",
                duration="Monthly",
                price="49.99",
                number_appointments="5",
                ai_bot="yes",
                discount="",
                revenuecat_product_id="doc_premium_monthly",
                revenuecat_entitlement_id="premium",
            )
        return super().list(request, *args, **kwargs)


class RoleViewSet(viewsets.ModelViewSet):
    queryset = Role.objects.all()
    serializer_class = RoleSerializer
    permission_classes = [_ReadAnyWriteAdmin]


class ProviderViewSet(viewsets.ModelViewSet):
    queryset = Provider.objects.select_related("speciality", "user").all()
    serializer_class = ProviderListSerializer
    permission_classes = [_ReadAnyWriteAdmin]

    def perform_update(self, serializer):
        provider = serializer.save()
        if not _is_staffish(self.request.user):
            return
        data = self.request.data
        uf = []
        if "is_verified" in data:
            raw = data.get("is_verified")
            provider.is_verified = str(raw).lower() in ("1", "true", "yes", "active")
            uf.append("is_verified")
        if "status" in data:
            st = (provider.status or "").lower().strip()
            if st == "active":
                provider.is_verified = True
                if "is_verified" not in uf:
                    uf.append("is_verified")
        if uf:
            provider.save(update_fields=uf)
        if "is_staff" in data and provider.user_id:
            raw = data.get("is_staff")
            provider.user.is_staff = str(raw).lower() in ("1", "true", "yes")
            provider.user.save(update_fields=["is_staff"])


class PatientViewSet(viewsets.ModelViewSet):
    """Staff can PATCH/DELETE via app; authenticated users can list/retrieve."""

    queryset = Patient.objects.select_related("user").all()
    serializer_class = PatientSerializer
    permission_classes = [_ReadAnyWriteAdmin]
    http_method_names = ["get", "patch", "put", "delete", "head", "options"]

    def perform_update(self, serializer):
        patient = serializer.save()
        if patient.user_id:
            user = patient.user
            email = (serializer.validated_data.get("email") or "").strip()
            if email and user.email != email:
                user.email = email
                user.save(update_fields=["email"])
            if _is_staffish(self.request.user) and "is_staff" in self.request.data:
                raw = self.request.data.get("is_staff")
                user.is_staff = str(raw).lower() in ("1", "true", "yes")
                user.save(update_fields=["is_staff"])
            if _is_staffish(self.request.user) and "is_superuser" in self.request.data:
                raw = self.request.data.get("is_superuser")
                user.is_superuser = str(raw).lower() in ("1", "true", "yes")
                user.save(update_fields=["is_superuser"])


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def patients_providers(request):
    """
    Role-aware hub for Patients · Providers screen.
    - Admin/staff: all patients, providers, recent appointments
    - Doctor: their patients (from appointments) + their schedule
    - Patient: their doctors (from appointments) + their schedule
    """
    user = request.user
    patient = Patient.objects.filter(user=user).first()
    provider = Provider.objects.filter(user=user).select_related("speciality").first()

    if _is_staffish(user):
        view = "admin"
        providers_qs = Provider.objects.select_related("speciality").order_by("full_name")[:200]
        patients_qs = Patient.objects.order_by("name")[:200]
        appt_qs = (
            Appointment.objects.select_related("provider__speciality", "patient")
            .order_by("-date", "-time")[:100]
        )
    elif provider:
        view = "doctor"
        patient_ids = (
            Appointment.objects.filter(provider=provider)
            .values_list("patient_id", flat=True)
            .distinct()
        )
        patients_qs = Patient.objects.filter(id__in=patient_ids).order_by("name")
        providers_qs = Provider.objects.filter(pk=provider.pk).select_related("speciality")
        appt_qs = (
            Appointment.objects.filter(provider=provider)
            .select_related("provider__speciality", "patient")
            .order_by("-date", "-time")[:100]
        )
    elif patient:
        view = "patient"
        provider_ids = (
            Appointment.objects.filter(patient=patient)
            .values_list("provider_id", flat=True)
            .distinct()
        )
        providers_qs = (
            Provider.objects.filter(id__in=provider_ids)
            .select_related("speciality")
            .order_by("full_name")
        )
        patients_qs = Patient.objects.filter(pk=patient.pk)
        appt_qs = (
            Appointment.objects.filter(patient=patient)
            .select_related("provider__speciality", "patient")
            .order_by("-date", "-time")[:100]
        )
    else:
        view = "guest"
        providers_qs = Provider.objects.none()
        patients_qs = Patient.objects.none()
        appt_qs = Appointment.objects.none()

    return _success(
        {
            "view": view,
            "providers": ProviderListSerializer(providers_qs, many=True).data,
            "patients": PatientSerializer(patients_qs, many=True).data,
            "appointments": AppointmentExpandedSerializer(appt_qs, many=True).data,
        }
    )


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def appointment_list(request):
    """Appointments for the signed-in user as patient and/or assigned provider."""
    user = request.user
    ids: list[int] = []
    patient = Patient.objects.filter(user=user).first()
    if patient:
        ids.extend(
            Appointment.objects.filter(patient=patient).values_list("id", flat=True)
        )
    provider = Provider.objects.filter(user=user).first()
    if provider:
        ids.extend(
            Appointment.objects.filter(provider=provider).values_list("id", flat=True)
        )
    if not ids:
        return _success({"appointments": []})
    qs = (
        Appointment.objects.filter(id__in=set(ids))
        .select_related("provider", "patient")
        .order_by("-date", "-time")[:200]
    )
    return _success({"appointments": AppointmentExpandedSerializer(qs, many=True).data})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def appointment_all(request):
    if not (
        _is_staffish(request.user)
        or Provider.objects.filter(user=request.user).exists()
    ):
        return Response(
            {"status": "error", "message": "Staff or provider only"},
            status=status.HTTP_403_FORBIDDEN,
        )
    qs = (
        Appointment.objects.select_related("provider", "patient")
        .order_by("-id")[:500]
    )
    return _success({"appointments": AppointmentExpandedSerializer(qs, many=True).data})


@api_view(["GET", "PATCH", "DELETE"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def appointment_detail(request, pk):
    """GET|PATCH /api/appointments/<pk>/ — patient, assigned provider, or staff.

    PATCH body (optional keys): ``medical_record_id`` — integer server id, or ``null`` to clear.
    The medical record must belong to the same patient as the appointment.
    """
    appt = (
        Appointment.objects.filter(pk=pk)
        .select_related("patient__user", "provider__user", "medical_record")
        .first()
    )
    if not appt:
        return _error({"detail": ["Not found"]}, status.HTTP_404_NOT_FOUND)

    user = request.user
    allowed = (
        _is_staffish(user)
        or (appt.patient.user_id == user.id)
        or (appt.provider.user_id == user.id)
    )
    if not allowed:
        return _error({"detail": ["Forbidden"]}, status.HTTP_403_FORBIDDEN)

    if request.method == "GET":
        return _success({"appointment": AppointmentExpandedSerializer(appt).data})

    if request.method == "DELETE":
        if not _is_staffish(user):
            return _error({"detail": ["Forbidden"]}, status.HTTP_403_FORBIDDEN)
        appt.delete()
        return _success({"deleted": True}, message="Deleted")

    update_fields = []
    if _is_staffish(user):
        raw_patient = request.data.get("patient_id")
        if raw_patient not in (None, ""):
            try:
                patient_pk = int(raw_patient)
            except (TypeError, ValueError):
                return _error({"patient_id": ["invalid"]})
            patient = Patient.objects.filter(pk=patient_pk).first()
            if not patient:
                return _error({"patient_id": ["not found"]})
            appt.patient = patient
            update_fields.append("patient")
        raw_provider = request.data.get("provider_id")
        if raw_provider not in (None, ""):
            try:
                provider_pk = int(raw_provider)
            except (TypeError, ValueError):
                return _error({"provider_id": ["invalid"]})
            provider = Provider.objects.filter(pk=provider_pk).first()
            if not provider:
                return _error({"provider_id": ["not found"]})
            appt.provider = provider
            update_fields.append("provider")
        raw_date = request.data.get("date")
        if raw_date not in (None, ""):
            d = parse_date(str(raw_date))
            if not d:
                return _error(
                    {"date": ["Invalid date (YYYY-MM-DD)"]},
                    status.HTTP_400_BAD_REQUEST,
                )
            appt.date = d
            update_fields.append("date")
        raw_time = request.data.get("time")
        if raw_time not in (None, ""):
            t = parse_time(str(raw_time))
            if t is None and len(str(raw_time)) == 5:
                t = parse_time(str(raw_time) + ":00")
            if not t:
                return _error(
                    {"time": ["Invalid time (HH:MM or HH:MM:SS)"]},
                    status.HTTP_400_BAD_REQUEST,
                )
            appt.time = t
            update_fields.append("time")
        status_raw = request.data.get("status") or request.data.get("approved")
        if status_raw not in (None, ""):
            appt.approved = str(status_raw).strip()
            update_fields.append("approved")

    if "medical_record_id" in request.data:
        mr_raw = request.data.get("medical_record_id")
        if mr_raw in (None, "", "null"):
            appt.medical_record = None
        else:
            try:
                mr_pk = int(mr_raw)
            except (TypeError, ValueError):
                return _error({"medical_record_id": ["invalid"]})
            mr = MedicalRecord.objects.filter(pk=mr_pk).first()
            if not mr:
                return _error({"medical_record_id": ["not found"]})
            if mr.patient_id != appt.patient_id:
                return _error(
                    {"medical_record_id": ["record does not belong to this patient"]},
                    status.HTTP_400_BAD_REQUEST,
                )
            appt.medical_record = mr
        update_fields.append("medical_record")

    if update_fields:
        appt.save(update_fields=list(dict.fromkeys(update_fields)))

    return _success(
        {"appointment": AppointmentExpandedSerializer(appt).data},
        message="Updated",
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def appointment_create(request):
    if _is_staffish(request.user):
        try:
            patient_id = int(request.data.get("patient_id"))
        except (TypeError, ValueError):
            return _error({"patient_id": ["required for admin create"]})
        patient = Patient.objects.filter(pk=patient_id).first()
        if not patient:
            return _error({"patient_id": ["not found"]}, status.HTTP_404_NOT_FOUND)
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
        approved = str(request.data.get("status") or request.data.get("approved") or "approved").strip()
        appt = Appointment.objects.create(
            patient=patient,
            provider_id=provider_id,
            date=d,
            time=t,
            approved=approved or None,
        )
        provider = Provider.objects.filter(pk=provider_id).first()
        allowance_after = _patient_subscription_allowance(patient)
        return _success(
            {
                "appointment": AppointmentExpandedSerializer(appt).data,
                "billing_hint": _appointment_billing_hint(
                    patient, provider, allowance_after
                ),
            },
            message="Created",
        )

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

    provider = Provider.objects.filter(pk=provider_id).first()
    allowance_before = _patient_subscription_allowance(patient)
    appt = Appointment.objects.create(
        patient=patient,
        provider_id=provider_id,
        date=d,
        time=t,
    )
    allowance_after = _patient_subscription_allowance(patient)
    billing_hint = _appointment_billing_hint(patient, provider, allowance_before)
    billing_hint["visit_allowance_after"] = allowance_after
    return _success(
        {
            "appointment": AppointmentSerializer(appt).data,
            "billing_hint": billing_hint,
        },
        message="Created",
    )


@api_view(["GET", "PATCH"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def patient_me(request):
    """GET|PATCH /api/patients/me/ - patient self-service"""
    patient = Patient.objects.filter(user=request.user).first()
    if not patient:
        return _error({"patient": ["No patient profile found"]}, status.HTTP_404_NOT_FOUND)

    if request.method == "GET":
        return _success({"patient": PatientSelfSerializer(patient).data})

    ser = PatientSelfUpdateSerializer(data=request.data)
    if not ser.is_valid():
        return _error(ser.errors)

    if "whatsapp_number" in ser.validated_data:
        patient.whatsapp_number = ser.validated_data["whatsapp_number"].strip()[:32]
        patient.save(update_fields=["whatsapp_number"])
    return _success({"patient": PatientSelfSerializer(patient).data}, message="Updated")


@api_view(["GET", "PATCH"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def provider_me(request):
    """GET|PATCH /api/providers/me/ - provider self-service (doctor-on-call)"""
    provider = Provider.objects.filter(user=request.user).first()
    if not provider:
        return _error({"provider": ["No provider profile found"]}, status.HTTP_404_NOT_FOUND)

    if request.method == "GET":
        return _success({"provider": ProviderSelfSerializer(provider, context={"provider": provider}).data})

    ser = ProviderSelfUpdateSerializer(data=request.data)
    if not ser.is_valid():
        return _error(ser.errors)

    data = ser.validated_data
    if "phone_number" in data:
        new_phone = data["phone_number"].strip()[:64]
        if new_phone:
            exists = Provider.objects.exclude(id=provider.id).filter(phone_number=new_phone).exists()
            if exists:
                return _error({"phone_number": ["This phone number is already in use"]})
        provider.phone_number = new_phone
    if "whatsapp_number" in data:
        provider.whatsapp_number = data["whatsapp_number"].strip()[:32]
    provider.save(update_fields=["phone_number", "whatsapp_number"])
    return _success({"provider": ProviderSelfSerializer(provider, context={"provider": provider}).data}, message="Updated")


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
        if is_staff:
            patient_id = request.query_params.get("patient_id")
            if patient_id:
                try:
                    qs = qs.filter(patient_id=int(patient_id))
                except (TypeError, ValueError):
                    return _error({"patient_id": ["invalid"]})
        elif patient:
            qs = qs.filter(patient=patient)
        else:
            prov = Provider.objects.filter(user=user).first()
            if not prov:
                return _success({"vitals": []})
            patient_id = request.query_params.get("patient_id")
            if patient_id:
                try:
                    pid = int(patient_id)
                except (TypeError, ValueError):
                    return _error({"patient_id": ["invalid"]})
                linked = Appointment.objects.filter(
                    provider=prov, patient_id=pid
                ).exists()
                if not linked:
                    return _error(
                        {"patient_id": ["no appointment with this patient"]},
                        status.HTTP_403_FORBIDDEN,
                    )
                qs = qs.filter(patient_id=pid)
            else:
                pids = (
                    Appointment.objects.filter(provider=prov)
                    .values_list("patient_id", flat=True)
                    .distinct()
                )
                qs = qs.filter(patient_id__in=pids)
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


TOMTOM_API_HOST = "https://api.tomtom.com"


def _tomtom_referer():
    ref = (getattr(settings, "TOMTOM_REFERER", "") or "https://api.docsoncalls.com/").strip()
    if ref and not ref.endswith("/"):
        ref += "/"
    return ref


def _tomtom_get_json(path, query_params=None, method="GET", json_body=None, timeout=25):
    """Server-side TomTom JSON fetch. Returns (parsed dict, error string)."""
    key = (getattr(settings, "TOMTOM_API_KEY", "") or "").strip()
    if not key:
        return None, "TomTom API key not configured"
    params = dict(query_params or {})
    params["key"] = key
    url = f"{TOMTOM_API_HOST.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urlencode(params)
    headers = {"Accept": "application/json", "Referer": _tomtom_referer()}
    payload = None
    if json_body is not None:
        headers["Content-Type"] = "application/json"
        payload = json.dumps(json_body).encode("utf-8")
    req = Request(url, data=payload, headers=headers, method=method.upper())
    try:
        with urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                return (json.loads(raw) if raw else {}), None
            except json.JSONDecodeError:
                return {"raw": raw}, None
    except HTTPError as e:
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            body = ""
        return None, f"TomTom HTTP {e.code}: {body[:300]}"
    except URLError as e:
        return None, f"TomTom unreachable: {e}"


def _tomtom_proxy(path, query_params=None, method="GET", json_body=None):
    """
    Call TomTom from the VPS (nginx → gunicorn). Key stays server-side; Referer matches whitelist.
    """
    data, err = _tomtom_get_json(path, query_params, method=method, json_body=json_body)
    if err:
        code = status.HTTP_503_SERVICE_UNAVAILABLE
        if "not configured" not in err:
            code = status.HTTP_502_BAD_GATEWAY
        return Response(
            {"status": "error", "message": err},
            status=code,
        )
    return Response(
        {"status": "success", "data": data},
        status=status.HTTP_200_OK,
    )


def _tomtom_fetch_binary(path, query_params=None):
    """Fetch PNG/binary from TomTom (map tiles)."""
    key = (getattr(settings, "TOMTOM_API_KEY", "") or "").strip()
    if not key:
        return None, None, "TomTom API key not configured"
    params = dict(query_params or {})
    params["key"] = key
    url = f"{TOMTOM_API_HOST.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urlencode(params)
    headers = {"Accept": "image/png,*/*", "Referer": _tomtom_referer()}
    req = Request(url, headers=headers, method="GET")
    try:
        with urlopen(req, timeout=20) as resp:
            data = resp.read()
            ct = resp.headers.get("Content-Type", "image/png")
            return data, ct, None
    except HTTPError as e:
        return None, None, f"TomTom tile HTTP {e.code}"
    except URLError as e:
        return None, None, str(e)


@api_view(["GET"])
@permission_classes([AllowAny])
def tomtom_tile(request, z, x, y):
    """Map tiles via nginx → Django (key not exposed to the app)."""
    style = (request.query_params.get("style") or "basic/main").strip()
    data, content_type, err = _tomtom_fetch_binary(
        f"map/1/tile/{style}/{z}/{x}/{y}.png",
        {"tileSize": "256"},
    )
    if err or not data:
        return Response(
            {"status": "error", "message": err or "Tile unavailable"},
            status=status.HTTP_502_BAD_GATEWAY,
        )
    return HttpResponse(data, content_type=content_type or "image/png")


@api_view(["GET"])
@permission_classes([AllowAny])
def tomtom_status(request):
    """Health check for TomTom via nginx → Django proxy."""
    key = (getattr(settings, "TOMTOM_API_KEY", "") or "").strip()
    if not key:
        return _success(
            {"configured": False, "reachable": False},
            message="TomTom key missing",
        )
    resp = _tomtom_proxy("search/2/geocode/Orlando.json", {"limit": 1})
    if resp.status_code >= 400:
        return _success(
            {
                "configured": True,
                "reachable": False,
                "upstream_status": resp.status_code,
            },
            message="TomTom unreachable",
        )
    return _success(
        {"configured": True, "reachable": True, "referer": _tomtom_referer()},
        message="TomTom OK",
    )


@api_view(["GET"])
@permission_classes([AllowAny])
def tomtom_search_hospitals(request):
    """
    TomTom Nearby Search backup for the Hospitals tab (no client API key).
    Query: lat, lon, radius_m (default 25000), limit (default 40)
    """
    lat = request.GET.get("lat")
    lon = request.GET.get("lon")
    if lat in (None, "") or lon in (None, ""):
        return _error({"lat": ["required"], "lon": ["required"]})
    try:
        lat_f = float(lat)
        lon_f = float(lon)
    except (TypeError, ValueError):
        return _error({"lat": ["invalid"], "lon": ["invalid"]})
    try:
        radius_m = int(request.GET.get("radius_m") or 25000)
    except (TypeError, ValueError):
        radius_m = 25000
    try:
        limit = int(request.GET.get("limit") or 40)
    except (TypeError, ValueError):
        limit = 40

    rows, err = _tomtom_hospitals_near(lat_f, lon_f, radius_m=radius_m, limit=limit)
    if err and not rows:
        return Response(
            {"status": "error", "message": err},
            status=status.HTTP_503_SERVICE_UNAVAILABLE
            if "not configured" in err
            else status.HTTP_502_BAD_GATEWAY,
        )
    return Response(
        {
            "status": "success",
            "data": rows,
            "source": "tomtom",
            "total_found": len(rows),
            "geo_note": "TomTom nearby hospital search (server proxy).",
        },
        status=status.HTTP_200_OK,
    )


@api_view(["GET"])
@permission_classes([AllowAny])
def tomtom_geocode(request):
    address = (request.query_params.get("address") or "").strip()
    if not address:
        return _error({"address": ["required"]})
    return _tomtom_proxy(f"search/2/geocode/{quote(address)}.json")


@api_view(["GET"])
@permission_classes([AllowAny])
def tomtom_reverse_geocode(request):
    try:
        lat = float(request.query_params.get("lat"))
        lon = float(request.query_params.get("lon"))
    except (TypeError, ValueError):
        return _error({"lat": ["required"], "lon": ["required"]})
    return _tomtom_proxy(f"search/2/reverseGeocode/{lat},{lon}.json")


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def tomtom_route(request):
    body = request.data if isinstance(request.data, dict) else {}
    origin = body.get("origin") or {}
    dest = body.get("destination") or {}
    try:
        o_lat, o_lon = float(origin.get("lat")), float(origin.get("lon"))
        d_lat, d_lon = float(dest.get("lat")), float(dest.get("lon"))
    except (TypeError, ValueError):
        return _error({"origin": ["lat/lon required"], "destination": ["lat/lon required"]})
    route_type = str(body.get("route_type") or "fastest").lower()
    travel_mode = "car"
    if route_type in ("eco", "green"):
        travel_mode = "car"
    path = f"routing/1/calculateRoute/{o_lat},{o_lon}:{d_lat},{d_lon}/json"
    return _tomtom_proxy(path, {"travelMode": travel_mode})


@api_view(["GET"])
@permission_classes([AllowAny])
def map_config(request):
    """Map settings for clients — TomTom key is not exposed; use /api/tomtom/* proxy."""
    base = (getattr(settings, "PUBLIC_API_BASE_URL", "") or "").rstrip("/")
    api_base = f"{base}/api/" if base else "/api/"
    return _success(
        {
            "tomtom_proxy": True,
            "tomtom_configured": bool(getattr(settings, "TOMTOM_API_KEY", "").strip()),
            "tomtom_base_path": "tomtom/",
            "tomtom_tile_url": "tomtom/tiles/{z}/{x}/{y}.png",
            "tomtom_search_hospitals": "tomtom/search-hospitals/",
            "api_base": api_base,
            "default_zoom": 12,
            "default_center": {"lat": 28.5383, "lon": -81.3792},
        }
    )


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
        api_base = (getattr(settings, "PUBLIC_API_BASE_URL", "") or "").rstrip("/")
        if api_base:
            link = f"{api_base}/reset-password/{uid}/{token}/"
        else:
            link = request.build_absolute_uri(f"/reset-password/{uid}/{token}/")
        support = getattr(settings, "SUPPORT_EMAIL", "info@innovatorsgeneration.com")
        body = (
            "You requested a password reset for Docs On Call (Doctor On Call).\n\n"
            f"Reset link: {link}\n\n"
            f"Questions? Contact {support}\n\n"
            "If you did not request this, ignore this email."
        )
        smtp_ready = bool((getattr(settings, "EMAIL_HOST", "") or "").strip())
        try:
            sent = send_mail(
                subject="Reset your Docs On Call password",
                message=body,
                from_email=getattr(settings, "DEFAULT_FROM_EMAIL", None),
                recipient_list=[email],
                fail_silently=not smtp_ready,
            )
            if smtp_ready and not sent:
                import logging
                logging.getLogger(__name__).warning(
                    "password_reset send_mail returned 0 for %s", email
                )
        except Exception as exc:
            import logging
            logging.getLogger(__name__).exception(
                "password_reset email failed for %s: %s", email, exc
            )

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


def _ollama_status_payload():
    """Shared status for Settings UI and public health check."""
    base, model = _ollama_base_and_model()
    health_to, gen_to = _ollama_bounded_timeouts()
    reachable, names, err_code, err_detail = _ollama_fetch_tag_names(base, health_to)
    model_available = reachable and _configured_model_in_tags(model, names)
    parsed = urlparse(base)
    host = (parsed.netloc or base).strip()
    linked = reachable and model_available

    if linked:
        message = f"Llama ({model}) is linked on the server via Ollama at {host}."
    elif reachable and not model_available:
        installed = ", ".join(names[:8]) if names else "(none)"
        message = (
            f"Ollama is reachable at {host} but model “{model}” is not installed. "
            f"On the VPS run: ollama pull {model}. Tags seen: {installed}"
        )
    else:
        label = {
            "timeout": "Ollama did not respond in time.",
            "dns_error": "Cannot resolve Ollama host.",
            "connection_refused": "Ollama is not running (connection refused).",
        }.get(err_code, "Ollama is not reachable from the API server.")
        hint = err_detail.strip()[:160] if err_detail else ""
        message = f"{label} Host: {host}.{(f' {hint}' if hint else '')} "
        message += "On GoDaddy VPS, set OLLAMA_BASE_URL and run Ollama (e.g. ollama serve)."

    return {
        "linked": linked,
        "reachable": reachable,
        "model_available": model_available,
        "error_code": err_code,
        "error_detail": err_detail,
        "models": names,
        "configured_model": model,
        "ollama_host": host,
        "ollama_base_url": base,
        "message": message,
        "generate_timeout_seconds": gen_to,
        "health_timeout_seconds": health_to,
    }


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
            try:
                pid = int(patient_id)
            except (TypeError, ValueError):
                return _error({"patient_id": ["invalid"]})
            if not _is_staffish(user):
                prov = Provider.objects.filter(user=user).first()
                if not prov:
                    return _error({"detail": ["forbidden"]}, status.HTTP_403_FORBIDDEN)
                linked = Appointment.objects.filter(
                    provider=prov, patient_id=pid
                ).exists()
                if not linked:
                    return _error(
                        {"patient_id": ["no appointment with this patient"]},
                        status.HTTP_403_FORBIDDEN,
                    )
            qs = qs.filter(patient_id=pid)
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


def _ollama_bounded_timeouts():
    try:
        h = int(getattr(settings, "OLLAMA_HEALTH_TIMEOUT", 5) or 5)
    except (TypeError, ValueError):
        h = 5
    try:
        g = int(getattr(settings, "OLLAMA_GENERATE_TIMEOUT", 180) or 180)
    except (TypeError, ValueError):
        g = 180
    return max(1, min(h, 120)), max(10, min(g, 7200))


def _ollama_base_and_model():
    base = (getattr(settings, "OLLAMA_BASE_URL", "") or "").strip() or "http://127.0.0.1:11434"
    model = (getattr(settings, "OLLAMA_MODEL", "") or "").strip() or "llama3.1"
    return base, model


def _truncate_ai_detail(value, limit=420):
    s = str(value or "").strip()
    if len(s) <= limit:
        return s
    return s[: limit - 1] + "…"


def _classify_urllib_issue(exc):
    r = getattr(exc, "reason", None)
    if isinstance(r, (socket.timeout, TimeoutError)):
        return "timeout", "The AI server took too long to respond."
    if isinstance(r, ConnectionRefusedError):
        return "connection_refused", "Cannot connect to the AI server (connection refused)."
    if isinstance(r, OSError) and getattr(r, "errno", None) == errno.ECONNREFUSED:
        return "connection_refused", "Cannot connect to the AI server (connection refused)."
    if isinstance(r, socket.gaierror):
        return "dns_error", "Could not resolve the AI server address."
    low = str(exc).lower()
    if "timed out" in low or isinstance(r, TimeoutError):
        return "timeout", "The AI server took too long to respond."
    if "refused" in low:
        return "connection_refused", "Cannot connect to the AI server (connection refused)."
    if any(x in low for x in ("name or service not known", "nodename nor servname", "getaddrinfo failed")):
        return "dns_error", "Could not resolve the AI server address."
    return "connection_error", "Could not reach the AI server."


def _ollama_fetch_tag_names(base, timeout_sec):
    """Return (ok, tag_names, err_code, err_detail)."""
    url = base.rstrip("/") + "/api/tags"
    try:
        req = Request(url, method="GET")
        with urlopen(req, timeout=timeout_sec) as resp:
            raw = resp.read().decode("utf-8", errors="ignore")
        body = json.loads(raw) if raw.strip() else {}
        models = body.get("models") if isinstance(body, dict) else None
        names = []
        if isinstance(models, list):
            for m in models:
                if isinstance(m, dict) and m.get("name"):
                    names.append(str(m["name"]))
                elif isinstance(m, str):
                    names.append(m)
        return True, names, None, None
    except HTTPError as e:
        try:
            chunk = e.read().decode("utf-8", errors="ignore") if e.fp else ""
        except Exception:
            chunk = ""
        tail = _truncate_ai_detail(chunk or str(e.reason or e.code))
        return False, [], "http_error", f"HTTP {e.code}: {tail}"
    except URLError as e:
        code, _ = _classify_urllib_issue(e)
        return False, [], code, _truncate_ai_detail(str(e.reason or e))
    except (TimeoutError, socket.timeout):
        return False, [], "timeout", _truncate_ai_detail("Timed out")
    except json.JSONDecodeError as e:
        return False, [], "invalid_response", _truncate_ai_detail(str(e))
    except Exception as e:
        return False, [], "unknown", _truncate_ai_detail(str(e))


def _configured_model_in_tags(wanted, tag_names):
    w = (wanted or "").strip().lower()
    if not w:
        return False
    w_base = w.split(":", 1)[0].strip()
    for n in tag_names:
        nl = str(n).lower().strip()
        if nl == w or nl == w_base or nl.startswith(w_base + ":"):
            return True
    return False


def _ai_assist_fail_response(code, message, detail="", status_code=status.HTTP_502_BAD_GATEWAY):
    return Response(
        {
            "status": "error",
            "code": code,
            "message": str(message or "AI assist unavailable"),
            "detail": _truncate_ai_detail(detail),
        },
        status=status_code,
    )


@api_view(["GET"])
@permission_classes([AllowAny])
def ai_assist_status(request):
    """Public lightweight check — `GET /api/integrations/ai-assist-status/` (always HTTP 200)."""
    payload = _ollama_status_payload()
    ready = payload["linked"]
    return _success(
        {
            "ai_assist_ready": ready,
            "linked": ready,
            "assist_message": "" if ready else payload["message"],
            "configured_model": payload["configured_model"],
            "ollama_host": payload["ollama_host"],
            "generate_timeout_seconds": payload["generate_timeout_seconds"],
            "health_timeout_seconds": payload["health_timeout_seconds"],
        },
        message="OK",
    )


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def ollama_status(request):
    """`GET …/integrations/ollama-status/` — Llama/Ollama link status for Settings (authenticated)."""
    return _success(_ollama_status_payload(), message="OK")


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
    base, model = _ollama_base_and_model()
    _, gen_timeout = _ollama_bounded_timeouts()
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
        with urlopen(req, timeout=gen_timeout) as resp:
            raw = resp.read().decode("utf-8", errors="ignore")
        out = json.loads(raw) if raw else {}
        answer = str(out.get("response") or "").strip()
        if isinstance(out.get("error"), str) and out.get("error").strip():
            return _ai_assist_fail_response(
                "model_error",
                "The AI server reported an error running the model.",
                out.get("error"),
            )
        if not answer:
            return _ai_assist_fail_response(
                "empty_response",
                "The model returned an empty reply.",
                _truncate_ai_detail(raw),
            )

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
                "subjective": _soap_section_text(soap_json.get("subjective")),
                "objective": _soap_section_text(soap_json.get("objective")),
                "assessment": _soap_section_text(soap_json.get("assessment")),
                "plan": _soap_section_text(soap_json.get("plan")),
            }

        return _success(payload, message="AI assist")
    except HTTPError as e:
        try:
            msg = e.read().decode("utf-8", errors="ignore")
        except Exception:
            msg = str(e)
        detail = _truncate_ai_detail(msg or str(e.reason or e.code))
        if e.code == 404:
            return _ai_assist_fail_response(
                "model_missing",
                "The configured model may be missing from Ollama.",
                detail,
            )
        return _ai_assist_fail_response("http_error", "The AI server returned an error.", detail)
    except URLError as e:
        code, short = _classify_urllib_issue(e)
        return _ai_assist_fail_response(code, short, _truncate_ai_detail(str(e.reason or e)))
    except (TimeoutError, socket.timeout):
        return _ai_assist_fail_response(
            "timeout",
            "The AI request timed out.",
            f"Limit was {gen_timeout}s (OLLAMA_GENERATE_TIMEOUT).",
        )
    except json.JSONDecodeError as e:
        return _ai_assist_fail_response("invalid_response", "Could not parse AI response.", _truncate_ai_detail(str(e)))
    except Exception as e:
        return _ai_assist_fail_response("server_error", "AI assist failed.", _truncate_ai_detail(str(e)), status.HTTP_500_INTERNAL_SERVER_ERROR)


HIPAA_DISCLAIMER = (
    "Disclaimer: This feature is for care coordination only and does not provide medical advice. "
    "Do not share highly sensitive information unless necessary. "
    "AI summaries may be incomplete or incorrect; clinicians must verify against source records. "
    "If you have an emergency, call local emergency services."
)


def _float_or_none(val):
    if val in (None, ""):
        return None
    try:
        return float(val)
    except (TypeError, ValueError):
        return None


def _int_or_none(val):
    if val in (None, ""):
        return None
    try:
        return int(float(val))
    except (TypeError, ValueError):
        return None


def _soap_section_text(value) -> str:
    """Normalize SOAP section for storage/display (LLM may return nested dicts)."""
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, dict):
        parts = []
        syms = value.get("symptoms")
        if isinstance(syms, list) and syms:
            parts.append("Symptoms: " + ", ".join(str(s) for s in syms))
        elif syms not in (None, ""):
            parts.append(f"Symptoms: {syms}")
        duration = value.get("duration")
        if duration not in (None, ""):
            parts.append(f"Duration: {duration}")
        history = value.get("history")
        if isinstance(history, list) and history:
            parts.append("History: " + "; ".join(str(h) for h in history))
        elif history not in (None, ""):
            parts.append(f"History: {history}")
        if parts:
            return "\n".join(parts)
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "\n".join(str(x).strip() for x in value if str(x).strip())
    return str(value).strip()


def _format_triage_summary(data: dict) -> str:
    lines = ["Triage (patient-shared)"]
    mapping = [
        ("height_cm", "Height (cm)"),
        ("weight_kg", "Weight (kg)"),
        ("bmi", "BMI"),
        ("temp_c", "Temp (°C)"),
        ("temperature_c", "Temp (°C)"),
        ("bp_sys", "BP systolic"),
        ("bp_dia", "BP diastolic"),
        ("pulse_bpm", "Pulse (bpm)"),
        ("resp_rate", "Resp (/min)"),
        ("resp_min", "Resp (/min)"),
        ("spo2_pct", "SpO2 (%)"),
        ("spo2", "SpO2 (%)"),
        ("glucose_mg_dl", "Glucose (mg/dL)"),
        ("glucose_mgdl", "Glucose (mg/dL)"),
    ]
    for key, label in mapping:
        val = data.get(key)
        if val not in (None, ""):
            lines.append(f"{label}: {val}")
    notes = (data.get("notes") or "").strip()
    if notes:
        lines.append(f"Notes: {notes}")
    if data.get("skin_photo_attached"):
        lines.append("Skin photo: attached on device (not uploaded)")
    return "\n".join(lines)


def _provider_linked_to_patient(provider, patient_id: int) -> bool:
    return Appointment.objects.filter(provider=provider, patient_id=patient_id).exists()


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def shares_mine(request):
    """Patient view: shares created by the logged-in patient."""
    user = request.user
    p = _get_patient_for_user(user)
    if not p:
        return _success({"results": [], "disclaimer": HIPAA_DISCLAIMER})
    qs = (
        PatientShare.objects.filter(patient=p)
        .select_related("provider", "patient", "vital", "appointment")
        [:200]
    )
    ser = PatientShareSerializer(qs, many=True)
    return _success({"results": ser.data, "disclaimer": HIPAA_DISCLAIMER})


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def shares_inbox(request):
    """Provider/staff view: shares sent to this provider."""
    user = request.user
    if _is_staffish(user):
        qs = PatientShare.objects.select_related(
            "provider", "patient", "vital", "appointment"
        ).all()[:200]
    else:
        prov = Provider.objects.filter(user=user).first()
        if not prov:
            return _error({"detail": ["Only providers can access inbox."]}, status.HTTP_403_FORBIDDEN)
        qs = (
            PatientShare.objects.filter(provider=prov)
            .select_related("provider", "patient", "vital", "appointment")
            [:200]
        )
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


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def shares_triage_create(request):
    """
  Patient shares triage vitals with a doctor.
  Body: provider_id (required), vitals (object), patient_note (optional),
        appointment_id (optional), include_patient_email (optional bool).
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

    if not Appointment.objects.filter(provider=prov, patient=p).exists():
        return _error(
            {"provider_id": ["book an appointment with this doctor first"]},
            status.HTTP_403_FORBIDDEN,
        )

    vitals = request.data.get("vitals") or request.data.get("triage") or {}
    if not isinstance(vitals, dict):
        return _error({"vitals": ["must be an object"]})

    note = str(request.data.get("patient_note") or request.data.get("note") or "").strip()[:8000]
    include_email = bool(
        request.data.get("include_patient_email") in (True, "true", "1", 1, "yes")
    )

    appt = None
    raw_appt = request.data.get("appointment_id")
    if raw_appt not in (None, ""):
        try:
            appt_id = int(raw_appt)
        except (TypeError, ValueError):
            return _error({"appointment_id": ["invalid"]})
        appt = Appointment.objects.filter(
            id=appt_id, patient=p, provider=prov
        ).first()
        if not appt:
            return _error({"appointment_id": ["not found for this doctor"]})

    vital = PatientVital.objects.create(
        patient=p,
        recorded_by=user,
        height_cm=_float_or_none(vitals.get("height_cm")),
        weight_kg=_float_or_none(vitals.get("weight_kg")),
        temperature_c=_float_or_none(vitals.get("temp_c") or vitals.get("temperature_c")),
        bp_sys=_int_or_none(vitals.get("bp_sys")),
        bp_dia=_int_or_none(vitals.get("bp_dia")),
        pulse_bpm=_int_or_none(vitals.get("pulse_bpm")),
        resp_min=_int_or_none(vitals.get("resp_rate") or vitals.get("resp_min")),
        spo2=_int_or_none(vitals.get("spo2_pct") or vitals.get("spo2")),
        glucose_mgdl=_float_or_none(vitals.get("glucose_mg_dl") or vitals.get("glucose_mgdl")),
        notes=str(vitals.get("notes") or note or "").strip()[:4000],
    )

    triage_payload = dict(vitals)
    triage_payload["type"] = triage_payload.get("type") or "triage-v1"
    triage_payload["vital_id"] = vital.id
    if vitals.get("skin_photo_path") or vitals.get("skin_photo_attached"):
        triage_payload["skin_photo_attached"] = True
    summary = _format_triage_summary(triage_payload)

    share = PatientShare.objects.create(
        patient=p,
        provider=prov,
        patient_note=note or "Triage vitals shared with doctor",
        ai_summary=summary[:20000],
        include_patient_email=include_email,
        share_kind=PatientShare.ShareKind.TRIAGE,
        triage_payload=json.dumps(triage_payload)[:50000],
        vital=vital,
        appointment=appt,
        status=PatientShare.Status.SENT,
    )
    ser = PatientShareSerializer(share)
    return _success(
        {
            "share": ser.data,
            "vital": PatientVitalSerializer(vital).data,
            "disclaimer": HIPAA_DISCLAIMER,
        },
        message="Triage shared with doctor",
    )


@api_view(["GET", "POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def visit_notes(request):
    """
    GET: list visit notes (SOAP) for patient, provider, or staff.
      Query: appointment_id, patient_id
    POST: provider/staff sends SOAP to patient (creates VisitNote + MedicalRecord).
    """
    user = request.user

    if request.method == "GET":
        qs = VisitNote.objects.select_related("provider", "patient", "appointment")
        appointment_id = request.query_params.get("appointment_id")
        patient_id = request.query_params.get("patient_id")

        if _is_staffish(user):
            if appointment_id:
                try:
                    qs = qs.filter(appointment_id=int(appointment_id))
                except (TypeError, ValueError):
                    return _error({"appointment_id": ["invalid"]})
            if patient_id:
                try:
                    qs = qs.filter(patient_id=int(patient_id))
                except (TypeError, ValueError):
                    return _error({"patient_id": ["invalid"]})
        else:
            p = _get_patient_for_user(user)
            prov = Provider.objects.filter(user=user).first()
            if p:
                qs = qs.filter(patient=p)
            elif prov:
                qs = qs.filter(provider=prov)
                if patient_id:
                    try:
                        pid = int(patient_id)
                    except (TypeError, ValueError):
                        return _error({"patient_id": ["invalid"]})
                    if not _provider_linked_to_patient(prov, pid):
                        return _error(
                            {"patient_id": ["no appointment with this patient"]},
                            status.HTTP_403_FORBIDDEN,
                        )
                    qs = qs.filter(patient_id=pid)
            else:
                return _success({"results": []})
            if appointment_id:
                try:
                    qs = qs.filter(appointment_id=int(appointment_id))
                except (TypeError, ValueError):
                    return _error({"appointment_id": ["invalid"]})

        ser = VisitNoteSerializer(qs[:200], many=True)
        return _success({"results": ser.data})

    if not (_is_staffish(user) or user.provider_profiles.exists()):
        return _error({"detail": ["Only providers can send visit notes"]}, status.HTTP_403_FORBIDDEN)

    prov = Provider.objects.filter(user=user).first()
    if _is_staffish(user):
        raw_prov = request.data.get("provider_id")
        if raw_prov not in (None, ""):
            try:
                prov = Provider.objects.filter(id=int(raw_prov)).first()
            except (TypeError, ValueError):
                return _error({"provider_id": ["invalid"]})
    if not prov:
        return _error({"provider": ["No provider profile found"]}, status.HTTP_404_NOT_FOUND)

    try:
        patient_id = int(request.data.get("patient_id"))
    except (TypeError, ValueError):
        return _error({"patient_id": ["required"]})
    patient = Patient.objects.filter(id=patient_id).first()
    if not patient:
        return _error({"patient_id": ["not found"]}, status.HTTP_404_NOT_FOUND)

    if not _is_staffish(user) and not _provider_linked_to_patient(prov, patient_id):
        return _error(
            {"patient_id": ["no appointment with this patient"]},
            status.HTTP_403_FORBIDDEN,
        )

    subjective = _soap_section_text(request.data.get("subjective"))[:8000]
    objective = _soap_section_text(request.data.get("objective"))[:8000]
    assessment = _soap_section_text(request.data.get("assessment"))[:8000]
    plan = _soap_section_text(request.data.get("plan"))[:8000]
    if not any([subjective.strip(), objective.strip(), assessment.strip(), plan.strip()]):
        return _error({"detail": ["At least one SOAP section is required"]})

    appt = None
    raw_appt = request.data.get("appointment_id")
    if raw_appt not in (None, ""):
        try:
            appt_id = int(raw_appt)
        except (TypeError, ValueError):
            return _error({"appointment_id": ["invalid"]})
        appt = Appointment.objects.filter(id=appt_id).first()
        if not appt or appt.patient_id != patient.id:
            return _error({"appointment_id": ["not found for this patient"]})
        if appt.provider_id != prov.id and not _is_staffish(user):
            return _error({"appointment_id": ["not your appointment"]}, status.HTTP_403_FORBIDDEN)

    note = VisitNote.objects.create(
        patient=patient,
        provider=prov,
        appointment=appt,
        subjective=subjective,
        objective=objective,
        assessment=assessment,
        plan=plan,
    )

    soap_payload = {
        "type": "soap-v1",
        "visit_note_id": note.id,
        "subjective": subjective,
        "objective": objective,
        "assessment": assessment,
        "plan": plan,
        "provider_id": prov.id,
        "patient_id": patient.id,
        "appointment_id": appt.id if appt else None,
    }
    ai_line = subjective.strip() or assessment.strip() or plan.strip()
    mr = MedicalRecord.objects.create(
        patient=patient,
        title=f"SOAP — Dr. {prov.full_name or prov.id}",
        raw_payload=json.dumps(soap_payload)[:50000],
        ai_summary=ai_line[:2000],
        merged_by=user,
    )
    note.medical_record = mr
    note.save(update_fields=["medical_record"])
    if appt:
        appt.medical_record = mr
        appt.save(update_fields=["medical_record"])

    ser = VisitNoteSerializer(note)
    return _success(
        {
            "visit_note": ser.data,
            "medical_record_id": mr.id,
        },
        message="SOAP note sent to patient",
    )


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
        send_mail(
            subject,
            body,
            getattr(settings, "DEFAULT_FROM_EMAIL", None),
            [patient_email],
            fail_silently=False,
        )
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
    allowance = _patient_subscription_allowance(p) if p else {}
    return _success({
        "active": PatientSubscriptionSerializer(sub).data if sub else None,
        "visit_allowance": allowance,
    })


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def billing_checkout(request):
    """
    Subscribe to a monthly plan.
    - platform apple|android → RevenueCat product_id for App Store / Play (mobile app).
    - platform web → Stripe Checkout URL (browser only; mobile must not use web for plans).
    Extra visit invoices: POST billing/patient/pay-bill/ (Stripe), not this endpoint.
    Body: { plan_id, platform: "apple"|"android"|"web" }
    """
    import stripe

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

    platform = (request.data.get("platform") or "web").lower().strip()

    if platform in ("apple", "android"):
        store_product_id = (plan.revenuecat_product_id or "").strip() or f"doc_{plan.plan_name.lower()}_monthly"
        return _success(
            {
                "product_id": store_product_id,
                "plan_id": plan.id,
                "plan_name": plan.plan_name,
                "price": plan.price,
                "platform": platform,
                "purchase_channel": "app_store" if platform == "apple" else "google_play",
                "number_appointments": plan.number_appointments,
                "revenuecat_product_id": store_product_id,
            },
            message="Purchase in app, then POST billing/verify-store/ with receipt",
        )

    if platform != "web":
        return _error(
            {"platform": ["Use apple, android, or web"]},
            status.HTTP_400_BAD_REQUEST,
        )

    stripe.api_key = settings.STRIPE_SECRET_KEY
    if not stripe.api_key:
        return _error(
            {"billing": ["Stripe is not configured on server. Use iOS/Android in-app purchase."]},
            status.HTTP_501_NOT_IMPLEMENTED,
        )

    frontend = (getattr(settings, "FRONTEND_BASE_URL", "") or "").rstrip("/") or "https://docsoncalls.com"
    try:
        amount_cents = int(round(float(str(plan.price).replace("$", "").strip()) * 100))
    except Exception:
        return _error({"price": ["Plan price invalid"]})
    if amount_cents <= 0:
        return _error({"price": ["Plan price must be > 0"]})

    session = stripe.checkout.Session.create(
        mode="payment",
        success_url=frontend + "/?billing=success",
        cancel_url=frontend + "/?billing=cancel",
        customer_email=(p.email or "").strip() or None,
        line_items=[{
            "price_data": {
                "currency": "usd",
                "product_data": {"name": f"Docs On Call plan: {plan.plan_name}"},
                "unit_amount": amount_cents,
            },
            "quantity": 1,
        }],
        metadata={"patient_id": str(p.id), "plan_id": str(plan.id)},
    )
    return _success(
        {"url": session.url, "session_id": session.id, "checkout_url": session.url},
        message="Open Stripe Checkout in browser",
    )


def _plan_for_store_product(product_id):
    pid = (product_id or "").strip()
    if not pid:
        return None
    plan = Plan.objects.filter(revenuecat_product_id__iexact=pid).first()
    if plan:
        return plan
    return Plan.objects.filter(plan_name__iexact=pid).first()


def _verify_apple_receipt(verification_data, expected_product_id):
    """
    Verify App Store receipt with Apple. Returns (ok, detail).
    If APPLE_SHARED_SECRET is unset and STORE_VERIFY_STRICT is false, accepts client proof.
    """
    secret = (getattr(settings, "APPLE_SHARED_SECRET", "") or "").strip()
    strict = getattr(settings, "STORE_VERIFY_STRICT", False)
    receipt = (verification_data or "").strip()
    if not receipt:
        return False, "missing_receipt"
    if not secret:
        if strict:
            return False, "APPLE_SHARED_SECRET not configured"
        return True, "accepted_without_apple_verify"

    import json
    from urllib.error import HTTPError, URLError
    from urllib.request import Request, urlopen

    payload = json.dumps(
        {
            "receipt-data": receipt,
            "password": secret,
            "exclude-old-transactions": True,
        }
    ).encode("utf-8")
    urls = [
        "https://buy.itunes.apple.com/verifyReceipt",
        "https://sandbox.itunes.apple.com/verifyReceipt",
    ]
    last_err = "apple_verify_failed"
    for url in urls:
        try:
            req = Request(
                url,
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urlopen(req, timeout=25) as resp:
                body = json.loads(resp.read().decode("utf-8", errors="replace"))
            status = body.get("status")
            if status == 21007 and "sandbox" not in url:
                continue
            if status != 0:
                last_err = f"apple_status_{status}"
                continue
            for item in body.get("latest_receipt_info") or []:
                if (item.get("product_id") or "").lower() == expected_product_id.lower():
                    return True, "verified"
            for item in (body.get("receipt") or {}).get("in_app") or []:
                if (item.get("product_id") or "").lower() == expected_product_id.lower():
                    return True, "verified"
            return False, "product_not_in_receipt"
        except HTTPError as e:
            last_err = f"apple_http_{e.code}"
        except URLError as e:
            last_err = str(e)
        except Exception as e:
            last_err = str(e)
    return False, last_err


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def billing_verify_store(request):
    """
    Activate subscription after direct App Store / Google Play purchase (no RevenueCat).
    Body: plan_id, platform (apple|android), product_id, purchase_id,
          verification_data, local_verification_data (optional), transaction_date (optional)
    """
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

    platform = (request.data.get("platform") or "").lower().strip()
    if platform not in ("apple", "android"):
        return _error({"platform": ["Use apple or android"]})

    product_id = (request.data.get("product_id") or plan.revenuecat_product_id or "").strip()
    if not product_id:
        return _error({"product_id": ["required"]})

    mapped = _plan_for_store_product(product_id)
    if mapped and mapped.id != plan.id:
        plan = mapped

    purchase_id = (request.data.get("purchase_id") or "").strip()
    verification_data = (request.data.get("verification_data") or "").strip()
    if not purchase_id and not verification_data:
        return _error({"purchase_id": ["purchase_id or verification_data required"]})

    verify_note = "google_accepted"
    if platform == "apple":
        ok, detail = _verify_apple_receipt(verification_data, product_id)
        if not ok:
            return _error(
                {"receipt": [detail]},
                status.HTTP_400_BAD_REQUEST,
            )
        verify_note = detail
    else:
        strict = getattr(settings, "STORE_VERIFY_STRICT", False)
        if strict and not verification_data:
            return _error(
                {"verification_data": ["required for Google Play in strict mode"]},
                status.HTTP_400_BAD_REQUEST,
            )

    store_label = "APP_STORE" if platform == "apple" else "PLAY_STORE"
    original_tx = purchase_id or verification_data[:128]
    entitlement = (plan.revenuecat_entitlement_id or plan.plan_name or "").strip()

    PatientSubscription.objects.update_or_create(
        patient=p,
        defaults={
            "plan": plan,
            "status": PatientSubscription.Status.ACTIVE,
            "revenuecat_product_id": product_id,
            "revenuecat_entitlement_id": entitlement,
            "platform": store_label,
            "original_transaction_id": original_tx,
            "will_renew": True,
        },
    )
    allowance = _patient_subscription_allowance(p)
    sub = (
        PatientSubscription.objects.filter(patient=p, status=PatientSubscription.Status.ACTIVE)
        .select_related("plan")
        .first()
    )
    return _success(
        {
            "active": PatientSubscriptionSerializer(sub).data if sub else None,
            "visit_allowance": allowance,
            "verified": verify_note,
        },
        message="Subscription active",
    )


@api_view(["POST"])
@permission_classes([AllowAny])
def billing_webhook(request):
    """Optional legacy RevenueCat webhook (app uses billing/verify-store/ instead)."""
    import json

    payload = request.body
    if not payload:
        return Response({"ok": False, "detail": "empty body"}, status=400)

    secret = (getattr(settings, "REVENUECAT_WEBHOOK_SECRET", "") or "").strip()
    if secret:
        auth = (request.headers.get("Authorization") or "").strip()
        header_secret = (request.headers.get("X-RevenueCat-Webhook-Secret") or "").strip()
        if auth not in (secret, f"Bearer {secret}") and header_secret != secret:
            return Response({"ok": False, "detail": "unauthorized"}, status=401)

    try:
        event = json.loads(payload)
    except Exception:
        return Response({"ok": False}, status=400)

    event_type = event.get("event", "")
    if event_type in ("INITIAL_PURCHASE", "RENEWAL", "PRODUCT_CHANGE"):
        app_user_id = event.get("app_user_id", "")
        product_id = event.get("product_id", "")
        entitlement_id = event.get("entitlement_id", "")
        store = event.get("store", "unknown")
        transaction_id = event.get("transaction_id", "")
        country = event.get("store_country", "")
        will_renew = event.get("auto_resume_at", False) or event.get("auto_resume_at") is not None
        expires_at_ms = event.get("expires_at_ms")

        # Map RevenueCat product to our Plan
        plan = Plan.objects.filter(revenuecat_product_id__iexact=product_id).first()
        if not plan:
            plan = Plan.objects.filter(revenuecat_entitlement_id__iexact=entitlement_id).first()
        if not plan:
            plan = Plan.objects.filter(plan_name__iexact=product_id).first()
        if not plan:
            plan = Plan.objects.filter(plan_name__iexact=entitlement_id).first()

        user_id = None
        try:
            user_id = int(app_user_id)
        except (ValueError, TypeError):
            pass

        patient = None
        if user_id:
            patient = Patient.objects.filter(user_id=user_id).first()
        if not patient:
            patient = Patient.objects.filter(user__email=event.get("email", "")).first()

        if patient and not plan:
            return Response(
                {
                    "ok": False,
                    "detail": "unknown_product",
                    "product_id": product_id,
                    "entitlement_id": entitlement_id,
                },
                status=400,
            )

        if patient and plan:
            expires_at = None
            if expires_at_ms:
                from datetime import datetime
                expires_at = datetime.fromtimestamp(expires_at_ms / 1000, tz=timezone.utc)

            PatientSubscription.objects.update_or_create(
                patient=patient,
                defaults={
                    "plan": plan,
                    "status": PatientSubscription.Status.ACTIVE,
                    "revenuecat_product_id": product_id,
                    "revenuecat_entitlement_id": entitlement_id,
                    "platform": store,
                    "original_transaction_id": transaction_id,
                    "store_country": country,
                    "will_renew": will_renew,
                    "expires_at": expires_at,
                },
            )

    elif event_type == "CANCELLATION":
        app_user_id = event.get("app_user_id", "")
        try:
            uid = int(app_user_id)
        except (ValueError, TypeError):
            uid = None
        if uid:
            patient = Patient.objects.filter(user_id=uid).first()
            if patient:
                PatientSubscription.objects.filter(
                    patient=patient, status=PatientSubscription.Status.ACTIVE
                ).update(status=PatientSubscription.Status.CANCELED, will_renew=False)

    return Response({"ok": True}, status=200)


# ──────────────────────────────────────────────
# Doctor Billing: provider ↔ patient transactions
# ──────────────────────────────────────────────

@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def doctor_billing_summary(request):
    """Return billing summary for the current provider."""
    provider = Provider.objects.filter(user=request.user).first()
    if not provider:
        return _error({"provider": ["No provider profile"]}, status.HTTP_404_NOT_FOUND)

    now = timezone.now()
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    transactions = ProviderTransaction.objects.filter(provider=provider)
    total_earned = sum(
        (t.provider_payout or 0) for t in transactions.filter(status=ProviderTransaction.Status.COMPLETED)
    )
    month_earned = sum(
        (t.provider_payout or 0)
        for t in transactions.filter(
            status=ProviderTransaction.Status.COMPLETED, completed_at__gte=month_start
        )
    )
    pending = sum(
        (t.amount or 0) for t in transactions.filter(status=ProviderTransaction.Status.PENDING)
    )
    platform_fees = sum(
        (t.platform_fee or 0) for t in transactions.filter(status=ProviderTransaction.Status.COMPLETED)
    )

    connect_ready = bool(
        (provider.stripe_connect_account_id or "").strip()
        and provider.stripe_connect_onboarded
    )

    default_fee = (
        float(provider.consultation_fee)
        if provider.consultation_fee is not None
        else None
    )

    return _success({
        "total_earned": float(total_earned),
        "month_earned": float(month_earned),
        "pending_amount": float(pending),
        "platform_fees": float(platform_fees),
        "transaction_count": transactions.count(),
        "commission_percent": float(
            getattr(settings, "PLATFORM_COMMISSION_PERCENT", 15)
        ),
        "consultation_fee": default_fee,
        "offers_free_consultation": _provider_offers_free_consultation(provider),
        "stripe_connect_account_id": provider.stripe_connect_account_id or "",
        "stripe_connect_onboarded": connect_ready,
        "payouts": ProviderPayoutSerializer(
            ProviderPayout.objects.filter(provider=provider).order_by("-requested_at")[:10],
            many=True,
        ).data,
    })


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def doctor_transactions(request):
    """Return transaction history for the current provider."""
    provider = Provider.objects.filter(user=request.user).first()
    if not provider:
        return _error({"provider": ["No provider profile"]}, status.HTTP_404_NOT_FOUND)

    transactions = ProviderTransaction.objects.filter(provider=provider).select_related("patient")
    return _success({
        "transactions": ProviderTransactionSerializer(transactions, many=True).data,
    })


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def doctor_create_invoice(request):
    """Doctor creates an invoice for a patient."""
    provider = Provider.objects.filter(user=request.user).first()
    if not provider:
        return _error({"provider": ["No provider profile"]}, status.HTTP_404_NOT_FOUND)

    patient_id = request.data.get("patient_id")
    amount = request.data.get("amount")
    notes = request.data.get("notes", "")
    appointment_id = request.data.get("appointment_id")
    complimentary = request.data.get("complimentary") in (True, "true", "1", 1) or (
        "/complimentary-visit/" in (getattr(request, "path", "") or "")
    )
    use_default_fee = request.data.get("use_default_fee") in (True, "true", "1", 1)

    if not patient_id:
        return _error({"patient_id": ["required"]})

    patient = Patient.objects.filter(id=patient_id).first()
    if not patient:
        return _error({"patient_id": ["not found"]}, status.HTTP_404_NOT_FOUND)

    if complimentary:
        amount_val = 0.0
        commission_pct = float(getattr(settings, "PLATFORM_COMMISSION_PERCENT", 15))
        platform_fee = 0.0
        provider_payout = 0.0
        note_text = (notes or "").strip() or "Complimentary / free visit"
        tx = ProviderTransaction.objects.create(
            appointment_id=appointment_id or None,
            patient=patient,
            provider=provider,
            amount=amount_val,
            platform_commission_percent=commission_pct,
            platform_fee=platform_fee,
            provider_payout=provider_payout,
            status=ProviderTransaction.Status.COMPLETED,
            notes=note_text,
            completed_at=timezone.now(),
        )
        return _success({
            "transaction": ProviderTransactionSerializer(tx).data,
        }, message="Free visit recorded")

    if use_default_fee and provider.consultation_fee is not None:
        amount = provider.consultation_fee

    if amount in (None, ""):
        return _error({"amount": ["required (or set complimentary / use_default_fee)"]})

    try:
        amount_val = float(amount)
    except (TypeError, ValueError):
        return _error({"amount": ["invalid number"]})

    if amount_val <= 0:
        return _error({"amount": ["must be > 0 (use complimentary for free visits)"]})

    commission_pct = float(getattr(settings, "PLATFORM_COMMISSION_PERCENT", 15))
    platform_fee = round(amount_val * commission_pct / 100, 2)
    provider_payout = round(amount_val - platform_fee, 2)

    tx = ProviderTransaction.objects.create(
        appointment_id=appointment_id or None,
        patient=patient,
        provider=provider,
        amount=amount_val,
        platform_commission_percent=commission_pct,
        platform_fee=platform_fee,
        provider_payout=provider_payout,
        status=ProviderTransaction.Status.PENDING,
        notes=notes,
    )

    return _success({
        "transaction": ProviderTransactionSerializer(tx).data,
    }, message="Invoice created")


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def patient_bills(request):
    """Return unpaid/completed bills for the current patient."""
    patient = Patient.objects.filter(user=request.user).first()
    if not patient:
        return _error({"patient": ["No patient profile"]}, status.HTTP_404_NOT_FOUND)

    transactions = ProviderTransaction.objects.filter(patient=patient).select_related("provider")
    return _success({
        "bills": ProviderTransactionSerializer(transactions, many=True).data,
    })


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def patient_pay_bill(request):
    """Patient pays a pending bill via Stripe."""
    import stripe

    if not getattr(settings, "STRIPE_SECRET_KEY", ""):
        return _error({"billing": ["Stripe is not configured."]}, status.HTTP_501_NOT_IMPLEMENTED)

    patient = Patient.objects.filter(user=request.user).first()
    if not patient:
        return _error({"patient": ["No patient profile"]}, status.HTTP_404_NOT_FOUND)

    tx_id = request.data.get("transaction_id")
    tx = ProviderTransaction.objects.filter(id=tx_id, patient=patient, status=ProviderTransaction.Status.PENDING).first()
    if not tx:
        return _error({"transaction_id": ["not found or already paid"]}, status.HTTP_404_NOT_FOUND)

    stripe.api_key = settings.STRIPE_SECRET_KEY
    frontend = (getattr(settings, "FRONTEND_BASE_URL", "") or "").rstrip("/") or "https://docsoncalls.com"

    amount_cents = int(round(float(tx.amount) * 100))
    platform_fee_cents = int(round(float(tx.platform_fee or 0) * 100))
    line_items = [{
        "price_data": {
            "currency": "usd",
            "product_data": {
                "name": f"Consultation with Dr. {tx.provider.full_name}",
            },
            "unit_amount": amount_cents,
        },
        "quantity": 1,
    }]
    metadata = {
        "tx_id": str(tx.id),
        "type": "doctor_billing",
    }
    session_kwargs = {
        "mode": "payment",
        "success_url": f"{frontend}/?bill=success&tx_id={tx.id}",
        "cancel_url": f"{frontend}/?bill=cancel&tx_id={tx.id}",
        "customer_email": (patient.email or "").strip() or None,
        "line_items": line_items,
        "metadata": metadata,
    }
    dest = (tx.provider.stripe_connect_account_id or "").strip()
    if dest and platform_fee_cents >= 0:
        session_kwargs["payment_intent_data"] = {
            "application_fee_amount": platform_fee_cents,
            "transfer_data": {"destination": dest},
        }

    session = stripe.checkout.Session.create(**session_kwargs)

    return _success({"url": session.url, "session_id": session.id}, message="Checkout created")


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def provider_request_payout(request):
    """Provider requests a payout of their accumulated balance."""
    provider = Provider.objects.filter(user=request.user).first()
    if not provider:
        return _error({"provider": ["No provider profile"]}, status.HTTP_404_NOT_FOUND)

    amount_str = request.data.get("amount", "0")
    try:
        amount = float(amount_str)
    except (TypeError, ValueError):
        return _error({"amount": ["invalid number"]})

    if amount <= 0:
        return _error({"amount": ["must be > 0"]})

    completed_txs = ProviderTransaction.objects.filter(
        provider=provider, status=ProviderTransaction.Status.COMPLETED
    )
    available = sum((t.provider_payout or 0) for t in completed_txs)

    paid_out = sum(
        (p.amount or 0) for p in ProviderPayout.objects.filter(
            provider=provider, status=ProviderPayout.Status.PAID
        )
    )
    pending_payouts = sum(
        (p.amount or 0) for p in ProviderPayout.objects.filter(
            provider=provider, status=ProviderPayout.Status.PENDING
        )
    )
    balance = available - paid_out - pending_payouts

    if amount > balance:
        return _error({"amount": [f"Insufficient balance. Available: ${balance:.2f}"]})

    payout = ProviderPayout.objects.create(
        provider=provider,
        amount=amount,
        status=ProviderPayout.Status.PENDING,
    )

    return _success({
        "payout": ProviderPayoutSerializer(payout).data,
    }, message="Payout requested")


@api_view(["POST"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def doctor_stripe_connect_onboard(request):
    """Create or resume Stripe Connect Express onboarding for the current doctor."""
    import stripe

    if not getattr(settings, "STRIPE_SECRET_KEY", ""):
        return _error(
            {"billing": ["Stripe is not configured on server."]},
            status.HTTP_501_NOT_IMPLEMENTED,
        )

    provider = Provider.objects.filter(user=request.user).first()
    if not provider:
        return _error({"provider": ["No provider profile"]}, status.HTTP_404_NOT_FOUND)

    stripe.api_key = settings.STRIPE_SECRET_KEY
    acct_id = (provider.stripe_connect_account_id or "").strip()
    if not acct_id:
        account = stripe.Account.create(
            type="express",
            country="US",
            email=(provider.email or "").strip() or None,
            capabilities={
                "card_payments": {"requested": True},
                "transfers": {"requested": True},
            },
            metadata={"provider_id": str(provider.id)},
        )
        acct_id = account.id
        provider.stripe_connect_account_id = acct_id
        provider.save(update_fields=["stripe_connect_account_id"])

    link = stripe.AccountLink.create(
        account=acct_id,
        refresh_url=getattr(settings, "STRIPE_CONNECT_REFRESH_URL", ""),
        return_url=getattr(settings, "STRIPE_CONNECT_RETURN_URL", ""),
        type="account_onboarding",
    )
    return _success(
        {"url": link.url, "account_id": acct_id},
        message="Open Stripe Connect onboarding",
    )


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def doctor_stripe_connect_status(request):
    """Refresh Stripe Connect onboarding flags for the current doctor."""
    import stripe

    provider = Provider.objects.filter(user=request.user).first()
    if not provider:
        return _error({"provider": ["No provider profile"]}, status.HTTP_404_NOT_FOUND)

    acct_id = (provider.stripe_connect_account_id or "").strip()
    if not acct_id or not getattr(settings, "STRIPE_SECRET_KEY", ""):
        return _success({
            "stripe_connect_account_id": acct_id,
            "stripe_connect_onboarded": False,
        })

    stripe.api_key = settings.STRIPE_SECRET_KEY
    try:
        account = stripe.Account.retrieve(acct_id)
        charges_enabled = bool(getattr(account, "charges_enabled", False))
        payouts_enabled = bool(getattr(account, "payouts_enabled", False))
        provider.stripe_connect_onboarded = charges_enabled and payouts_enabled
        provider.save(update_fields=["stripe_connect_onboarded"])
    except Exception:
        pass

    return _success({
        "stripe_connect_account_id": provider.stripe_connect_account_id or "",
        "stripe_connect_onboarded": provider.stripe_connect_onboarded,
    })


@api_view(["POST"])
@permission_classes([AllowAny])
def stripe_billing_webhook(request):
    """Stripe webhooks: mark doctor invoices paid after Checkout."""
    import stripe

    payload = request.body
    sig = request.META.get("HTTP_STRIPE_SIGNATURE", "")
    secret = getattr(settings, "STRIPE_WEBHOOK_SECRET", "")
    if not secret:
        return Response({"ok": False, "detail": "webhook not configured"}, status=400)

    try:
        event = stripe.Webhook.construct_event(payload, sig, secret)
    except Exception as exc:
        return Response({"ok": False, "detail": str(exc)}, status=400)

    if event["type"] == "checkout.session.completed":
        session = event["data"]["object"]
        meta = session.get("metadata") or {}
        if meta.get("type") == "doctor_billing" and meta.get("tx_id"):
            try:
                tx_id = int(meta["tx_id"])
            except (TypeError, ValueError):
                tx_id = None
            if tx_id:
                tx = ProviderTransaction.objects.filter(id=tx_id).first()
                if tx and tx.status == ProviderTransaction.Status.PENDING:
                    tx.status = ProviderTransaction.Status.COMPLETED
                    tx.completed_at = timezone.now()
                    tx.stripe_payment_intent_id = (
                        session.get("payment_intent") or ""
                    )[:255]
                    tx.save(
                        update_fields=[
                            "status",
                            "completed_at",
                            "stripe_payment_intent_id",
                        ]
                    )

    elif event["type"] == "account.updated":
        acct = event["data"]["object"]
        acct_id = acct.get("id") or ""
        prov = Provider.objects.filter(stripe_connect_account_id=acct_id).first()
        if prov:
            prov.stripe_connect_onboarded = bool(
                acct.get("charges_enabled") and acct.get("payouts_enabled")
            )
            prov.save(update_fields=["stripe_connect_onboarded"])

    return Response({"ok": True}, status=200)


@api_view(["GET"])
@authentication_classes([TokenAuthentication, SessionAuthentication])
@permission_classes([IsAuthenticated])
def admin_platform_billing_summary(request):
    """Staff: platform commission totals and active subscriptions."""
    if not (request.user.is_staff or request.user.is_superuser):
        return _error({"detail": ["Admin only"]}, status.HTTP_403_FORBIDDEN)

    completed = ProviderTransaction.objects.filter(
        status=ProviderTransaction.Status.COMPLETED
    )
    total_volume = sum(float(t.amount or 0) for t in completed)
    total_platform_fees = sum(float(t.platform_fee or 0) for t in completed)
    total_doctor_payouts = sum(float(t.provider_payout or 0) for t in completed)
    pending_invoices = ProviderTransaction.objects.filter(
        status=ProviderTransaction.Status.PENDING
    ).count()

    active_subs = PatientSubscription.objects.filter(
        status=PatientSubscription.Status.ACTIVE
    ).select_related("plan")
    subs_by_plan = {}
    for sub in active_subs:
        name = sub.plan.plan_name if sub.plan_id else "Unknown"
        subs_by_plan[name] = subs_by_plan.get(name, 0) + 1

    doctors_with_connect = Provider.objects.filter(
        stripe_connect_onboarded=True
    ).count()

    return _success({
        "commission_percent": float(
            getattr(settings, "PLATFORM_COMMISSION_PERCENT", 15)
        ),
        "total_volume": round(total_volume, 2),
        "total_platform_fees": round(total_platform_fees, 2),
        "total_doctor_payouts": round(total_doctor_payouts, 2),
        "pending_invoices": pending_invoices,
        "active_subscriptions": active_subs.count(),
        "subscriptions_by_plan": subs_by_plan,
        "doctors_stripe_connect_ready": doctors_with_connect,
    })
