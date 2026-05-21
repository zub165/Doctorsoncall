import 'dart:math' as math;

import '../models/hospital.dart';

/// Display distance in km or miles (1 mi ≈ 1.60934 km).
enum DistanceUnit { km, miles }

extension DistanceUnitLabel on DistanceUnit {
  String get shortLabel => this == DistanceUnit.km ? 'km' : 'mi';
}

String formatDistanceKm(double distanceKm, DistanceUnit unit) {
  if (distanceKm <= 0) return '';
  if (unit == DistanceUnit.km) {
    final d = distanceKm;
    return d < 10 ? '${d.toStringAsFixed(1)} km' : '${d.toStringAsFixed(0)} km';
  }
  final miles = distanceKm / 1.60934;
  return miles < 10 ? '${miles.toStringAsFixed(1)} mi' : '${miles.toStringAsFixed(0)} mi';
}

/// Search radius for MyWaitime `radius_m` query param.
int radiusMetersForUnit(DistanceUnit unit, {double kmRadius = 40}) {
  final km = kmRadius.clamp(5.0, 200.0);
  if (unit == DistanceUnit.km) {
    return (km * 1000).round();
  }
  return (km * 1000 * 1.60934).round();
}

/// Max distance (km) for list/map when filtering catalog rows to "near you".
double catalogRadiusKm(DistanceUnit unit, {double kmRadius = 80}) {
  final km = kmRadius.clamp(10.0, 200.0);
  if (unit == DistanceUnit.km) return km;
  return km * 1.60934;
}

const _earthRadiusKm = 6371.0;

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final la1 = lat1 * math.pi / 180;
  final la2 = lat2 * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusKm * c;
}

extension HospitalNearFilter on List<Hospital> {
  /// True if at least one row is within [maxKm] of ([lat], [lon]).
  bool hasAnyNear(double lat, double lon, double maxKm) {
    for (final h in this) {
      if (h.latitude.abs() < 1e-5 && h.longitude.abs() < 1e-5) continue;
      final km = h.distanceKm > 0 && h.distanceKm < 500
          ? h.distanceKm
          : haversineKm(lat, lon, h.latitude, h.longitude);
      if (km <= maxKm) return true;
    }
    return false;
  }

  /// Keeps rows with coordinates within [maxKm] of ([lat], [lon]).
  List<Hospital> nearLocation(double lat, double lon, double maxKm) {
    final out = <Hospital>[];
    for (final h in this) {
      if (h.latitude.abs() < 1e-5 && h.longitude.abs() < 1e-5) continue;
      final km = h.distanceKm > 0 && h.distanceKm < 500
          ? h.distanceKm
          : haversineKm(lat, lon, h.latitude, h.longitude);
      if (km <= maxKm) out.add(h);
    }
    out.sort((a, b) {
      final da = a.distanceKm > 0 ? a.distanceKm : haversineKm(lat, lon, a.latitude, a.longitude);
      final db = b.distanceKm > 0 ? b.distanceKm : haversineKm(lat, lon, b.latitude, b.longitude);
      return da.compareTo(db);
    });
    return out;
  }
}
