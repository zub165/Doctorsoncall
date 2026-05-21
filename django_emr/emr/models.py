from django.conf import settings
from django.db import models
from django.utils import timezone


class Country(models.Model):
    country_code = models.CharField(max_length=32)
    country_name = models.CharField(max_length=255)
    image = models.CharField(max_length=512, blank=True)

    class Meta:
        db_table = "countries"
        verbose_name_plural = "countries"


class Speciality(models.Model):
    speciality_name = models.CharField(max_length=255)
    speciality_image = models.CharField(max_length=512, blank=True)
    country = models.ForeignKey(
        Country,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="specialities",
    )

    class Meta:
        db_table = "specialities"


class Plan(models.Model):
    plan_name = models.CharField(max_length=255)
    duration = models.CharField(max_length=64)
    price = models.CharField(max_length=64)
    discount = models.CharField(max_length=64, blank=True, null=True)
    discount_date = models.DateField(blank=True, null=True)
    number_appointments = models.CharField(max_length=64)
    ai_bot = models.CharField(max_length=64)
    revenuecat_product_id = models.CharField(
        max_length=255,
        blank=True,
        help_text="App Store / Play product id (e.g. doc_gold_monthly)",
    )
    revenuecat_entitlement_id = models.CharField(
        max_length=255,
        blank=True,
        help_text="RevenueCat entitlement id (e.g. plus)",
    )

    class Meta:
        db_table = "plan"


class Role(models.Model):
    """
    Lightweight admin-managed roles list (used by Admin Hub UI).
    This is separate from Django auth Groups/Permissions.
    """

    name = models.CharField(max_length=128)
    status = models.CharField(max_length=32, default="active")
    description = models.CharField(max_length=512, blank=True)

    class Meta:
        db_table = "roles"
        ordering = ["id"]


class Patient(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="patient_profiles"
    )
    image = models.CharField(max_length=512, blank=True)
    name = models.CharField(max_length=255)
    date_of_birth = models.CharField(max_length=64)
    email = models.EmailField()
    city = models.CharField(max_length=255, blank=True)
    country = models.CharField(max_length=255, blank=True)
    birth_place = models.CharField(max_length=255, blank=True)
    identity_no = models.CharField(max_length=255, blank=True)
    profile_status = models.CharField(max_length=64, blank=True)
    whatsapp_number = models.CharField(max_length=32, blank=True)

    class Meta:
        db_table = "patients"


class Provider(models.Model):
    class Gender(models.TextChoices):
        MALE = "male", "male"
        FEMALE = "female", "female"
        OTHER = "other", "other"

    class ConsultationType(models.TextChoices):
        VIDEO = "video", "video"
        AUDIO = "audio", "audio"
        CHAT = "chat", "chat"
        IN_PERSON = "in-person", "in-person"

    class Status(models.TextChoices):
        ACTIVE = "active", "active"
        INACTIVE = "inactive", "inactive"
        PENDING = "pending", "pending"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="provider_profiles"
    )
    full_name = models.CharField(max_length=255)
    date_of_birth = models.DateField(null=True, blank=True)
    gender = models.CharField(
        max_length=16, choices=Gender.choices, blank=True, null=True
    )
    email = models.EmailField(unique=True)
    phone_number = models.CharField(max_length=64, unique=True)
    profile_picture = models.CharField(max_length=512, blank=True)
    address = models.CharField(max_length=512, blank=True)
    nationality = models.CharField(max_length=128, blank=True)
    speciality = models.ForeignKey(Speciality, on_delete=models.PROTECT)
    sub_specialization = models.CharField(max_length=255, blank=True)
    experience_years = models.IntegerField(null=True, blank=True)
    qualifications = models.CharField(max_length=512, blank=True)
    license_number = models.CharField(max_length=128, blank=True, null=True, unique=True)
    license_authority = models.CharField(max_length=255, blank=True)
    license_expiry = models.DateField(null=True, blank=True)
    bio = models.TextField(blank=True)
    consultation_days = models.CharField(max_length=255, blank=True)
    consultation_hours = models.JSONField(null=True, blank=True)
    time_zone = models.CharField(max_length=64, blank=True)
    max_consultations_per_day = models.IntegerField(null=True, blank=True)
    consultation_fee = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True
    )
    consultation_type = models.CharField(
        max_length=32,
        choices=ConsultationType.choices,
        default=ConsultationType.VIDEO,
    )
    bank_name = models.CharField(max_length=255, blank=True)
    account_number = models.CharField(max_length=128, blank=True)
    consultation_duration = models.IntegerField(default=30)
    status = models.CharField(
        max_length=32, choices=Status.choices, default=Status.PENDING
    )
    is_verified = models.BooleanField(default=False)
    registered_date = models.DateTimeField(null=True, blank=True)
    last_login = models.DateTimeField(null=True, blank=True)
    whatsapp_number = models.CharField(max_length=32, blank=True)
    stripe_connect_account_id = models.CharField(max_length=255, blank=True)
    stripe_connect_onboarded = models.BooleanField(default=False)

    class Meta:
        db_table = "providers"


class Appointment(models.Model):
    patient = models.ForeignKey(Patient, on_delete=models.CASCADE)
    provider = models.ForeignKey(Provider, on_delete=models.CASCADE)
    date = models.DateField()
    time = models.TimeField()
    approved = models.CharField(max_length=64, blank=True, null=True)
    medium = models.CharField(max_length=64, blank=True, null=True)
    review = models.CharField(max_length=512, blank=True, null=True)
    medical_record = models.ForeignKey(
        "MedicalRecord",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="appointments",
    )

    class Meta:
        db_table = "appointment"


class MedicalRecord(models.Model):
    """
    Minimal server-side medical record storage for imports/merges.
    (Flutter also keeps a rich local offline store; this is a light backend inbox/merge store.)
    """

    patient = models.ForeignKey(Patient, on_delete=models.CASCADE, related_name="medical_records")
    source_url = models.CharField(max_length=1024, blank=True)
    source_system = models.CharField(max_length=128, blank=True)
    title = models.CharField(max_length=255, blank=True)
    raw_payload = models.TextField(blank=True)  # JSON/text
    ai_summary = models.TextField(blank=True)
    merged_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="merged_records",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "medical_records"
        ordering = ["-id"]


class ImportInbox(models.Model):
    """
    Inbox of external API imports awaiting admin merge.
    """

    class Status(models.TextChoices):
        PENDING = "pending", "pending"
        MERGED = "merged", "merged"
        REJECTED = "rejected", "rejected"

    submitted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="import_submissions",
    )
    patient_email = models.EmailField(blank=True)
    patient_hint = models.CharField(max_length=255, blank=True)
    source_url = models.CharField(max_length=1024)
    raw_payload = models.TextField(blank=True)
    ai_summary = models.TextField(blank=True)
    status = models.CharField(max_length=32, choices=Status.choices, default=Status.PENDING)
    merged_patient = models.ForeignKey(
        Patient,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="merged_imports",
    )
    merged_record = models.ForeignKey(
        MedicalRecord,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="source_imports",
    )
    merged_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="import_merges",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "import_inbox"
        ordering = ["-id"]


class Feedback(models.Model):
    class ReviewerRole(models.TextChoices):
        PATIENT = "patient", "patient"
        PROVIDER = "provider", "provider"
        ADMIN = "admin", "admin"
        GUEST = "guest", "guest"

    class SubjectType(models.TextChoices):
        PROVIDER = "provider", "provider"
        PATIENT = "patient", "patient"
        GENERAL = "general", "general"

    # Allow anonymous feedback (mobile apps may submit before login).
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="feedback_items",
    )
    reviewer_role = models.CharField(
        max_length=16,
        choices=ReviewerRole.choices,
        default=ReviewerRole.GUEST,
        blank=True,
    )
    subject_type = models.CharField(
        max_length=16,
        choices=SubjectType.choices,
        default=SubjectType.GENERAL,
        blank=True,
    )
    provider = models.ForeignKey(
        "Provider",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="feedback_received",
    )
    patient = models.ForeignKey(
        "Patient",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="feedback_received",
    )
    appointment = models.ForeignKey(
        "Appointment",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="feedback_items",
    )
    overall_rating = models.PositiveSmallIntegerField(null=True, blank=True)
    rating_communication = models.PositiveSmallIntegerField(null=True, blank=True)
    rating_care_quality = models.PositiveSmallIntegerField(null=True, blank=True)
    rating_ease = models.PositiveSmallIntegerField(null=True, blank=True)
    rating_recommend = models.PositiveSmallIntegerField(null=True, blank=True)
    responses = models.JSONField(default=dict, blank=True)
    feedback = models.TextField()
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "feedback"
        ordering = ["-id"]


class NutritionEntry(models.Model):
    """Nutrition tracking (extends EMR beyond Laravel schema)."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="nutrition_entries"
    )
    description = models.CharField(max_length=512)
    calories = models.IntegerField(null=True, blank=True)
    logged_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "nutrition_entries"
        ordering = ["-logged_at"]


class Invoices(models.Model):
    patient = models.ForeignKey(Patient, on_delete=models.CASCADE, related_name="invoices")
    name = models.CharField(max_length=255)
    email = models.CharField(max_length=255)
    amount = models.CharField(max_length=64)
    invoice_date = models.DateField()

    class Meta:
        db_table = "invoices"


class Timezone(models.Model):
    timezone = models.CharField(max_length=255)

    class Meta:
        db_table = "timezone"


class General(models.Model):
    """Generic settings model."""

    key = models.CharField(max_length=128, unique=True)
    value = models.TextField(blank=True)

    class Meta:
        db_table = "general"


class Hospital(models.Model):
    """
    Hospital / facility listing for the mobile app.

    Keep field names aligned with Flutter `Hospital.fromJson` aliases:
    - facility_type, wait_time_minutes, ai_rating, is_open, rating, photo_url
    """

    name = models.CharField(max_length=255)
    address = models.CharField(max_length=512, blank=True)
    facility_type = models.CharField(max_length=64, default="Hospital")
    phone_number = models.CharField(max_length=64, blank=True)

    latitude = models.FloatField(default=0)
    longitude = models.FloatField(default=0)

    rating = models.FloatField(default=0)
    ai_rating = models.FloatField(null=True, blank=True)
    wait_time_minutes = models.IntegerField(default=0)
    is_open = models.BooleanField(default=True)

    photo_url = models.CharField(max_length=512, blank=True)

    class Meta:
        db_table = "hospitals"
        ordering = ["name"]


class PatientDocument(models.Model):
    """
    Patient-uploaded document (PDF/image/text) intended for doctor review.

    Flow:
    1) patient uploads file
    2) backend extracts text (PDF/text) and/or OCRs (images)
    3) backend generates an AI summary report for the doctor
    """

    class Status(models.TextChoices):
        UPLOADED = "uploaded", "uploaded"
        TEXT_EXTRACTED = "text_extracted", "text_extracted"
        OCR_DONE = "ocr_done", "ocr_done"
        SUMMARIZED = "summarized", "summarized"
        ERROR = "error", "error"

    patient = models.ForeignKey(
        Patient, on_delete=models.CASCADE, related_name="documents"
    )
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="uploaded_documents",
    )
    file = models.FileField(upload_to="documents/%Y/%m/%d/")
    original_name = models.CharField(max_length=255, blank=True)
    content_type = models.CharField(max_length=128, blank=True)
    size_bytes = models.BigIntegerField(default=0)

    extracted_text = models.TextField(blank=True)
    ai_summary = models.TextField(blank=True)

    status = models.CharField(
        max_length=32, choices=Status.choices, default=Status.UPLOADED
    )
    error_message = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    processed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "patient_documents"
        ordering = ["-id"]


class PatientVital(models.Model):
    """
    Basic vitals capture (manual or device-fed).
    Intended for patient self-tracking and clinician review.
    """

    patient = models.ForeignKey(Patient, on_delete=models.CASCADE, related_name="vitals")
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="recorded_vitals",
    )

    height_cm = models.FloatField(null=True, blank=True)
    weight_kg = models.FloatField(null=True, blank=True)
    temperature_c = models.FloatField(null=True, blank=True)
    bp_sys = models.IntegerField(null=True, blank=True)
    bp_dia = models.IntegerField(null=True, blank=True)
    pulse_bpm = models.IntegerField(null=True, blank=True)
    resp_min = models.IntegerField(null=True, blank=True)
    spo2 = models.IntegerField(null=True, blank=True)
    glucose_mgdl = models.FloatField(null=True, blank=True)
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "patient_vitals"
        ordering = ["-created_at"]


class PatientShare(models.Model):
    """
    Consent-based share from patient → provider/doctor.

    HIPAA note: By default, keep sensitive PII on device; only store what patient
    explicitly submits in `patient_note` / attachments. AI outputs are advisory.
    """

    class Status(models.TextChoices):
        SENT = "sent", "sent"
        VIEWED = "viewed", "viewed"
        DELETED = "deleted", "deleted"

    class ShareKind(models.TextChoices):
        GENERAL = "general", "general"
        TRIAGE = "triage", "triage"

    patient = models.ForeignKey(Patient, on_delete=models.CASCADE, related_name="shares")
    provider = models.ForeignKey(Provider, on_delete=models.CASCADE, related_name="shares_inbox")
    patient_note = models.TextField(blank=True)
    ai_summary = models.TextField(blank=True)
    include_patient_email = models.BooleanField(default=False)
    share_kind = models.CharField(
        max_length=16,
        choices=ShareKind.choices,
        default=ShareKind.GENERAL,
    )
    triage_payload = models.TextField(blank=True)
    vital = models.ForeignKey(
        PatientVital,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="shares",
    )
    appointment = models.ForeignKey(
        Appointment,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="patient_shares",
    )
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.SENT)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "patient_shares"
        ordering = ["-id"]


class VisitNote(models.Model):
    """
    Provider SOAP note delivered to the patient (server copy).
    Optionally linked to an appointment and/or medical record for the visit thread.
    """

    patient = models.ForeignKey(Patient, on_delete=models.CASCADE, related_name="visit_notes")
    provider = models.ForeignKey(Provider, on_delete=models.CASCADE, related_name="visit_notes")
    appointment = models.ForeignKey(
        Appointment,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="visit_notes",
    )
    medical_record = models.ForeignKey(
        MedicalRecord,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="visit_notes",
    )
    subjective = models.TextField(blank=True)
    objective = models.TextField(blank=True)
    assessment = models.TextField(blank=True)
    plan = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "visit_notes"
        ordering = ["-id"]


class PatientSubscription(models.Model):
    """
    RevenueCat-backed plan subscription for a patient.
    Supports Apple IAP (App Store) and Google Play via RevenueCat.
    """

    class Status(models.TextChoices):
        PENDING = "pending", "pending"
        ACTIVE = "active", "active"
        CANCELED = "canceled", "canceled"
        FAILED = "failed", "failed"

    patient = models.ForeignKey(Patient, on_delete=models.CASCADE, related_name="subscriptions")
    plan = models.ForeignKey(Plan, on_delete=models.PROTECT, related_name="subscriptions")
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)
    revenuecat_product_id = models.CharField(max_length=255, blank=True)
    revenuecat_entitlement_id = models.CharField(max_length=255, blank=True)
    platform = models.CharField(max_length=16, default="apple", help_text="apple or android")
    original_transaction_id = models.CharField(max_length=255, blank=True)
    store_country = models.CharField(max_length=8, blank=True)
    will_renew = models.BooleanField(default=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "patient_subscriptions"
        ordering = ["-id"]


class ProviderTransaction(models.Model):
    """
    Tracks payments from patients to doctors for medical services.
    Platform takes a commission percentage.
    """

    class Status(models.TextChoices):
        PENDING = "pending", "pending"
        COMPLETED = "completed", "completed"
        REFUNDED = "refunded", "refunded"
        FAILED = "failed", "failed"

    appointment = models.ForeignKey(
        Appointment, on_delete=models.SET_NULL, null=True, blank=True, related_name="transactions"
    )
    patient = models.ForeignKey(Patient, on_delete=models.CASCADE, related_name="transactions")
    provider = models.ForeignKey(Provider, on_delete=models.CASCADE, related_name="transactions")
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    platform_commission_percent = models.DecimalField(max_digits=5, decimal_places=2, default=15.00)
    platform_fee = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    provider_payout = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)
    stripe_payment_intent_id = models.CharField(max_length=255, blank=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "provider_transactions"
        ordering = ["-id"]


class ProviderPayout(models.Model):
    """
    Tracks when a doctor withdraws their accumulated earnings.
    """

    class Status(models.TextChoices):
        PENDING = "pending", "pending"
        PAID = "paid", "paid"
        FAILED = "failed", "failed"

    provider = models.ForeignKey(Provider, on_delete=models.CASCADE, related_name="payouts")
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)
    stripe_transfer_id = models.CharField(max_length=255, blank=True)
    notes = models.TextField(blank=True)
    requested_at = models.DateTimeField(auto_now_add=True)
    paid_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "provider_payouts"
        ordering = ["-id"]
