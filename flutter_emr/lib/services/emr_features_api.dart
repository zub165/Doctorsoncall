import 'package:dio/dio.dart';

import '../config/api_paths.dart';
import '../models/billing.dart';
import 'emergency_api_client.dart';

/// EMR features: appointments, providers, countries, feedback, Ollama status — paths follow [ApiPaths].
class EmrFeaturesApi {
  EmrFeaturesApi(this._c);

  final EmergencyApiClient _c;

  Future<dynamic> registrationsPending() async {
    // Paths must be relative to baseUrl (`…/api/`); a leading `/` drops `/api/` in Dio.
    final r = await _c.raw.get<dynamic>(ApiPaths.registrationsPending);
    return r.data;
  }

  Future<dynamic> registrationsApprove({required String kind, required int id}) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.registrationsApprove,
      data: {'kind': kind, 'id': id},
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  Future<dynamic> importSubmit({
    required String sourceUrl,
    required String patientEmail,
    required String rawPayload,
    required String aiSummary,
    String patientHint = '',
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.importsSubmit,
      data: {
        'source_url': sourceUrl,
        'patient_email': patientEmail,
        'patient_hint': patientHint,
        'raw_payload': rawPayload,
        'ai_summary': aiSummary,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  Future<void> adminPatchCountry(int id, Map<String, dynamic> patch) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.countriesList}$id/',
      data: patch,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<int> adminCreateCountry(Map<String, dynamic> body) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.countriesList,
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
    final data = r.data;
    if (data is Map && data['id'] != null) return (data['id'] as num).toInt();
    return 0;
  }

  Future<void> adminDeleteCountry(int id) async {
    await _c.raw.delete<dynamic>('${ApiPaths.countriesList}$id/');
  }

  /// kind: `patient` | `doctor` | `admin`
  Future<void> adminCreateUser({
    required String kind,
    required String email,
    required String password,
    required String name,
    int? specialityId,
    String? phoneNumber,
    String? profileStatus,
  }) async {
    final body = <String, dynamic>{
      'kind': kind,
      'email': email,
      'password': password,
      'name': name,
    };
    if (specialityId != null) body['speciality_id'] = specialityId;
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      body['phone_number'] = phoneNumber;
    }
    if (profileStatus != null && profileStatus.isNotEmpty) {
      body['profile_status'] = profileStatus;
    }
    await _c.raw.post<dynamic>(
      ApiPaths.adminCreateUser,
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<void> adminPatchSpeciality(int id, Map<String, dynamic> patch) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.specialitiesList}$id/',
      data: patch,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  /// Staff POST — downloads PNGs to server media and sets `speciality_image` URLs.
  Future<Map<String, dynamic>> adminSeedSpecialityAvatars({bool force = false}) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.specialitiesSeedAvatars,
      data: {if (force) 'force': true},
      options: Options(contentType: Headers.jsonContentType),
    );
    final data = r.data;
    if (data is Map) {
      final inner = data['data'];
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return Map<String, dynamic>.from(data);
    }
    return const {};
  }

  Future<void> adminPatchProvider(int id, Map<String, dynamic> patch) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.providersList}$id/',
      data: patch,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<void> adminPatchPatient(int id, Map<String, dynamic> patch) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.patientsList}$id/',
      data: patch,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<void> adminDeletePatient(int id) async {
    await _c.raw.delete<dynamic>('${ApiPaths.patientsList}$id/');
  }

  Future<void> adminDeleteProvider(int id) async {
    await _c.raw.delete<dynamic>('${ApiPaths.providersList}$id/');
  }

  /// [fixture] — when true, calls `GET …/plans/?fixture=1` so Django can seed demo rows when allowed.
  /// [all] — admin only: `GET …/plans/?all=1` includes test/legacy rows without store product ids.
  Future<dynamic> plans({bool fixture = false, bool all = false}) async {
    final q = <String>[];
    if (fixture) q.add('fixture=1');
    if (all) q.add('all=1');
    final path = q.isEmpty ? ApiPaths.plans : '${ApiPaths.plans}?${q.join('&')}';
    final r = await _c.raw.get<dynamic>(path);
    return r.data;
  }

  Future<void> adminPatchPlan(int id, Map<String, dynamic> patch) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.plans}$id/',
      data: patch,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<dynamic> roles() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.roles);
    return r.data;
  }

  Future<void> adminPatchRole(int id, Map<String, dynamic> patch) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.roles}$id/',
      data: patch,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<dynamic> myAppointments() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.myAppointments);
    return r.data;
  }

  Future<dynamic> storeAppointment({
    required int providerId,
    required String date,
    required String time,
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.storeAppointment,
      data: {
        'provider_id': providerId,
        'date': date,
        'time': time,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  /// `POST /api/appointments/` — includes [AppointmentBookResult.billingHint].
  Future<AppointmentBookResult> bookAppointment({
    required int providerId,
    required String date,
    required String time,
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.storeAppointment,
      data: {
        'provider_id': providerId,
        'date': date,
        'time': time,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return AppointmentBookResult.fromResponse(r.data);
  }

  Future<dynamic> providers() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.providersList);
    return r.data;
  }

  Future<dynamic> countries() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.countriesList);
    return r.data;
  }

  Future<dynamic> specialities() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.specialitiesList);
    return r.data;
  }

  Future<dynamic> patientsProviders() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.patientsProvidersCross);
    return r.data;
  }

  Future<dynamic> patients() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.patientsList);
    return r.data;
  }

  Future<dynamic> allAppointments() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.allAppointments);
    return r.data;
  }

  /// Links a server [MedicalRecord] to an appointment (`PATCH …/appointments/<id>/`).
  Future<void> patchAppointmentMedicalRecord({
    required int appointmentId,
    required int medicalRecordId,
  }) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.storeAppointment}$appointmentId/',
      data: {'medical_record_id': medicalRecordId},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  /// Clears appointment ↔ chart link on the server (`medical_record_id: null`).
  Future<void> clearAppointmentMedicalRecord(int appointmentId) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.storeAppointment}$appointmentId/',
      data: {'medical_record_id': null},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  /// Staff PATCH `…/appointments/<id>/` — keys `date`, `time`, `status` (maps to approved on server).
  Future<void> adminPatchAppointment(int id, Map<String, dynamic> patch) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.storeAppointment}$id/',
      data: patch,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<void> adminDeleteAppointment(int id) async {
    await _c.raw.delete<dynamic>('${ApiPaths.storeAppointment}$id/');
  }

  /// Staff POST `appointments/` with `patient_id`, `provider_id`, `date`, `time`, optional `status`.
  Future<int> adminCreateAppointment({
    required int patientId,
    required int providerId,
    required String date,
    required String time,
    String? status,
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.storeAppointment,
      data: {
        'patient_id': patientId,
        'provider_id': providerId,
        'date': date,
        'time': time,
        if (status != null && status.isNotEmpty) 'status': status,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    final data = r.data;
    if (data is Map) {
      final appt = data['appointment'] ?? (data['data'] is Map ? (data['data'] as Map)['appointment'] : null);
      if (appt is Map && appt['id'] != null) return (appt['id'] as num).toInt();
      if (data['id'] != null) return (data['id'] as num).toInt();
    }
    return 0;
  }

  Future<Map<String, dynamic>> fetchFeedbackContext() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.feedbackContext);
    final data = r.data;
    if (data is Map && data['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<void> submitFeedback(String text) async {
    await submitVisitFeedback(feedback: text);
  }

  /// Visit-linked star ratings for patient ↔ doctor (see `feedback/context/`).
  Future<void> submitVisitFeedback({
    required String feedback,
    String? subjectType,
    int? providerId,
    int? patientId,
    int? appointmentId,
    int? overallRating,
    int? ratingCommunication,
    int? ratingCareQuality,
    int? ratingEase,
    int? ratingRecommend,
  }) async {
    final body = <String, dynamic>{
      'feedback': feedback,
      if (subjectType != null && subjectType.isNotEmpty) 'subject_type': subjectType,
      if (providerId != null) 'provider_id': providerId,
      if (patientId != null) 'patient_id': patientId,
      if (appointmentId != null) 'appointment_id': appointmentId,
      if (overallRating != null) 'overall_rating': overallRating,
      if (ratingCommunication != null) 'rating_communication': ratingCommunication,
      if (ratingCareQuality != null) 'rating_care_quality': ratingCareQuality,
      if (ratingEase != null) 'rating_ease': ratingEase,
      if (ratingRecommend != null) 'rating_recommend': ratingRecommend,
    };
    await _c.raw.post<dynamic>(
      ApiPaths.feedback,
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<dynamic> myInvoices({bool fixture = false}) async {
    final r = await _c.raw.get<dynamic>(
      ApiPaths.invoices,
      queryParameters: {if (fixture) 'fixture': '1'},
    );
    return r.data;
  }

  Future<dynamic> vitals() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.vitals);
    return r.data;
  }

  Future<dynamic> billingStatus() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.billingStatus);
    return r.data;
  }

  /// `GET /api/billing/status/` — active sub + [VisitAllowance].
  Future<BillingStatusSnapshot> fetchBillingStatus() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.billingStatus);
    return BillingStatusSnapshot.fromResponse(r.data);
  }

  Future<dynamic> billingCheckout(int planId, {String platform = 'web'}) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.billingCheckout,
      data: {'plan_id': planId, 'platform': platform},
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  /// `POST /api/billing/verify-store/` — after App Store / Play purchase (no RevenueCat).
  Future<dynamic> billingVerifyStore({
    required int planId,
    required String platform,
    required String productId,
    required String purchaseId,
    required String verificationData,
    String localVerificationData = '',
    String? transactionDate,
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.billingVerifyStore,
      data: {
        'plan_id': planId,
        'platform': platform,
        'product_id': productId,
        'purchase_id': purchaseId,
        'verification_data': verificationData,
        if (localVerificationData.isNotEmpty)
          'local_verification_data': localVerificationData,
        if (transactionDate != null && transactionDate.isNotEmpty)
          'transaction_date': transactionDate,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  Future<dynamic> adminBillingSummary() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.billingAdminSummary);
    return r.data;
  }

  // ── Doctor billing ──

  Future<dynamic> doctorBillingSummary() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.doctorBillingSummary);
    return r.data;
  }

  Future<dynamic> doctorTransactions() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.doctorTransactions);
    return r.data;
  }

  Future<dynamic> doctorComplimentaryVisit({
    required int patientId,
    String notes = '',
    int? appointmentId,
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.doctorComplimentaryVisit,
      data: {
        'patient_id': patientId,
        'notes': notes,
        if (appointmentId != null) 'appointment_id': appointmentId,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  Future<dynamic> doctorCreateInvoice({
    required int patientId,
    double? amount,
    String notes = '',
    int? appointmentId,
    bool complimentary = false,
    bool useDefaultFee = false,
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.doctorCreateInvoice,
      data: {
        'patient_id': patientId,
        if (amount != null) 'amount': amount,
        'notes': notes,
        if (appointmentId != null) 'appointment_id': appointmentId,
        if (complimentary) 'complimentary': true,
        if (useDefaultFee) 'use_default_fee': true,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  Future<dynamic> doctorRequestPayout(double amount) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.doctorRequestPayout,
      data: {'amount': amount},
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  Future<dynamic> doctorStripeConnectOnboard() async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.doctorStripeConnect,
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  Future<dynamic> doctorStripeConnectStatus() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.doctorStripeConnectStatus);
    return r.data;
  }

  // ── Patient billing ──

  Future<dynamic> patientBills() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.patientBills);
    return r.data;
  }

  Future<dynamic> patientPayBill(int transactionId) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.patientPayBill,
      data: {'transaction_id': transactionId},
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  /// `GET /api/integrations/ollama-status/` — Llama on server (GoDaddy Ollama).
  Future<Map<String, dynamic>> ollamaStatus() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.ollamaStatus);
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  Future<dynamic> providerApply({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String gender,
    required int specialityId,
    String? licenseNumber,
    String? qualifications,
    String? bio,
    bool volunteerOnlineVisits = false,
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.providersApply,
      data: {
        'full_name': fullName,
        'email': email,
        'phone_number': phoneNumber,
        'gender': gender,
        'speciality_id': specialityId,
        'license_number': (licenseNumber ?? '').trim(),
        'qualifications': (qualifications ?? '').trim(),
        'bio': (bio ?? '').trim(),
        'volunteer_online_visits': volunteerOnlineVisits,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return r.data;
  }

  Future<void> changePassword(String newPassword) async {
    await _c.raw.post<dynamic>(
      ApiPaths.changePassword,
      data: {'new_password': newPassword},
      options: Options(contentType: Headers.jsonContentType),
    );
  }
}
