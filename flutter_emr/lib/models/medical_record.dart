import '../utils/api_envelope.dart';

/// Symptom row used by Doctor On Call medical record JSON.
class Symptom {
  final String name;
  final String? severity;
  final String? duration;
  final String? notes;

  const Symptom({
    required this.name,
    this.severity,
    this.duration,
    this.notes,
  });

  factory Symptom.fromJson(Map<String, dynamic> json) => Symptom(
        name: json['name']?.toString() ?? '',
        severity: json['severity']?.toString(),
        duration: json['duration']?.toString(),
        notes: json['notes']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (severity != null) 'severity': severity,
        if (duration != null) 'duration': duration,
        if (notes != null) 'notes': notes,
      };
}

/// EMR medical record row — tolerant of `{ status, data }` and flat maps.
class MedicalRecord {
  MedicalRecord({
    // Doctor On Call format (required)
    required this.id,
    required this.date,
    required this.time,
    required this.symptoms,
    required this.status,
    required this.hospitalId,
    required this.hospitalName,
    this.notes = '',
    this.userId,
    this.deleted = false,
    this.deletedAt,
    this.presentingComplaints = '',
    this.pastMedicalHistory = '',
    this.socialHistory = '',
    this.surgicalHistory = '',
    List<Map<String, String>>? medications,
    List<String>? allergies,
    List<Map<String, String>>? labs,
    List<Map<String, String>>? imaging,

    // Backward compatible UI fields (optional)
    String? title,
    this.recordType,
    String? summary,
    this.providerName,
    this.facilityName,
    this.recordedAt,
    this.updatedAt,
    List<String>? tags,
    this.aiHighlight,
    Map<String, dynamic>? raw,
  })  : medications = medications ?? const [],
        allergies = allergies ?? const [],
        labs = labs ?? const [],
        imaging = imaging ?? const [],
        title = title ??
            (hospitalName.isNotEmpty ? hospitalName : 'Medical record'),
        summary = summary ?? (notes.isNotEmpty ? notes : null),
        tags = tags ?? const [],
        raw = raw ?? const {};

  // --- Required Doctor On Call fields ---
  final String id;
  final DateTime date;
  final String time;
  final List<Symptom> symptoms;
  final String status; // Completed, Pending, Active, Resolved, Follow-up, Critical
  final String hospitalId;
  final String hospitalName;
  final String notes;
  final String? userId;
  final bool deleted;
  final DateTime? deletedAt;
  final String presentingComplaints;
  final String pastMedicalHistory;
  final String socialHistory;
  final String surgicalHistory;
  final List<Map<String, String>> medications; // [{name, dosage?, frequency?}, ...]
  final List<String> allergies;
  final List<Map<String, String>> labs; // [{name, value?, unit?, note?}, ...]
  final List<Map<String, String>> imaging; // [{name, finding?, note?}, ...]

  // --- Optional UI/legacy fields ---
  final String title;
  final String? recordType;
  final String? summary;
  final String? providerName;
  final String? facilityName;
  final DateTime? recordedAt;
  final DateTime? updatedAt;
  final List<String> tags;

  /// Optional server-provided short AI teaser for list cards.
  final String? aiHighlight;
  final Map<String, dynamic> raw;

  /// Parses both legacy EMR record lists and the Doctor On Call record format.
  static MedicalRecord fromJson(Map<String, dynamic> json) {
    final m = _unwrap(json);

    final id =
        m['id']?.toString() ?? m['uuid']?.toString() ?? m['record_id']?.toString() ?? '';

    // Doctor On Call keys
    final dateRaw = m['date'];
    final time = m['time']?.toString() ?? '';
    final status = m['status']?.toString() ?? 'Active';
    final hospitalId = m['hospitalId']?.toString() ?? m['hospital_id']?.toString() ?? '';
    final hospitalName =
        m['hospitalName']?.toString() ?? m['hospital_name']?.toString() ?? '';

    List<Symptom> syms = [];
    final s = m['symptoms'];
    if (s is List) {
      syms = s
          .whereType<Map>()
          .map((e) => Symptom.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    List<Map<String, String>> meds = [];
    final md = m['medications'];
    if (md is List) {
      for (final item in md) {
        if (item is Map) {
          meds.add(
            Map<String, String>.from(
              item.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
            ),
          );
        }
      }
    }

    List<String> all = [];
    final al = m['allergies'];
    if (al is List) {
      all = al.map((e) => e.toString()).toList();
    }

    List<Map<String, String>> labs = [];
    final lb = m['labs'] ?? m['labResults'] ?? m['lab_results'];
    if (lb is List) {
      for (final item in lb) {
        if (item is Map) {
          labs.add(
            Map<String, String>.from(
              item.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
            ),
          );
        }
      }
    }

    List<Map<String, String>> imaging = [];
    final im = m['imaging'] ?? m['images'] ?? m['imaging_results'];
    if (im is List) {
      for (final item in im) {
        if (item is Map) {
          imaging.add(
            Map<String, String>.from(
              item.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
            ),
          );
        }
      }
    }

    // Legacy keys
    final title =
        m['title']?.toString() ?? m['name']?.toString() ?? m['subject']?.toString();
    final recordType = m['record_type']?.toString() ?? m['type']?.toString();
    final ra = m['recorded_at'] ?? m['recordedAt'] ?? m['created_at'];
    final ua = m['updated_at'] ?? m['updatedAt'];
    List<String> tags = [];
    final t = m['tags'];
    if (t is List) tags = t.map((e) => e.toString()).toList();

    return MedicalRecord(
      id: id,
      date: _parseDate(dateRaw) ?? _parseDate(ra) ?? DateTime.now(),
      time: time,
      symptoms: syms,
      status: status,
      hospitalId: hospitalId,
      hospitalName: hospitalName,
      notes: m['notes']?.toString() ?? m['summary']?.toString() ?? '',
      userId: m['userId']?.toString() ?? m['user_id']?.toString(),
      deleted: m['deleted'] == true || m['is_deleted'] == true,
      deletedAt: _parseDate(m['deleted_at'] ?? m['deletedAt']),
      presentingComplaints: m['presentingComplaints']?.toString() ?? '',
      pastMedicalHistory: m['pastMedicalHistory']?.toString() ?? '',
      socialHistory: m['socialHistory']?.toString() ?? '',
      surgicalHistory: m['surgicalHistory']?.toString() ?? '',
      medications: meds,
      allergies: all,
      labs: labs,
      imaging: imaging,
      title: title,
      recordType: recordType,
      summary: m['summary']?.toString() ?? m['notes']?.toString(),
      providerName: m['provider_name']?.toString() ?? m['provider']?.toString(),
      facilityName:
          m['facility_name']?.toString() ?? m['facility']?.toString(),
      recordedAt: _parseDate(ra),
      updatedAt: _parseDate(ua),
      tags: tags,
      aiHighlight: m['ai_highlight']?.toString() ?? m['aiHighlight']?.toString(),
      raw: Map<String, dynamic>.from(m),
    );
  }

  /// JSON format required by Doctor On Call (matches your snippet keys).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'time': time,
      'symptoms': symptoms.map((s) => s.toJson()).toList(),
      'status': status,
      'hospitalId': hospitalId,
      'hospitalName': hospitalName,
      'notes': notes,
      'userId': userId,
      'deleted': deleted,
      'deleted_at': deletedAt?.toIso8601String(),
      'presentingComplaints': presentingComplaints,
      'pastMedicalHistory': pastMedicalHistory,
      'socialHistory': socialHistory,
      'surgicalHistory': surgicalHistory,
      'medications': medications,
      'allergies': allergies,
      'labs': labs,
      'imaging': imaging,
    };
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    if (ApiEnvelope.isSuccess(json)) {
      final d = ApiEnvelope.dataMap(json);
      if (d != null) return d;
    }
    final inner = json['data'];
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return json;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
