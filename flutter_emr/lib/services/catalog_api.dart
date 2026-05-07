import 'package:dio/dio.dart';

import '../config/api_paths.dart';
import '../models/hospital.dart';
import '../utils/api_envelope.dart';
import 'emergency_api_client.dart';

/// Hospitals, OSM, courses (Django-oriented).
class CatalogApi {
  CatalogApi(this._c);

  final EmergencyApiClient _c;

  Future<dynamic> health() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.health);
    return r.data;
  }

  /// Typed list with **401 → needsSignIn** (common on production when guest has no token).
  Future<HospitalsListResult> loadHospitalsList() async {
    try {
      final r = await _c.raw.get<dynamic>(ApiPaths.hospitals);
      final maps = _extractHospitalMaps(r.data);
      final hospitals = <Hospital>[];
      for (final m in maps) {
        try {
          hospitals.add(Hospital.fromJson(m));
        } catch (_) {
          /* skip malformed row */
        }
      }
      return HospitalsListResult(hospitals: hospitals);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return const HospitalsListResult(needsSignIn: true);
      }
      return HospitalsListResult(errorMessage: _dioMessage(e));
    } catch (e) {
      return HospitalsListResult(errorMessage: e.toString());
    }
  }

  Future<HospitalDetailResult> loadHospitalDetail(String uuid) async {
    try {
      final r = await _c.raw.get<dynamic>(ApiPaths.hospitalDetail(uuid));
      var raw = _unwrapToMap(r.data);
      if (raw.isEmpty) {
        return const HospitalDetailResult(errorMessage: 'No data returned');
      }
      raw = Map<String, dynamic>.from(raw);
      raw.putIfAbsent('id', () => uuid);
      raw.putIfAbsent('uuid', () => uuid);
      final h = Hospital.fromJson(raw);
      return HospitalDetailResult(hospital: h, raw: raw);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return const HospitalDetailResult(needsSignIn: true);
      }
      return HospitalDetailResult(errorMessage: _dioMessage(e));
    } catch (e) {
      return HospitalDetailResult(errorMessage: e.toString());
    }
  }

  /// Legacy raw map (no 401 handling) — prefer [loadHospitalDetail].
  Future<Map<String, dynamic>> hospitalDetail(String uuid) async {
    final r = await _c.raw.get<dynamic>(ApiPaths.hospitalDetail(uuid));
    final data = r.data;
    if (data is Map<String, dynamic>) return _unwrapToMap(data);
    if (data is Map) return _unwrapToMap(Map<String, dynamic>.from(data));
    return {};
  }

  /// `GET …/api/hospitals/<uuid>/ai-wait-time/`
  Future<dynamic> hospitalAiWaitTime(String uuid) async {
    final r = await _c.raw.get<dynamic>(ApiPaths.hospitalAiWaitTime(uuid));
    return r.data;
  }

  Future<dynamic> hospitalsSearch(double lat, double lon) async {
    final r = await _c.raw.get<dynamic>(
      ApiPaths.hospitalsSearch(lat: lat, lon: lon),
    );
    return r.data;
  }

  Future<dynamic> osmSearchHospitals(double lat, double lon) async {
    final r = await _c.raw.get<dynamic>(
      ApiPaths.osmSearchHospitals(lat: lat, lon: lon),
    );
    return r.data;
  }

  Future<dynamic> osmSystemStatus() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.osmSystemStatus);
    return r.data;
  }

  Future<dynamic> courses() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.coursesV1);
    return r.data;
  }
}

// --- Helpers & DTOs ---

class HospitalsListResult {
  const HospitalsListResult({
    this.hospitals = const [],
    this.needsSignIn = false,
    this.errorMessage,
  });

  final List<Hospital> hospitals;
  final bool needsSignIn;
  final String? errorMessage;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
}

class HospitalDetailResult {
  const HospitalDetailResult({
    this.hospital,
    this.needsSignIn = false,
    this.errorMessage,
    this.raw = const {},
  });

  final Hospital? hospital;
  final bool needsSignIn;
  final String? errorMessage;
  final Map<String, dynamic> raw;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
}

List<Map<String, dynamic>> _extractHospitalMaps(dynamic data) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (data is Map) {
    final m = Map<String, dynamic>.from(data);
    if (ApiEnvelope.isSuccess(m)) {
      final d = ApiEnvelope.dataMap(m);
      if (d != null) return _extractHospitalMaps(d);
    }
    for (final key in ['results', 'hospitals', 'data', 'items', 'places']) {
      final v = m[key];
      if (v is List) {
        return v
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
  }
  return [];
}

Map<String, dynamic> _unwrapToMap(dynamic data) {
  if (data is! Map) return {};
  final m = Map<String, dynamic>.from(data);
  if (ApiEnvelope.isSuccess(m)) {
    final d = ApiEnvelope.dataMap(m);
    if (d != null) return d;
  }
  final inner = m['data'];
  if (inner is Map) return Map<String, dynamic>.from(inner);
  return m;
}

String _dioMessage(DioException e) {
  final c = e.response?.statusCode;
  final tail =
      e.response?.data is Map && (e.response!.data as Map)['message'] != null
      ? ' ${(e.response!.data as Map)['message']}'
      : '';
  if (c != null) return 'HTTP $c$tail';
  return e.message ?? 'Network error';
}
