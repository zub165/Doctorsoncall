from django.core.management.base import BaseCommand

from emr.speciality_avatars import seed_speciality_avatars


class Command(BaseCommand):
    help = "Download PNG avatars for all specialities into MEDIA_ROOT and save stable URLs."

    def add_arguments(self, parser):
        parser.add_argument(
            "--force",
            action="store_true",
            help="Re-download even when a hosted /media/ URL already exists.",
        )

    def handle(self, *args, **options):
        result = seed_speciality_avatars(force=options["force"])
        self.stdout.write(self.style.SUCCESS(str(result)))
