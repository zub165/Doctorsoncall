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
}
