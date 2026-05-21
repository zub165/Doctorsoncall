from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("emr", "0012_revenuecat_doctor_billing"),
    ]

    operations = [
        migrations.AddField(
            model_name="patientshare",
            name="share_kind",
            field=models.CharField(
                choices=[("general", "general"), ("triage", "triage")],
                default="general",
                max_length=16,
            ),
        ),
        migrations.AddField(
            model_name="patientshare",
            name="triage_payload",
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name="patientshare",
            name="appointment",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="patient_shares",
                to="emr.appointment",
            ),
        ),
        migrations.AddField(
            model_name="patientshare",
            name="vital",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="shares",
                to="emr.patientvital",
            ),
        ),
        migrations.CreateModel(
            name="VisitNote",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("subjective", models.TextField(blank=True)),
                ("objective", models.TextField(blank=True)),
                ("assessment", models.TextField(blank=True)),
                ("plan", models.TextField(blank=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "appointment",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="visit_notes",
                        to="emr.appointment",
                    ),
                ),
                (
                    "medical_record",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="visit_notes",
                        to="emr.medicalrecord",
                    ),
                ),
                (
                    "patient",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="visit_notes",
                        to="emr.patient",
                    ),
                ),
                (
                    "provider",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="visit_notes",
                        to="emr.provider",
                    ),
                ),
            ],
            options={
                "db_table": "visit_notes",
                "ordering": ["-id"],
            },
        ),
    ]
