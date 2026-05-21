"""Send a test message using current EMAIL_* settings (VPS smoke test)."""

from django.conf import settings
from django.core.mail import send_mail
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Send test email via configured SMTP (dedrelay / smtpout)."

    def add_arguments(self, parser):
        parser.add_argument(
            "recipient",
            nargs="?",
            default="",
            help="Recipient address (required)",
        )

    def handle(self, *args, **options):
        to = (options["recipient"] or "").strip()
        if not to:
            raise CommandError("Usage: python manage.py send_test_email you@example.com")

        host = (getattr(settings, "EMAIL_HOST", "") or "").strip()
        if not host:
            raise CommandError(
                "EMAIL_HOST not set in .env — add dedrelay or smtpout settings on the VPS."
            )

        from_addr = getattr(settings, "DEFAULT_FROM_EMAIL", "noreply@docsoncalls.com")
        body = (
            "Docs On Call / django_emr SMTP test.\n\n"
            f"Host: {host}:{getattr(settings, 'EMAIL_PORT', '?')}\n"
            f"From: {from_addr}\n"
            f"Support: {getattr(settings, 'SUPPORT_EMAIL', '')}\n"
        )
        n = send_mail(
            "Docs On Call SMTP test",
            body,
            from_addr,
            [to],
            fail_silently=False,
        )
        if n < 1:
            raise CommandError("send_mail returned 0 — message not sent.")
        self.stdout.write(
            self.style.SUCCESS(f"Sent test email to {to} from {from_addr} via {host}")
        )
