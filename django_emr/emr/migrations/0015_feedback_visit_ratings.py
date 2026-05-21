from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("emr", "0014_plan_revenuecat_stripe_connect"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name="feedback",
            name="reviewer_role",
            field=models.CharField(
                blank=True,
                choices=[
                    ("patient", "patient"),
                    ("provider", "provider"),
                    ("admin", "admin"),
                    ("guest", "guest"),
                ],
                default="guest",
                max_length=16,
            ),
        ),
        migrations.AddField(
            model_name="feedback",
            name="subject_type",
            field=models.CharField(
                blank=True,
                choices=[
                    ("provider", "provider"),
                    ("patient", "patient"),
                    ("general", "general"),
                ],
                default="general",
                max_length=16,
            ),
        ),
        migrations.AddField(
            model_name="feedback",
            name="provider",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="feedback_received",
                to="emr.provider",
            ),
        ),
        migrations.AddField(
            model_name="feedback",
            name="patient",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="feedback_received",
                to="emr.patient",
            ),
        ),
        migrations.AddField(
            model_name="feedback",
            name="appointment",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="feedback_items",
                to="emr.appointment",
            ),
        ),
        migrations.AddField(
            model_name="feedback",
            name="overall_rating",
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="feedback",
            name="rating_communication",
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="feedback",
            name="rating_care_quality",
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="feedback",
            name="rating_ease",
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="feedback",
            name="rating_recommend",
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="feedback",
            name="responses",
            field=models.JSONField(blank=True, default=dict),
        ),
    ]
