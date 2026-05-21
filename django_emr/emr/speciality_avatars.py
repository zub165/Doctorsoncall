"""Download speciality avatar PNGs into MEDIA_ROOT and persist stable URLs on each row."""

from __future__ import annotations

import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from django.conf import settings

from .models import Speciality

_TWEMOJI = "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/{code}.png"

# Keyword → Twemoji codepoint (hex, no 0x prefix).
_KEYWORD_ICONS: tuple[tuple[str, str], ...] = (
    ("allergy", "1f927"),
    ("immunology", "1f9fc"),
    ("cardio", "2764"),
    ("heart", "2764"),
    ("derma", "1f9fc"),
    ("skin", "1f9fc"),
    ("neuro", "1f9e0"),
    ("brain", "1f9e0"),
    ("pediatr", "1f476"),
    ("child", "1f476"),
    ("ortho", "1f9b5"),
    ("bone", "1f9b4"),
    ("eye", "1f441-fe0f"),
    ("ophthal", "1f441-fe0f"),
    ("radio", "1f4f7"),
    ("imaging", "1f4f7"),
    ("emergency", "1f691"),
    ("trauma", "1f691"),
    ("psych", "1f9d8"),
    ("mental", "1f9d8"),
    ("dent", "1f9b7"),
    ("nutrition", "1f96a"),
    ("diet", "1f96a"),
    ("surgery", "1fa7a"),
    ("surgical", "1fa7a"),
    ("family", "1f46a"),
    ("internal", "1f3e5"),
    ("medicine", "1f3e5"),
    ("anesth", "1f48a"),
    ("pathology", "1f52c"),
    ("lab", "1f52c"),
    ("urology", "1f4a7"),
    ("oncology", "1f380"),
    ("cancer", "1f380"),
    ("gastro", "1f957"),
    ("pulmon", "1fac1"),
    ("lung", "1fac1"),
    ("obstet", "1f476"),
    ("gynec", "1f9ba"),
    ("women", "1f9ba"),
    ("geriatr", "1f9d3"),
    ("elder", "1f9d3"),
    ("sport", "26bd"),
    ("pain", "1f915"),
    ("sleep", "1f634"),
    ("endocrin", "1f9ec"),
    ("diabetes", "1f9ec"),
    ("infect", "1f9a0"),
    ("virus", "1f9a0"),
    ("occupational", "1f477"),
    ("plastic", "1f485"),
    ("vascular", "1fa78"),
    ("nephro", "1f9fd"),
    ("kidney", "1f9fd"),
    ("hepat", "1f9a0"),
    ("liver", "1f9a0"),
    ("ent", "1f442"),
    ("otolaryng", "1f442"),
    ("chiropractic", "1f9b5"),
    ("podiatr", "1f9b6"),
    ("foot", "1f9b6"),
    ("hematology", "1fa78"),
    ("blood", "1fa78"),
    ("rheumat", "1f9b4"),
    ("critical", "1f691"),
    ("icu", "1f691"),
    ("neonatal", "1f476"),
    ("rehab", "1f9d8"),
    ("physical therapy", "1f9d8"),
    ("telemedicine", "1f4f1"),
    ("genetic", "1f9ec"),
)

_FALLBACK_TWEMOJI = (
    "1fa7a",
    "1f3e5",
    "1f48a",
    "2764",
    "1f9e0",
    "1f52c",
)


def _slugify(name: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9]+", "-", name.strip().lower()).strip("-")
    return (s[:60] or "speciality")


def source_url_for_name(name: str) -> str:
    """Pick a remote PNG URL to download (Twemoji or ui-avatars)."""
    n = name.lower()
    for keyword, code in _KEYWORD_ICONS:
        if keyword in n:
            return _TWEMOJI.format(code=code)
    idx = abs(hash(name)) % len(_FALLBACK_TWEMOJI)
    return _TWEMOJI.format(code=_FALLBACK_TWEMOJI[idx])


def generated_avatar_url(name: str) -> str:
    label = name.strip() or "MD"
    q = urllib.parse.urlencode(
        {
            "name": label,
            "size": "256",
            "background": "D32F2F",
            "color": "fff",
            "bold": "true",
        }
    )
    return f"https://ui-avatars.com/api/?{q}"


def public_media_url(relative_path: str) -> str:
    rel = relative_path.lstrip("/")
    return f"{settings.PUBLIC_API_BASE_URL}{settings.MEDIA_URL}{rel}"


def _download(url: str, dest: Path, timeout: int = 30) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "DocOnCall-EMR/1.0 (speciality-avatar-seed)"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
    if len(data) < 64:
        raise ValueError(f"Download too small from {url}")
    dest.write_bytes(data)


def needs_refresh(speciality: Speciality, *, force: bool) -> bool:
    if force:
        return True
    img = (speciality.speciality_image or "").strip()
    if not img:
        return True
    if "ui-avatars.com" in img:
        return True
    if "/media/specialities/" in img:
        return False
    return not img.startswith("http")


def seed_speciality_avatars(*, force: bool = False, use_generated_fallback: bool = True) -> dict:
    """
    Download PNG for each speciality into media/specialities/<id>.png
    and set speciality_image to the public media URL.
    """
    media_dir = Path(settings.MEDIA_ROOT) / "specialities"
    media_dir.mkdir(parents=True, exist_ok=True)

    updated = 0
    skipped = 0
    errors: list[dict] = []

    for spec in Speciality.objects.all().order_by("id"):
        if not needs_refresh(spec, force=force):
            skipped += 1
            continue
        slug = _slugify(spec.speciality_name)
        filename = f"{spec.id}-{slug}.png"
        dest = media_dir / filename
        rel = f"specialities/{filename}"

        urls_to_try = [source_url_for_name(spec.speciality_name)]
        if use_generated_fallback:
            urls_to_try.append(generated_avatar_url(spec.speciality_name))

        saved = False
        last_err = ""
        for url in urls_to_try:
            try:
                _download(url, dest)
                saved = True
                break
            except (urllib.error.URLError, OSError, ValueError) as exc:
                last_err = str(exc)

        if not saved:
            errors.append(
                {
                    "id": spec.id,
                    "name": spec.speciality_name,
                    "error": last_err or "download failed",
                }
            )
            continue

        spec.speciality_image = public_media_url(rel)
        spec.save(update_fields=["speciality_image"])
        updated += 1

    return {
        "updated": updated,
        "skipped": skipped,
        "errors": errors,
        "total": Speciality.objects.count(),
        "media_base": public_media_url("specialities/"),
    }
