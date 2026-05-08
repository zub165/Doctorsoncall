"""
Django settings — Doctor On Call / EMR (converted from Laravel).
"""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = "django-insecure-change-me-in-production"

DEBUG = True

ALLOWED_HOSTS = ["*"]

# Admin self-registration code.
# For production, override via env var ADMIN_REGISTER_CODE.
ADMIN_REGISTER_CODE = os.environ.get("ADMIN_REGISTER_CODE", "DoctorAdmin2026!")

# Optional upstream API base (proxied by nginx to :3015).
# Used to fetch ER wait-time analytics or other legacy endpoints.
MYWAITIME_UPSTREAM_API_BASE = os.environ.get(
    "MYWAITIME_UPSTREAM_API_BASE", "https://api.mywaitime.com/api/"
).strip()

# Local LLM (Ollama) configuration.
# Example:
#   OLLAMA_BASE_URL=http://127.0.0.1:11434
#   OLLAMA_MODEL=llama3.1
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://127.0.0.1:11434").strip()
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3.1").strip()

# Billing (Stripe) configuration.
# Set these in production env:
# - STRIPE_SECRET_KEY=sk_live_...
# - STRIPE_WEBHOOK_SECRET=whsec_...
# - FRONTEND_BASE_URL=https://docsoncalls.com
STRIPE_SECRET_KEY = os.environ.get("STRIPE_SECRET_KEY", "").strip()
STRIPE_WEBHOOK_SECRET = os.environ.get("STRIPE_WEBHOOK_SECRET", "").strip()
FRONTEND_BASE_URL = os.environ.get("FRONTEND_BASE_URL", "https://docsoncalls.com").strip()

# Email (password reset, notifications). Default to console for dev.
EMAIL_BACKEND = os.environ.get(
    "EMAIL_BACKEND", "django.core.mail.backends.console.EmailBackend"
).strip()
EMAIL_HOST = os.environ.get("EMAIL_HOST", "").strip()
EMAIL_PORT = int(os.environ.get("EMAIL_PORT", "587").strip() or 587)
EMAIL_HOST_USER = os.environ.get("EMAIL_HOST_USER", "").strip()
EMAIL_HOST_PASSWORD = os.environ.get("EMAIL_HOST_PASSWORD", "").strip()
EMAIL_USE_TLS = os.environ.get("EMAIL_USE_TLS", "true").lower().strip() in ("1", "true", "yes")
DEFAULT_FROM_EMAIL = os.environ.get("DEFAULT_FROM_EMAIL", "no-reply@docsoncalls.com").strip()

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
