import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../config/api_paths.dart';
import '../models/hospital.dart';
import '../utils/api_envelope.dart';
import 'emergency_api_client.dart';
import 'health_api.dart';

/// In-memory smart-wait cache (refresh every few minutes, not per scroll).
class HospitalWaitTimeCache {
  HospitalWaitTimeCache._();
  static final HospitalWaitTimeCache instance = HospitalWaitTimeCache._();

  static const ttl = Duration(minutes: 4);

  final Map<String, _WaitCacheEntry> _entries = {};

  Map<String, dynamic>? get(String hospitalId) {
    final e = _entries[hospitalId];
    if (e == null || DateTime.now().difference(e.at) > ttl) return null;
    return e.data;
  }

  void put(String hospitalId, Map<String, dynamic> data) {
    _entries[hospitalId] = _WaitCacheEntry(data, DateTime.now());
  }
}

class _WaitCacheEntry {
  _WaitCacheEntry(this.data, this.at);
  final Map<String, dynamic> data;
  final DateTime at;
}

/// Hospitals, OSM, courses (MyWaitime + EMR).
class CatalogApi {
  CatalogApi(this._c);

  final EmergencyApiClient _c;

  Future<dynamic> health() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.health);
    return r.data;
  }

  /// `GET /api/map-config/` — TomTom tile URL template when configured.
  Future<Map<String, dynamic>> fetchMapConfig() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.mapConfig);
    final raw = r.data;
    if (raw is Map<String, dynamic>) {
      final inner = raw['data'];
      if (inner is Map<String, dynamic>) return inner;
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return raw;
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  /// Typed list with **401 → needsSignIn** (common on production when guest has no token).
  ///
  /// When [lat] / [lon] are set, server sorts by distance (see `GET /api/hospitals/?lat=&lon=`).
  Future<HospitalsListResult> loadHospitalsList({
    double? lat,
    double? lon,
    double radiusKm = 150,
  }) async {
    try {
      final path = (lat != null && lon != null)
          ? '${ApiPaths.hospitals}?lat=$lat&lon=$lon&radius_km=$radiusKm'
          : ApiPaths.hospitals;
      final r = await _c.raw.get<dynamic>(path);
      final maps = _extractHospitalMaps(r.data);
      final hospitals = <Hospital>[];
      for (final m in maps) {
        try {
          hospitals.add(Hospital.fromJson(m));
        } catch (_) {
          /* skip malformed row */
        }
      }
      String? geoNote;
      final raw = r.data;
      if (raw is Map) {
        final m = Map<String, dynamic>.from(raw);
        if (ApiEnvelope.isSuccess(m)) {
          final d = ApiEnvelope.dataMap(m);
          geoNote = d?['geo_note']?.toString();
        }
      }
      return HospitalsListResult(hospitals: hospitals, geoNote: geoNote);
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

  /// `GET {MAPS_API_BASE_URL}health/` — Hospital Finder Django on :3015 (via nginx).
  Future<bool> isFinderApiAvailable({int attempts = 2}) =>
      HealthApi(_c).ping(attempts: attempts);

  /// Hospital Finder live search only (`MAPS_API_BASE_URL` → nginx → :3015).
  Future<HospitalsListResult> loadFinderHospitalSearch({
    required double lat,
    required double lon,
    int radiusM = 25000,
    int limit = 50,
    String type = 'all',
  }) async {
    return _loadHospitalSearch(
      apiSource: ApiConfig.mapsApiBaseUrl,
      path: ApiPaths.hospitalsSearch(
        lat: lat,
        lon: lon,
        radiusM: radiusM,
        limit: limit,
        type: type,
      ),
      fallbackNote: 'Hospital Finder (:3015) search failed.',
    );
  }

  /// Direct MyWaitime live search (`MAPS_API_BASE_URL`, e.g. local :3015).
  Future<HospitalsListResult> loadMapsHospitalSearch({
    required double lat,
    required double lon,
    int radiusM = 25000,
    int limit = 50,
    String type = 'all',
  }) async {
    return _loadHospitalSearch(
      apiSource: ApiConfig.mapsApiBaseUrl,
      path: ApiPaths.hospitalsSearch(
        lat: lat,
        lon: lon,
        radiusM: radiusM,
        limit: limit,
        type: type,
      ),
      fallbackNote:
          'MyWaitime search empty or failed — EMR proxy will be tried next.',
    );
  }

  /// TomTom Nearby Search via EMR (`GET …/api/tomtom/search-hospitals/`).
  Future<HospitalsListResult> loadTomtomHospitalSearch({
    required double lat,
    required double lon,
    int radiusM = 25000,
    int limit = 40,
  }) async {
    return _loadHospitalSearch(
      apiSource: ApiConfig.emrApiBaseUrl,
      path: ApiPaths.tomtomSearchHospitals(
        lat: lat,
        lon: lon,
        radiusM: radiusM,
        limit: limit,
      ),
      fallbackNote: 'TomTom hospital backup empty or failed.',
    );
  }

  /// EMR proxy → MyWaitime (`GET …/api/hospitals/search/` on docsoncalls).
  Future<HospitalsListResult> loadWaitimeHospitalSearch({
    required double lat,
    required double lon,
    int radiusM = 25000,
    int limit = 50,
    String type = 'all',
  }) async {
    return _loadHospitalSearch(
      apiSource: ApiConfig.emrApiBaseUrl,
      path: ApiPaths.hospitalsSearch(
        lat: lat,
        lon: lon,
        radiusM: radiusM,
        limit: limit,
        type: type,
      ),
      fallbackNote: 'EMR hospital search proxy failed.',
    );
  }

  Future<HospitalsListResult> _loadHospitalSearch({
    required String apiSource,
    required String path,
    required String fallbackNote,
  }) async {
    Future<HospitalsListResult> once() async {
      try {
        final r = await _c.raw.get<dynamic>(path);
        final hospitals = <Hospital>[];
        for (final m in _extractHospitalMaps(r.data)) {
          try {
            hospitals.add(Hospital.fromJson(m));
          } catch (_) {}
        }
        String? note;
        var upstreamDegraded = false;
        if (r.data is Map) {
          final m = Map<String, dynamic>.from(r.data as Map);
          if (m['upstream_degraded'] == true) upstreamDegraded = true;
          final src = (m['source'] ?? '').toString();
          if (src == 'emr_catalog') upstreamDegraded = true; // not Finder :3015
          final isFinderDb = src == 'local_database' ||
              src == 'mywaitime' ||
              src.contains('finder') ||
              (ApiEnvelope.isSuccess(m) && m['data'] is List);
          final found = m['total_found'] ?? m['totalFound'];
          final geo = m['geo_note']?.toString();
          if (geo != null && geo.isNotEmpty) {
            note = geo;
          } else if (found != null) {
            note = upstreamDegraded
                ? 'EMR catalog ($src): $found near you · $apiSource'
                : isFinderDb
                ? 'Finder DB (:3015): $found near you · $apiSource'
                : 'Live search ($src): $found found · $apiSource';
          } else if (upstreamDegraded) {
            note = 'EMR catalog near you (live search unavailable) · $apiSource';
          }
          if (ApiEnvelope.isSuccess(m)) {
            final d = ApiEnvelope.dataMap(m);
            if (d?['upstream_degraded'] == true) upstreamDegraded = true;
          }
        }
        return HospitalsListResult(
          hospitals: hospitals,
          geoNote: note ?? 'Live search · $apiSource',
          apiSource: apiSource,
          upstreamDegraded: upstreamDegraded,
        );
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code == 401 || code == 403) {
          return const HospitalsListResult(needsSignIn: true);
        }
        if (code == 429) {
          return HospitalsListResult(
            errorMessage: 'Rate limited (429). Cache results and retry later.',
            geoNote: fallbackNote,
            apiSource: apiSource,
          );
        }
        return HospitalsListResult(
          errorMessage: _dioMessage(e),
          geoNote: fallbackNote,
          apiSource: apiSource,
        );
      } catch (e) {
        return HospitalsListResult(
          errorMessage: e.toString(),
          geoNote: fallbackNote,
          apiSource: apiSource,
        );
      }
    }

    var result = await once();
    if (result.hasError &&
        (result.errorMessage?.contains('502') == true ||
            result.errorMessage?.contains('503') == true)) {
      result = await once();
    }
    return result;
  }

  /// `GET …/api/hospitals/<uuid>/smart-wait-time/`
  Future<Map<String, dynamic>> loadSmartWaitTime(
    String uuid, {
    double? userLat,
    double? userLon,
    bool useCache = true,
  }) async {
    if (useCache) {
      final cached = HospitalWaitTimeCache.instance.get(uuid);
      if (cached != null) return cached;
    }
    try {
      final r = await _c.raw.get<dynamic>(
        ApiPaths.hospitalSmartWaitTime(uuid, userLat: userLat, userLon: userLon),
      );
      final raw = _unwrapToMap(r.data);
      if (raw.isNotEmpty && useCache) {
        HospitalWaitTimeCache.instance.put(uuid, raw);
      }
      return raw;
    } on DioException catch (e) {
      if (e.response?.statusCode == 502) {
        final r2 = await _c.raw.get<dynamic>(
          ApiPaths.hospitalSmartWaitTime(uuid, userLat: userLat, userLon: userLon),
        );
        return _unwrapToMap(r2.data);
      }
      rethrow;
    }
  }

  /// `POST …/api/hospitals/smart-wait-time/batch/` (max 30 ids).
  Future<Map<String, dynamic>> loadSmartWaitTimeBatch({
    required List<String> hospitalIds,
    double? userLat,
    double? userLon,
  }) async {
    final ids = hospitalIds.take(30).toList();
    final r = await _c.raw.post<dynamic>(
      ApiPaths.hospitalsSmartWaitTimeBatch,
      data: {
        'hospital_ids': ids,
        if (userLat != null) 'user_lat': userLat,
        if (userLon != null) 'user_lon': userLon,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return _unwrapToMap(r.data);
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
    this.geoNote,
    this.apiSource,
    this.upstreamDegraded = false,
  });

  final List<Hospital> hospitals;
  final bool needsSignIn;
  final String? errorMessage;

  /// Backend hint when no rows fall inside [radius_km] but farther entries are returned.
  final String? geoNote;

  /// Which base URL served this list (MyWaitime vs EMR).
  final String? apiSource;

  /// `GET hospitals/search/` returned EMR catalog because MyWaitime was down.
  final bool upstreamDegraded;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  HospitalsListResult copyWith({
    List<Hospital>? hospitals,
    bool? needsSignIn,
    String? errorMessage,
    String? geoNote,
    String? apiSource,
    bool? upstreamDegraded,
  }) {
    return HospitalsListResult(
      hospitals: hospitals ?? this.hospitals,
      needsSignIn: needsSignIn ?? this.needsSignIn,
      errorMessage: errorMessage ?? this.errorMessage,
      geoNote: geoNote ?? this.geoNote,
      apiSource: apiSource ?? this.apiSource,
      upstreamDegraded: upstreamDegraded ?? this.upstreamDegraded,
    );
  }
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
      final payload = m['data'];
      if (payload is List) {
        return payload
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
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
  String tail = '';
  if (e.response?.data is Map) {
    final m = Map<String, dynamic>.from(e.response!.data as Map);
    tail = (m['message'] ?? m['detail'] ?? '').toString().trim();
    if (tail.isEmpty && m['errors'] != null) {
      tail = m['errors'].toString();
    }
  }
  if (c == 502) {
    final detail = tail.isNotEmpty ? tail : 'Live hospital search unavailable.';
    return 'HTTP 502 — $detail Pull down to retry (EMR → Maps → catalog).';
  }
  if (c == 503) {
    final detail = tail.isNotEmpty ? tail : 'Service temporarily unavailable.';
    return 'HTTP 503 — $detail Pull down to retry.';
  }
  if (c != null) {
    return tail.isNotEmpty ? 'HTTP $c — $tail' : 'HTTP $c';
  }
  return e.message ?? 'Network error';
}
