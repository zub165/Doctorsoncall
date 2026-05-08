from django.conf import settings
from django.db import models


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

    class Meta:
        db_table = "plan"


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
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    feedback = models.CharField(max_length=255)

    class Meta:
        db_table = "feedback"


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
