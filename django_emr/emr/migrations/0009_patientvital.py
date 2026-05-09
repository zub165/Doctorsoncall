from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ("emr", "0008_patientsubscription"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="PatientVital",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("height_cm", models.FloatField(blank=True, null=True)),
                ("weight_kg", models.FloatField(blank=True, null=True)),
                ("temperature_c", models.FloatField(blank=True, null=True)),
                ("bp_sys", models.IntegerField(blank=True, null=True)),
                ("bp_dia", models.IntegerField(blank=True, null=True)),
                ("pulse_bpm", models.IntegerField(blank=True, null=True)),
                ("resp_min", models.IntegerField(blank=True, null=True)),
                ("spo2", models.IntegerField(blank=True, null=True)),
                ("glucose_mgdl", models.FloatField(blank=True, null=True)),
                ("notes", models.TextField(blank=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "patient",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="vitals",
                        to="emr.patient",
                    ),
                ),
                (
                    "recorded_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="recorded_vitals",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "patient_vitals",
                "ordering": ["-created_at"],
            },
        ),
    ]

