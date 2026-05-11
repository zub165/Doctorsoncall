from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("emr", "0010_appointment_medical_record"),
    ]

    operations = [
        migrations.AddField(
            model_name="patient",
            name="whatsapp_number",
            field=models.CharField(blank=True, max_length=32),
        ),
        migrations.AddField(
            model_name="provider",
            name="whatsapp_number",
            field=models.CharField(blank=True, max_length=32),
        ),
    ]
