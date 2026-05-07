import 'package:dio/dio.dart';

import '../config/api_paths.dart';
import 'emergency_api_client.dart';

/// EMR features: appointments, providers, countries, feedback, replicate — paths follow [ApiPaths].
class EmrFeaturesApi {
  EmrFeaturesApi(this._c);

  final EmergencyApiClient _c;

  Future<dynamic> registrationsPending() async {
    final r = await _c.raw.get<dynamic>('/registrations/pending/');
    return r.data;
  }

  Future<dynamic> registrationsApprove({required String kind, required int id}) async {
    final r = await _c.raw.post<dynamic>(
      '/registrations/approve/',
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
      '/imports/submit/',
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

  Future<void> adminPatchSpeciality(int id, Map<String, dynamic> patch) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.specialitiesList}$id/',
      data: patch,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<void> adminPatchProvider(int id, Map<String, dynamic> patch) async {
    await _c.raw.patch<dynamic>(
      '${ApiPaths.providersList}$id/',
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

  Future<void> submitFeedback(String text) async {
    await _c.raw.post<dynamic>(
      ApiPaths.feedback,
      data: {'feedback': text},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<dynamic> replicateToken() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.replicateToken);
    return r.data;
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
  }) async {
    final r = await _c.raw.post<dynamic>(
      '/providers/apply/',
      data: {
        'full_name': fullName,
        'email': email,
        'phone_number': phoneNumber,
        'gender': gender,
        'speciality_id': specialityId,
        'license_number': (licenseNumber ?? '').trim(),
        'qualifications': (qualifications ?? '').trim(),
        'bio': (bio ?? '').trim(),
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
