"""
Django settings — Doctor On Call / EMR (converted from Laravel).
"""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent


def _load_env_file(path: Path) -> None:
    """Load project `.env` when not already in the process environment (e.g. gunicorn)."""
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = val


_load_env_file(BASE_DIR / ".env")

SECRET_KEY = "django-insecure-change-me-in-production"

DEBUG = True

ALLOWED_HOSTS = ["*"]

# Admin self-registration code.
# For production, override via env var ADMIN_REGISTER_CODE.
ADMIN_REGISTER_CODE = os.environ.get("ADMIN_REGISTER_CODE", "DoctorAdmin2026!")

# Hospital Finder / live ER search (server-side proxy only).
# EMR reads MYWAITIME_UPSTREAM_API_BASE — not MYWAITIME_API_KEY or HOSPITAL_FINDER_API_BASE.
# VPS example: http://127.0.0.1:3015/api/ (nginx → Finder on :3015).
# Flutter app calls https://api.mywaitime.com/api/ directly (no API key in the client).
# Put MYWAITIME_API_* keys in the Hospital Finder service .env, not django_emr/.env.
# Same-VPS production: http://127.0.0.1:3015/api/ (Hospital Finder gunicorn + DB).
# Public fallback only when Finder is on another host.
MYWAITIME_UPSTREAM_API_BASE = os.environ.get(
    "MYWAITIME_UPSTREAM_API_BASE", "http://127.0.0.1:3015/api/"
).strip()

# TomTom Maps / Search / Routing (set in django_emr/.env or process env on VPS).
TOMTOM_API_KEY = os.environ.get("TOMTOM_API_KEY", "").strip()
# Referer sent to TomTom (must match domain whitelist — use hostname, no path required).
TOMTOM_REFERER = os.environ.get(
    "TOMTOM_REFERER", "https://api.docsoncalls.com/"
).strip()

# Local LLM (Ollama) configuration.
# Example:
#   OLLAMA_BASE_URL=http://127.0.0.1:11434
#   OLLAMA_MODEL=llama3.1
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://127.0.0.1:11434").strip()
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5:0.5b-instruct").strip()

# Billing (Stripe) configuration.
# Set these in production env:
# - STRIPE_SECRET_KEY=sk_live_...
# - STRIPE_WEBHOOK_SECRET=whsec_...
# - FRONTEND_BASE_URL=https://docsoncalls.com
STRIPE_SECRET_KEY = os.environ.get("STRIPE_SECRET_KEY", "").strip()
STRIPE_WEBHOOK_SECRET = os.environ.get("STRIPE_WEBHOOK_SECRET", "").strip()
FRONTEND_BASE_URL = os.environ.get("FRONTEND_BASE_URL", "https://docsoncalls.com").strip()
STRIPE_CONNECT_RETURN_URL = os.environ.get(
    "STRIPE_CONNECT_RETURN_URL", f"{FRONTEND_BASE_URL.rstrip('/')}/?stripe_connect=return"
).strip()
STRIPE_CONNECT_REFRESH_URL = os.environ.get(
    "STRIPE_CONNECT_REFRESH_URL", f"{FRONTEND_BASE_URL.rstrip('/')}/?stripe_connect=refresh"
).strip()

# Legacy RevenueCat webhook (optional — app uses direct App Store / Play + verify-store).
REVENUECAT_WEBHOOK_SECRET = os.environ.get("REVENUECAT_WEBHOOK_SECRET", "").strip()

# Direct store verification (no RevenueCat).
# APPLE_SHARED_SECRET = App Store Connect shared secret for auto-renewable subscriptions.
# STORE_VERIFY_STRICT=1 requires Apple receipt verify before activating (recommended prod).
APPLE_SHARED_SECRET = os.environ.get("APPLE_SHARED_SECRET", "").strip()
STORE_VERIFY_STRICT = os.environ.get("STORE_VERIFY_STRICT", "").strip().lower() in (
    "1",
    "true",
    "yes",
)

# Platform commission percentage for doctor-patient transactions.
# e.g. 15 = platform takes 15%, doctor gets 85%.
PLATFORM_COMMISSION_PERCENT = float(os.environ.get("PLATFORM_COMMISSION_PERCENT", "15").strip())

# Email (password reset, share summaries). Loaded from django_emr/.env on VPS.
#
# Practical split for Docs On Call / api.docsoncalls.com:
#   Outbound (system): noreply@docsoncalls.com  — dedrelay from GoDaddy VPS (no MX required)
#   Inbound (support): info@innovatorsgeneration.com — real mailbox on smtpout if needed
#
# Option A — VPS relay (try first):
#   EMAIL_HOST=dedrelay.secureserver.net
#   EMAIL_PORT=25
#   EMAIL_USE_TLS=false
#   DEFAULT_FROM_EMAIL=noreply@docsoncalls.com
#
# Option B — mailbox (if relay fails):
#   EMAIL_HOST=smtpout.secureserver.net
#   EMAIL_PORT=587
#   EMAIL_USE_TLS=true
#   EMAIL_HOST_USER=info@innovatorsgeneration.com
#   EMAIL_HOST_PASSWORD=...
#   DEFAULT_FROM_EMAIL=info@innovatorsgeneration.com
#
# Local dev: omit EMAIL_HOST → console backend. Test: python manage.py sendtestemail you@example.com

SUPPORT_EMAIL = os.environ.get(
    "SUPPORT_EMAIL", "info@innovatorsgeneration.com"
).strip()


def _env_bool(name: str, default: str = "false") -> bool:
    return os.environ.get(name, default).strip().lower() in ("1", "true", "yes")


def _configure_email() -> dict:
    host = os.environ.get("EMAIL_HOST", "").strip()
    explicit_backend = os.environ.get("EMAIL_BACKEND", "").strip()
    from_email = os.environ.get(
        "DEFAULT_FROM_EMAIL", "noreply@docsoncalls.com"
    ).strip()
    server_email = os.environ.get("SERVER_EMAIL", from_email).strip()

    port_env = os.environ.get("EMAIL_PORT", "").strip()
    tls_env = os.environ.get("EMAIL_USE_TLS", "").strip()
    ssl_env = os.environ.get("EMAIL_USE_SSL", "").strip()

    port = int(port_env) if port_env else None
    use_tls = _env_bool("EMAIL_USE_TLS") if tls_env else None
    use_ssl = _env_bool("EMAIL_USE_SSL") if ssl_env else False

    if host:
        lower = host.lower()
        if port is None:
            if "dedrelay" in lower:
                port = 25
            elif "smtpout" in lower:
                port = 587
            else:
                port = 587
        if use_tls is None:
            use_tls = "dedrelay" not in lower
    else:
        port = port or 587
        if use_tls is None:
            use_tls = True

    if explicit_backend:
        backend = explicit_backend
    elif host:
        backend = "django.core.mail.backends.smtp.EmailBackend"
    else:
        backend = "django.core.mail.backends.console.EmailBackend"

    return {
        "EMAIL_BACKEND": backend,
        "EMAIL_HOST": host,
        "EMAIL_PORT": port,
        "EMAIL_HOST_USER": os.environ.get("EMAIL_HOST_USER", "").strip(),
        "EMAIL_HOST_PASSWORD": os.environ.get("EMAIL_HOST_PASSWORD", "").strip(),
        "EMAIL_USE_TLS": use_tls,
        "EMAIL_USE_SSL": use_ssl,
        "DEFAULT_FROM_EMAIL": from_email,
        "SERVER_EMAIL": server_email,
    }


_email_cfg = _configure_email()
EMAIL_BACKEND = _email_cfg["EMAIL_BACKEND"]
EMAIL_HOST = _email_cfg["EMAIL_HOST"]
EMAIL_PORT = _email_cfg["EMAIL_PORT"]
EMAIL_HOST_USER = _email_cfg["EMAIL_HOST_USER"]
EMAIL_HOST_PASSWORD = _email_cfg["EMAIL_HOST_PASSWORD"]
EMAIL_USE_TLS = _email_cfg["EMAIL_USE_TLS"]
EMAIL_USE_SSL = _email_cfg["EMAIL_USE_SSL"]
DEFAULT_FROM_EMAIL = _email_cfg["DEFAULT_FROM_EMAIL"]
SERVER_EMAIL = _email_cfg["SERVER_EMAIL"]

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework.authtoken",
    "corsheaders",
    "accounts",
    "emr",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "emergencytime.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "emergencytime.wsgi.application"

def _parse_database_url(url: str):
    """
    Minimal DATABASE_URL parser.

    Supported:
    - postgres://user:pass@host:5432/dbname
    - postgresql://...
    - mysql://user:pass@host:3306/dbname
    """
    from urllib.parse import urlparse

    u = urlparse(url)
    scheme = (u.scheme or "").lower()
    if scheme in ("postgres", "postgresql"):
        engine = "django.db.backends.postgresql"
    elif scheme in ("mysql",):
        engine = "django.db.backends.mysql"
    else:
        raise ValueError(f"Unsupported DATABASE_URL scheme: {scheme}")

    name = (u.path or "").lstrip("/") or ""
    return {
        "ENGINE": engine,
        "NAME": name,
        "USER": u.username or "",
        "PASSWORD": u.password or "",
        "HOST": u.hostname or "",
        "PORT": str(u.port or ""),
    }


# Hybrid DB mode:
# - Local dev default: SQLite (db.sqlite3)
# - Production (GoDaddy): set DATABASE_URL (recommended, PostgreSQL)
# - Legacy: DJANGO_DATABASE=mysql with MYSQL_* vars (kept for compatibility)
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
if DATABASE_URL:
    cfg = _parse_database_url(DATABASE_URL)
    if cfg["ENGINE"] == "django.db.backends.mysql":
        cfg["OPTIONS"] = {"charset": "utf8mb4"}
    DATABASES = {"default": cfg}
elif os.environ.get("DJANGO_DATABASE", "").lower() == "mysql":
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.mysql",
            "NAME": os.environ.get("MYSQL_DATABASE", "emergencytime"),
            "HOST": os.environ.get("MYSQL_HOST", "127.0.0.1"),
            "PORT": os.environ.get("MYSQL_PORT", "3306"),
            "USER": os.environ.get("MYSQL_USER", "root"),
            "PASSWORD": os.environ.get("MYSQL_PASSWORD", ""),
            "OPTIONS": {"charset": "utf8mb4"},
        }
    }
else:
    DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR / "db.sqlite3"}}

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
# Required for `collectstatic` on the server (served by nginx or a CDN in production).
STATIC_ROOT = BASE_DIR / "staticfiles"

# User-uploaded files (documents, images, etc.)
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"

# Public base for stored media URLs returned to mobile clients (no trailing slash).
PUBLIC_API_BASE_URL = os.environ.get(
    "PUBLIC_API_BASE_URL", "https://api.docsoncalls.com"
).strip().rstrip("/")
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

AUTH_USER_MODEL = "accounts.User"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework.authentication.TokenAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticatedOrReadOnly",
    ],
}

CORS_ALLOW_ALL_ORIGINS = True
