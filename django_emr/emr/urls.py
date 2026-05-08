from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register(r"countries", views.CountryViewSet, basename="country")
router.register(r"specialities", views.SpecialityViewSet, basename="speciality")
router.register(r"plans", views.PlanViewSet, basename="plan")
router.register(r"roles", views.RoleViewSet, basename="role")
router.register(r"providers", views.ProviderViewSet, basename="provider")
router.register(r"patients", views.PatientViewSet, basename="patient")
router.register(r"nutrition", views.NutritionEntryViewSet, basename="nutrition")

urlpatterns = [
    path("health/", views.health),
    path("doctor-on-call/me/", views.doctor_on_call_me),
    path("auth/login/", views.auth_login),
    path("auth/register/", views.auth_register),
    path("auth/register-admin/", views.auth_register_admin),
    path("auth/logout/", views.auth_logout),
    path("auth/password-policy/", views.auth_password_policy),
    path("user-data/", views.user_data),
    path("feedback/submit/", views.feedback_submit),
    path("hospitals/", views.hospitals_list),
    path("hospitals/search/", views.hospitals_search),
    path("hospitals/seed-demo/", views.hospitals_seed_demo),
    path("hospitals/<str:hospital_id>/", views.hospital_detail),
    path(
        "hospitals/<str:hospital_id>/ai-wait-time/",
        views.hospital_ai_wait_time,
    ),
    path("er-wait-times/", views.er_wait_times),
    path("osm/search-hospitals/", views.osm_search),
    path("osm/system-status/", views.osm_status),
    path("v1/courses/", views.courses_v1),
    path("patients-providers/", views.patients_providers),
    path("providers/seed-demo/", views.providers_seed_demo),
    path("providers/apply/", views.provider_apply),
    path("provider-types/", views.provider_types),
    path("reference/seed-all/", views.reference_seed_all),
    path("registrations/pending/", views.registrations_pending),
    path("registrations/approve/", views.registrations_approve),
    path("imports/submit/", views.import_submit),
    path("imports/pending/", views.import_pending),
    path("imports/merge/", views.import_merge),
    path("appointments/mine/", views.appointment_list),
    path("appointments/all/", views.appointment_all),
    path("appointments/", views.appointment_create),
    path("auth/change-password/", views.change_password),
    path("integrations/replicate-token/", views.replicate_token_env),
    path("medical-records/ai-assist/", views.medical_records_ai_assist),
    path("medical-records/<str:record_id>/", views.medical_record_detail),
    path("medical-records/", views.medical_records_list),
    path("vitals/", views.vitals_stub),
    path("invoices/", views.invoices_list),
    path("timezone/", views.timezone_list),
    path("settings/general/", views.general_settings),
    path("settings/general/<str:key>/", views.general_settings),
    path("documents/", views.patient_documents),
    path("documents/<int:doc_id>/", views.patient_document_detail),
    path("patient/me/", views.patient_me_update),
    path("billing/status/", views.billing_status),
    path("billing/checkout/", views.billing_checkout),
    path("billing/webhook/", views.billing_webhook),
    path("shares/mine/", views.shares_mine),
    path("shares/inbox/", views.shares_inbox),
    path("shares/", views.shares_create),
    path("shares/<int:share_id>/", views.shares_delete),
    path("shares/<int:share_id>/email/", views.shares_email_patient),
    path("", include(router.urls)),
]
