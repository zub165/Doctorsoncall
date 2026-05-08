import '../utils/api_envelope.dart';

/// Hospital / ER listing row — tolerant of Django envelopes, Google Places, and plain JSON.
class Hospital {
  final String id;
  final String name;
  final String address;
  final String? phoneNumber;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String estimatedTime;
  final bool isOpen;
  final double rating;
  final String? photoUrl;
  final int waitTimeMinutes;
  final String facilityType;
  final double? aiRating;
  final int? travelTimeMinutes;
  final int? trafficDelayMinutes;
  final String? routeType;
  final String? googlePlaceId;
  final String? tomtomId;
  final String? email;
  final String? description;

  Hospital({
    required this.id,
    required this.name,
    required this.address,
    this.phoneNumber,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.estimatedTime,
    required this.isOpen,
    required this.rating,
    this.photoUrl,
    this.waitTimeMinutes = 0,
    this.facilityType = 'Hospital',
    this.aiRating,
    this.travelTimeMinutes,
    this.trafficDelayMinutes,
    this.routeType,
    this.googlePlaceId,
    this.tomtomId,
    this.email,
    this.description,
  });

  static Hospital fromJson(Map<String, dynamic> json) {
    final root = _unwrap(json);

    // Prefer server primary keys first so `GET /api/hospitals/<id>/` matches Django EMR.
    // `place_id` (Google/Maps) must not win when EMR also sends numeric `id`.
    var id =
        root['id']?.toString() ??
        root['uuid']?.toString() ??
        root['place_id']?.toString() ??
        '';

    double lat = _lat(root) ?? 0;
    double lng = _lng(root) ?? 0;

    final distanceKm = _distanceKm(root);

    final ratingRaw = root['rating'];
    final rating = ratingRaw is num
        ? ratingRaw.toDouble()
        : double.tryParse(ratingRaw?.toString() ?? '') ?? 0.0;

    final wait =
        root['waitTimeMinutes'] ??
        root['wait_time_minutes'] ??
        root['wait_time'];
    final waitInt = wait is int
        ? wait
        : (wait is num
              ? wait.toInt()
              : int.tryParse(wait?.toString() ?? '') ?? 0);

    final ai = root['aiRating'] ?? root['ai_rating'];
    final aiRating = ai is num
        ? ai.toDouble()
        : double.tryParse(ai?.toString() ?? '');

    final photo =
        root['photo_url'] ?? root['photoUrl'] ?? root['image'] ?? root['photo'];
    String? photoUrl;
    if (photo is String && photo.startsWith('http')) {
      photoUrl = photo;
    }

    final openRaw = root['opening_hours'] is Map
        ? (root['opening_hours'] as Map)['open_now']
        : root['is_open'] ?? root['open_now'] ?? true;
    final isOpen = openRaw is bool ? openRaw : true;

    if (id.isEmpty) {
      id = 'h_${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';
    }

    return Hospital(
      id: id,
      name: root['name']?.toString() ?? root['title']?.toString() ?? 'Hospital',
      address:
          root['vicinity']?.toString() ??
          root['address']?.toString() ??
          root['formatted_address']?.toString() ??
          '',
      phoneNumber:
          root['formatted_phone_number']?.toString() ??
          root['phone']?.toString() ??
          root['phoneNumber']?.toString(),
      latitude: lat,
      longitude: lng,
      distanceKm: distanceKm,
      estimatedTime:
          root['duration']?.toString() ??
          root['estimated_time']?.toString() ??
          root['estimatedTime']?.toString() ??
          '—',
      isOpen: isOpen,
      rating: rating,
      photoUrl: photoUrl,
      waitTimeMinutes: waitInt,
      facilityType:
          root['facilityType']?.toString() ??
          root['facility_type']?.toString() ??
          'Hospital',
      aiRating: aiRating,
      travelTimeMinutes: _intOrNull(
        root['travelTimeMinutes'] ?? root['travel_time_minutes'],
      ),
      trafficDelayMinutes: _intOrNull(
        root['trafficDelayMinutes'] ?? root['traffic_delay_minutes'],
      ),
      routeType:
          root['routeType']?.toString() ?? root['route_type']?.toString(),
      googlePlaceId: root['google_place_id']?.toString(),
      tomtomId: root['tomtom_id']?.toString(),
      email: root['email']?.toString(),
      description: root['description']?.toString(),
    );
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    if (ApiEnvelope.isSuccess(json)) {
      final d = ApiEnvelope.dataMap(json);
      if (d != null) return d;
    }
    final inner = json['data'];
    if (inner is Map<String, dynamic>) return inner;
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return json;
  }

  static double? _lat(Map<String, dynamic> j) {
    final g = j['geometry'];
    if (g is Map) {
      final loc = g['location'];
      if (loc is Map) {
        final la = loc['lat'];
        if (la is num) return la.toDouble();
      }
    }
    final a = j['latitude'] ?? j['lat'];
    if (a is num) return a.toDouble();
    return double.tryParse(a?.toString() ?? '');
  }

  static double? _lng(Map<String, dynamic> j) {
    final g = j['geometry'];
    if (g is Map) {
      final loc = g['location'];
      if (loc is Map) {
        final lg = loc['lng'] ?? loc['lon'];
        if (lg is num) return lg.toDouble();
      }
    }
    final a = j['longitude'] ?? j['lng'] ?? j['lon'];
    if (a is num) return a.toDouble();
    return double.tryParse(a?.toString() ?? '');
  }

  /// Interprets distance: explicit km fields, else heuristic meters → km.
  static double _distanceKm(Map<String, dynamic> j) {
    if (j['distance_km'] != null || j['distance_in_km'] != null) {
      final v = j['distance_km'] ?? j['distance_in_km'];
      final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
      return n;
    }
    final raw = j['distance'];
    if (raw == null) return 0;
    final v = raw is num
        ? raw.toDouble()
        : double.tryParse(raw.toString()) ?? 0;
    if (v > 200) return v * 0.001;
    return v;
  }

  static int? _intOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'phoneNumber': phoneNumber,
    'latitude': latitude,
    'longitude': longitude,
    'distanceKm': distanceKm,
    'estimatedTime': estimatedTime,
    'isOpen': isOpen,
    'rating': rating,
    'photoUrl': photoUrl,
    'waitTimeMinutes': waitTimeMinutes,
    'facilityType': facilityType,
    'aiRating': aiRating,
    'travelTimeMinutes': travelTimeMinutes,
    'trafficDelayMinutes': trafficDelayMinutes,
    'routeType': routeType,
    'google_place_id': googlePlaceId,
    'tomtom_id': tomtomId,
    'email': email,
    'description': description,
  };
}
