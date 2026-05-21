from django.contrib.auth import authenticate
from rest_framework import serializers

from accounts.models import User
from .models import (
    Appointment,
    Country,
    Feedback,
    General,
    Hospital,
    ImportInbox,
    Invoices,
    MedicalRecord,
    NutritionEntry,
    Patient,
    Plan,
    Provider,
    ProviderPayout,
    ProviderTransaction,
    Role,
    Speciality,
    Timezone,
    PatientDocument,
    PatientShare,
    PatientSubscription,
    PatientVital,
    VisitNote,
)


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ("id", "username", "email", "first_name", "last_name")


class RegisterSerializer(serializers.Serializer):
    username = serializers.CharField(required=False, allow_blank=True)
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=8)
    first_name = serializers.CharField(required=False, allow_blank=True, default="")
    portal = serializers.CharField(required=False, allow_blank=True, default="patient")
    role = serializers.CharField(required=False, allow_blank=True, default="")

    def validate(self, attrs):
        portal_hint = str(attrs.get("portal") or "").lower().strip()
        role_hint = str(attrs.get("role") or "").lower().strip()
        for hint in (portal_hint, role_hint):
            if hint in ("administrator", "admin"):
                raise serializers.ValidationError(
                    {"portal": ["Administrator accounts cannot be self-registered."]}
                )
        merged = portal_hint or role_hint or "patient"
        attrs["portal"] = merged if merged else "patient"
        return attrs

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("Email already registered.")
        return value

    def create(self, validated_data):
        email = validated_data["email"]
        password = validated_data["password"]
        username = (validated_data.get("username") or "").strip()
        if not username:
            base = email.split("@")[0][:30]
            username = base
            n = 1
            while User.objects.filter(username=username).exists():
                username = f"{base}{n}"
                n += 1
        user = User.objects.create_user(
            username=username,
            email=email,
            password=password,
            first_name=validated_data.get("first_name") or "",
        )
        return user


class CountrySerializer(serializers.ModelSerializer):
    class Meta:
        model = Country
        fields = "__all__"


class SpecialitySerializer(serializers.ModelSerializer):
    country_name = serializers.CharField(
        source="country.country_name", read_only=True, default=""
    )

    class Meta:
        model = Speciality
        fields = "__all__"


class PlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = Plan
        fields = "__all__"


class RoleSerializer(serializers.ModelSerializer):
    class Meta:
        model = Role
        fields = "__all__"


class ProviderListSerializer(serializers.ModelSerializer):
    user_is_staff = serializers.SerializerMethodField()
    speciality_name = serializers.CharField(source="speciality.speciality_name", read_only=True)
    speciality_image = serializers.CharField(source="speciality.speciality_image", read_only=True)
    profile_image = serializers.CharField(source="profile_picture", read_only=True)
    country_id = serializers.IntegerField(source="speciality.country_id", read_only=True)
    country_name = serializers.CharField(
        source="speciality.country.country_name", read_only=True, default=""
    )

    class Meta:
        model = Provider
        fields = (
            "id",
            "user_id",
            "full_name",
            "email",
            "speciality_id",
            "speciality_name",
            "speciality_image",
            "profile_image",
            "phone_number",
            "whatsapp_number",
            "status",
            "consultation_fee",
            "is_verified",
            "user_is_staff",
            "country_id",
            "country_name",
        )

    def get_user_is_staff(self, obj):
        return bool(obj.user.is_staff) if obj.user_id else False


class PatientSerializer(serializers.ModelSerializer):
    user_is_staff = serializers.SerializerMethodField()
    user_is_superuser = serializers.SerializerMethodField()

    class Meta:
        model = Patient
        fields = [
            "id",
            "user",
            "image",
            "name",
            "date_of_birth",
            "email",
            "city",
            "country",
            "birth_place",
            "identity_no",
            "profile_status",
            "whatsapp_number",
            "user_is_staff",
            "user_is_superuser",
        ]

    def get_user_is_staff(self, obj):
        return bool(obj.user.is_staff) if obj.user_id else False

    def get_user_is_superuser(self, obj):
        return bool(obj.user.is_superuser) if obj.user_id else False


class PatientSelfSerializer(serializers.ModelSerializer):
    """`GET /api/patients/me/` — safe subset for the signed-in patient."""

    class Meta:
        model = Patient
        fields = (
            "id",
            "user_id",
            "name",
            "email",
            "image",
            "city",
            "country",
            "date_of_birth",
            "profile_status",
            "whatsapp_number",
        )


class PatientSelfUpdateSerializer(serializers.Serializer):
    whatsapp_number = serializers.CharField(
        required=False, allow_blank=True, max_length=32
    )


class ProviderSelfSerializer(serializers.ModelSerializer):
    """`GET /api/providers/me/` — profile for the signed-in provider."""

    speciality_name = serializers.CharField(
        source="speciality.speciality_name", read_only=True
    )

    class Meta:
        model = Provider
        fields = (
            "id",
            "user_id",
            "full_name",
            "email",
            "phone_number",
            "whatsapp_number",
            "status",
            "speciality_id",
            "speciality_name",
            "consultation_fee",
            "consultation_type",
            "profile_picture",
            "bio",
            "time_zone",
        )


class ProviderSelfUpdateSerializer(serializers.Serializer):
    phone_number = serializers.CharField(
        required=False, allow_blank=True, max_length=64
    )
    whatsapp_number = serializers.CharField(
        required=False, allow_blank=True, max_length=32
    )


class AppointmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Appointment
        fields = "__all__"


class MedicalRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = MedicalRecord
        fields = "__all__"


class ImportInboxSerializer(serializers.ModelSerializer):
    class Meta:
        model = ImportInbox
        fields = "__all__"


class AppointmentExpandedSerializer(serializers.ModelSerializer):
    provider = ProviderListSerializer(read_only=True)
    patient = PatientSerializer(read_only=True)
    visit_notes = serializers.SerializerMethodField()

    class Meta:
        model = Appointment
        fields = (
            "id",
            "date",
            "time",
            "approved",
            "medium",
            "review",
            "medical_record_id",
            "provider",
            "patient",
            "provider_id",
            "patient_id",
            "visit_notes",
        )

    def get_visit_notes(self, obj):
        qs = VisitNote.objects.filter(appointment=obj).select_related(
            "provider", "patient"
        )[:20]
        return VisitNoteSerializer(qs, many=True).data


class FeedbackSerializer(serializers.ModelSerializer):
    provider_name = serializers.CharField(source="provider.full_name", read_only=True, default="")
    patient_name = serializers.CharField(source="patient.name", read_only=True, default="")

    class Meta:
        model = Feedback
        fields = (
            "id",
            "feedback",
            "user",
            "created_at",
            "reviewer_role",
            "subject_type",
            "provider",
            "patient",
            "appointment",
            "overall_rating",
            "rating_communication",
            "rating_care_quality",
            "rating_ease",
            "rating_recommend",
            "responses",
            "provider_name",
            "patient_name",
        )
        read_only_fields = ("id", "created_at", "provider_name", "patient_name")


class NutritionEntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = NutritionEntry
        fields = ("id", "description", "calories", "logged_at")


class InvoicesSerializer(serializers.ModelSerializer):
    class Meta:
        model = Invoices
        fields = "__all__"


class TimezoneSerializer(serializers.ModelSerializer):
    class Meta:
        model = Timezone
        fields = "__all__"


class GeneralSerializer(serializers.ModelSerializer):
    class Meta:
        model = General
        fields = "__all__"


class HospitalSerializer(serializers.ModelSerializer):
    class Meta:
        model = Hospital
        fields = (
            "id",
            "name",
            "address",
            "facility_type",
            "phone_number",
            "latitude",
            "longitude",
            "rating",
            "ai_rating",
            "wait_time_minutes",
            "is_open",
            "photo_url",
        )


class PatientDocumentSerializer(serializers.ModelSerializer):
    file_url = serializers.SerializerMethodField()

    class Meta:
        model = PatientDocument
        fields = (
            "id",
            "patient_id",
            "uploaded_by_id",
            "original_name",
            "content_type",
            "size_bytes",
            "file",
            "file_url",
            "status",
            "error_message",
            "created_at",
            "processed_at",
            "ai_summary",
        )


class PatientVitalSerializer(serializers.ModelSerializer):
    class Meta:
        model = PatientVital
        fields = (
            "id",
            "patient_id",
            "recorded_by_id",
            "height_cm",
            "weight_kg",
            "temperature_c",
            "bp_sys",
            "bp_dia",
            "pulse_bpm",
            "resp_min",
            "spo2",
            "glucose_mgdl",
            "notes",
            "created_at",
        )


class PatientShareSerializer(serializers.ModelSerializer):
    provider = ProviderListSerializer(read_only=True)
    patient = PatientSerializer(read_only=True)
    vital = PatientVitalSerializer(read_only=True)

    class Meta:
        model = PatientShare
        fields = (
            "id",
            "patient_id",
            "provider_id",
            "patient_note",
            "ai_summary",
            "include_patient_email",
            "share_kind",
            "triage_payload",
            "appointment_id",
            "vital_id",
            "status",
            "created_at",
            "provider",
            "patient",
            "vital",
        )


class VisitNoteSerializer(serializers.ModelSerializer):
    provider = ProviderListSerializer(read_only=True)
    patient = PatientSerializer(read_only=True)

    class Meta:
        model = VisitNote
        fields = (
            "id",
            "patient_id",
            "provider_id",
            "appointment_id",
            "medical_record_id",
            "subjective",
            "objective",
            "assessment",
            "plan",
            "created_at",
            "updated_at",
            "provider",
            "patient",
        )


class PatientSubscriptionSerializer(serializers.ModelSerializer):
    plan = PlanSerializer(read_only=True)

    class Meta:
        model = PatientSubscription
        fields = (
            "id",
            "patient_id",
            "plan_id",
            "status",
            "revenuecat_product_id",
            "platform",
            "will_renew",
            "expires_at",
            "created_at",
            "plan",
        )


class ProviderTransactionSerializer(serializers.ModelSerializer):
    patient_name = serializers.CharField(source="patient.name", read_only=True)
    provider_name = serializers.CharField(source="provider.full_name", read_only=True)

    class Meta:
        model = ProviderTransaction
        fields = (
            "id",
            "appointment_id",
            "patient_id",
            "provider_id",
            "patient_name",
            "provider_name",
            "amount",
            "platform_commission_percent",
            "platform_fee",
            "provider_payout",
            "status",
            "notes",
            "created_at",
            "completed_at",
        )


class ProviderPayoutSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProviderPayout
        fields = (
            "id",
            "provider_id",
            "amount",
            "status",
            "stripe_transfer_id",
            "notes",
            "requested_at",
            "paid_at",
        )

    def get_file_url(self, obj):
        request = self.context.get("request")
        if not obj.file:
            return ""
        try:
            url = obj.file.url
        except Exception:
            return ""
        if request is None:
            return url
        return request.build_absolute_uri(url)
