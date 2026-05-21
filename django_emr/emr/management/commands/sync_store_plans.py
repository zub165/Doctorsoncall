"""Upsert the three App Store / Play subscription plans (run on VPS after deploy)."""

from django.core.management.base import BaseCommand

from emr.models import Plan


STORE_PLANS = (
    {
        "plan_name": "Basic",
        "duration": "Monthly",
        "price": "9.99",
        "number_appointments": "1",
        "ai_bot": "no",
        "revenuecat_product_id": "doc_basic_monthly",
        "revenuecat_entitlement_id": "basic",
    },
    {
        "plan_name": "Gold",
        "duration": "Monthly",
        "price": "29.99",
        "number_appointments": "3",
        "ai_bot": "yes",
        "revenuecat_product_id": "doc_gold_monthly",
        "revenuecat_entitlement_id": "gold",
    },
    {
        "plan_name": "Premium",
        "duration": "Monthly",
        "price": "49.99",
        "number_appointments": "5",
        "ai_bot": "yes",
        "revenuecat_product_id": "doc_premium_monthly",
        "revenuecat_entitlement_id": "premium",
    },
)


class Command(BaseCommand):
    help = "Create or update Basic/Gold/Premium plans with App Store product IDs."

    def handle(self, *args, **options):
        for row in STORE_PLANS:
            pid = row["revenuecat_product_id"]
            matches = list(
                Plan.objects.filter(revenuecat_product_id=pid).order_by("id")
            )
            if len(matches) > 1:
                keep = matches[0]
                for extra in matches[1:]:
                    extra.revenuecat_product_id = ""
                    extra.revenuecat_entitlement_id = ""
                    extra.save(update_fields=["revenuecat_product_id", "revenuecat_entitlement_id"])
                    self.stdout.write(
                        self.style.WARNING(
                            f"Cleared duplicate store id on plan id={extra.id} ({extra.plan_name})"
                        )
                    )
                plan = keep
                created = False
            elif matches:
                plan = matches[0]
                created = False
            else:
                plan = Plan.objects.create(**row)
                created = True

            if not created:
                for key, value in row.items():
                    setattr(plan, key, value)
                plan.save()

            action = "Created" if created else "Updated"
            self.stdout.write(
                self.style.SUCCESS(
                    f"{action} plan id={plan.id} {plan.plan_name} → {pid} "
                    f"({row['number_appointments']} visits/mo)"
                )
            )
