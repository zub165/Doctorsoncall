/// Django-style `{ "status": "success"|"error", "data": ... }` helpers.
class ApiEnvelope {
  ApiEnvelope._();

  static bool isSuccess(Map<String, dynamic>? json) =>
      json != null && json['status']?.toString() == 'success';

  static Map<String, dynamic>? dataMap(Map<String, dynamic>? json) {
    final d = json?['data'];
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    return null;
  }

  static String? errorMessage(Map<String, dynamic>? json) {
    if (json == null) return null;
    return json['message']?.toString() ?? json['errors']?.toString();
  }

  /// Normalizes plan list payloads from DRF list, paginated `{ results }`, or wrapped envelopes.
  static List<Map<String, dynamic>> coercePlanList(dynamic raw) {
    if (raw == null) return [];

    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (raw is! Map) return [];

    final m = Map<String, dynamic>.from(raw);

    if (m['results'] is List) {
      return coercePlanList(m['results']);
    }
    if (m['plans'] is List) {
      return coercePlanList(m['plans']);
    }

    if (isSuccess(m)) {
      final dm = dataMap(m);
      if (dm != null) {
        final inner = coercePlanList(dm);
        if (inner.isNotEmpty) return inner;
      }
      final d = m['data'];
      if (d is List) {
        return coercePlanList(d);
      }
      if (d is Map) {
        return coercePlanList(d);
      }
    }

    final data = m['data'];
    if (data is Map) {
      final dm = Map<String, dynamic>.from(data);
      if (dm['results'] is List) return coercePlanList(dm['results']);
      if (dm['plans'] is List) return coercePlanList(dm['plans']);
    }

    return [];
  }
}
