from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("emr", "0013_visit_notes_triage_share"),
    ]

    operations = [
        migrations.AddField(
            model_name="plan",
            name="revenuecat_product_id",
            field=models.CharField(
                blank=True,
                help_text="App Store / Play product id (e.g. doc_plus_monthly)",
                max_length=255,
            ),
        ),
        migrations.AddField(
            model_name="plan",
            name="revenuecat_entitlement_id",
            field=models.CharField(
                blank=True,
                help_text="RevenueCat entitlement id (e.g. plus)",
                max_length=255,
            ),
        ),
        migrations.AddField(
            model_name="provider",
            name="stripe_connect_account_id",
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name="provider",
            name="stripe_connect_onboarded",
            field=models.BooleanField(default=False),
        ),
    ]
