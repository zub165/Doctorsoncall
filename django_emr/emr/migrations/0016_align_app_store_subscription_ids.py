"""Align Plan rows with App Store Connect product IDs (May 2026)."""

from django.db import migrations


def align_plan_store_ids(apps, schema_editor):
    Plan = apps.get_model("emr", "Plan")
    updates = [
        ("doc_plus_monthly", "doc_gold_monthly", "gold", "Gold"),
        ("doc_enterprise_monthly", "doc_premium_monthly", "premium", "Premium"),
    ]
    for old_pid, new_pid, ent, name in updates:
        Plan.objects.filter(revenuecat_product_id=old_pid).update(
            revenuecat_product_id=new_pid,
            revenuecat_entitlement_id=ent,
            plan_name=name,
        )
    # Middle tier may still be named "Plus" with wrong product id
    Plan.objects.filter(plan_name__iexact="Plus").update(
        plan_name="Gold",
        revenuecat_product_id="doc_gold_monthly",
        revenuecat_entitlement_id="gold",
    )


def noop(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("emr", "0015_feedback_visit_ratings"),
    ]

    operations = [
        migrations.RunPython(align_plan_store_ids, noop),
    ]
