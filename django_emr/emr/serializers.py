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
  Role,
    Speciality,
    Timezone,
    PatientDocument,
    PatientShare,
    PatientSubscription,
    PatientVital,
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
    class Meta:
        model = Provider
        fields = (
            "id",
            "full_name",
            "email",
            "speciality_id",
            "status",
            "consultation_fee",
        )


class PatientSerializer(serializers.ModelSerializer):
    class Meta:
        model = Patient
        fields = "__all__"


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
        )


class FeedbackSerializer(serializers.ModelSerializer):
    class Meta:
        model = Feedback
        fields = ("id", "feedback", "user", "created_at")


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


class PatientShareSerializer(serializers.ModelSerializer):
    provider = ProviderListSerializer(read_only=True)
    patient = PatientSerializer(read_only=True)

    class Meta:
        model = PatientShare
        fields = (
            "id",
            "patient_id",
            "provider_id",
            "patient_note",
            "ai_summary",
            "include_patient_email",
            "status",
            "created_at",
            "provider",
            "patient",
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


class PatientSubscriptionSerializer(serializers.ModelSerializer):
    plan = PlanSerializer(read_only=True)

    class Meta:
        model = PatientSubscription
        fields = (
            "id",
            "patient_id",
            "plan_id",
            "status",
            "stripe_customer_id",
            "stripe_session_id",
            "stripe_subscription_id",
            "created_at",
            "plan",
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
