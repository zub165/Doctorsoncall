from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("emr", "0009_patientvital"),
    ]

    operations = [
        migrations.AddField(
            model_name="appointment",
            name="medical_record",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="appointments",
                to="emr.medicalrecord",
            ),
        ),
    ]
