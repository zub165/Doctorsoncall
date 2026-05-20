import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/hospital.dart';
import '../services/catalog_api.dart';
import '../services/emergency_api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/api_access_placeholder.dart';
import 'hospital_detail_screen.dart';

class HospitalsListScreen extends StatefulWidget {
  const HospitalsListScreen({
    super.key,
    required this.apiClient,
    this.onNavigateToShellTab,
  });

  final EmergencyApiClient apiClient;

  /// Opens an [AppShell] drawer tab (e.g. Book appointment after viewing a hospital).
  final ValueChanged<int>? onNavigateToShellTab;

  @override
  State<HospitalsListScreen> createState() => _HospitalsListScreenState();
}

class _HospitalsListScreenState extends State<HospitalsListScreen> {
  late final EmergencyApiClient _mapsClient =
      EmergencyApiClient.maps(tokenRepository: widget.apiClient.tokenRepo);
  late final CatalogApi _api = CatalogApi(_mapsClient);
  late final CatalogApi _emrApi = CatalogApi(widget.apiClient);
  late Future<HospitalsListResult> _future;

  /// Last GPS position used for `GET …/hospitals/?lat=&lon=` (also EMR fallback).
  double? _geoLat;
  double? _geoLon;
  LatLng? _userLatLng;

  @override
  void initState() {
    super.initState();
    _future = _loadHospitals();
  }

  Future<HospitalsListResult> _loadHospitals() async {
    final pos = await _tryCurrentPosition();
    if (pos != null) {
      _geoLat = pos.latitude;
      _geoLon = pos.longitude;
      if (mounted) {
        setState(() {
          _userLatLng = LatLng(pos.latitude, pos.longitude);
        });
      }
    } else {
      _geoLat = null;
      _geoLon = null;
    }

    // Prefer Django EMR on 8012 (same host as auth, appointments, billing).
    final emr = await _emrApi.loadHospitalsList(lat: _geoLat, lon: _geoLon);
    if (emr.hospitals.isNotEmpty) return emr;
    if (emr.hasError && emr.errorMessage != null) {
      // Still try maps if EMR failed hard.
    } else if (!emr.hasError) {
      return emr;
    }

    final maps = await _api.loadHospitalsList(lat: _geoLat, lon: _geoLon);
    if (!maps.hasError && maps.hospitals.isNotEmpty) return maps;
    if (maps.needsSignIn && emr.hospitals.isEmpty && !emr.hasError) return emr;
    return emr.hasError ? emr : maps;
  }

  Future<Position?> _tryCurrentPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  String _searchQuery = '';
  /// 0=All, 1=Emergency Room, 2=Urgent Care, 3=Hospital
  int _filter = 0;

  void _reload() {
    setState(() {
      _future = _loadHospitals();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search by name, address, type…',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            onChanged: (v) =>
                setState(() => _searchQuery = v.trim().toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _choiceChip(
                label: 'All',
                selected: _filter == 0,
                icon: Icons.layers_outlined,
                onSelected: () => setState(() => _filter = 0),
              ),
              _choiceChip(
                label: 'Emergency Room',
                selected: _filter == 1,
                icon: Icons.warning_amber_rounded,
                onSelected: () => setState(() => _filter = 1),
              ),
              _choiceChip(
                label: 'Urgent Care',
                selected: _filter == 2,
                icon: Icons.local_hospital_outlined,
                onSelected: () => setState(() => _filter = 2),
              ),
              _choiceChip(
                label: 'Hospital',
                selected: _filter == 3,
                icon: Icons.local_hospital_rounded,
                onSelected: () => setState(() => _filter = 3),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              final next = _loadHospitals();
              setState(() {
                _future = next;
              });
              await next;
            },
            child: FutureBuilder<HospitalsListResult>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  );
                }
                final result = snap.data!;
                if (result.needsSignIn) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.12,
                      ),
                      ApiAccessPlaceholder(
                        title: 'Sign in for hospitals',
                        message: 'Hospital search on the maps API requires a token.',
                        requireSignIn: true,
                        onRetry: _reload,
                      ),
                    ],
                  );
                }
                if (result.hasError) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.12,
                      ),
                      ApiAccessPlaceholder(
                        title: 'Could not load hospitals',
                        message: result.errorMessage ?? 'Unknown error',
                        icon: Icons.error_outline_rounded,
                        onRetry: _reload,
                        requireSignIn: false,
                      ),
                    ],
                  );
                }
                return _HospitalsListBody(
                  theme: theme,
                  result: result,
                  filter: _filter,
                  searchQuery: _searchQuery,
                  userLocation: _userLatLng,
                  queryLat: _geoLat,
                  queryLon: _geoLon,
                  onReload: _reload,
                  onTapHospital: (h) {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => HospitalDetailScreen(
                          apiClient: widget.apiClient,
                          uuid: h.id,
                          listSnapshot: h,
                          onBookAppointment: widget.onNavigateToShellTab == null
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  widget.onNavigateToShellTab!(8);
                                },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _HospitalsListBody extends StatelessWidget {
  const _HospitalsListBody({
    required this.theme,
    required this.result,
    required this.filter,
    required this.searchQuery,
    required this.userLocation,
    this.queryLat,
    this.queryLon,
    required this.onReload,
    required this.onTapHospital,
  });

  final ThemeData theme;
  final HospitalsListResult result;
  final int filter;
  final String searchQuery;
  final LatLng? userLocation;
  final double? queryLat;
  final double? queryLon;
  final VoidCallback onReload;
  final void Function(Hospital h) onTapHospital;

  static bool _matchesFacilityFilter(Hospital h, int filter) {
    final t = h.facilityType.toLowerCase().trim();
    if (t.isEmpty) return filter == 0;
    switch (filter) {
      case 1:
        return t.contains('emergency') || t == 'er';
      case 2:
        return t.contains('urgent');
      case 3:
        return t.contains('hospital') &&
            !t.contains('emergency') &&
            !t.contains('urgent');
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    var rows = result.hospitals;

    if (filter != 0) {
      rows = rows.where((h) => _matchesFacilityFilter(h, filter)).toList();
    }

    if (searchQuery.isNotEmpty) {
      rows = rows.where((h) {
        final bucket =
            '${h.name} ${h.address} ${h.facilityType} ${h.phoneNumber ?? ''}'
                .toLowerCase();
        return bucket.contains(searchQuery);
      }).toList();
    }

    final openCount = rows.where((h) => h.isOpen).length;
    final geoBanner = result.geoNote;

    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (geoBanner != null && geoBanner.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.amber.shade900),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          geoBanner,
                          style: TextStyle(
                            color: Colors.grey.shade900,
                            height: 1.35,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _HospitalMapPreview(
            hospitals: result.hospitals,
            userLocation: userLocation,
            queryLat: queryLat,
            queryLon: queryLon,
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.12),
          Icon(
            Icons.local_hospital_outlined,
            size: 72,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No hospitals match',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            result.hospitals.isEmpty
                ? 'The list is empty or your filters excluded everything.'
                : 'Try a different search.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reload'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (geoBanner != null && geoBanner.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.amber.shade900),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        geoBanner,
                        style: TextStyle(
                          color: Colors.grey.shade900,
                          height: 1.35,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        _HospitalMapPreview(
          hospitals: rows,
          userLocation: userLocation,
          queryLat: queryLat,
          queryLon: queryLon,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 6),
          child: Row(
            children: [
              Text(
                '${rows.length} Results',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade700.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$openCount Open',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final h in rows)
          _HospitalCard(
            hospital: h,
            onTap: () => onTapHospital(h),
          ),
      ],
    );
  }
}

Widget _choiceChip({
  required String label,
  required bool selected,
  required IconData icon,
  required VoidCallback onSelected,
}) {
  final bg = selected ? AppColors.primary.withValues(alpha: 0.10) : Colors.grey.shade100;
  final fg = selected ? AppColors.primary : Colors.grey.shade700;
  return InkWell(
    onTap: onSelected,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? AppColors.primary.withValues(alpha: 0.25) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    ),
  );
}

/// OpenStreetMap tiles + pins using lat/lng from [CatalogApi.loadHospitalsList].
/// Also shows device GPS when granted, or [userLocation] from list/search context.
class _HospitalMapPreview extends StatefulWidget {
  const _HospitalMapPreview({
    required this.hospitals,
    this.userLocation,
    this.queryLat,
    this.queryLon,
  });

  final List<Hospital> hospitals;
  final LatLng? userLocation;
  final double? queryLat;
  final double? queryLon;

  @override
  State<_HospitalMapPreview> createState() => _HospitalMapPreviewState();
}

class _HospitalMapPreviewState extends State<_HospitalMapPreview> {
  final MapController _mapController = MapController();
  LatLng? _userLocation;
  bool _locAttempted = false;

  static List<Hospital> _withCoords(List<Hospital> hs) => hs
      .where((h) => h.latitude.abs() > 1e-6 || h.longitude.abs() > 1e-6)
      .toList();

  /// Prefer the device location so the map follows you (e.g. Tampa); else centroid of pins.
  static LatLng _mapCenter(List<Hospital> pts, LatLng? user) {
    if (user != null) return user;
    if (pts.isEmpty) return const LatLng(27.9506, -82.4572);
    var la = 0.0;
    var ln = 0.0;
    for (final h in pts) {
      la += h.latitude;
      ln += h.longitude;
    }
    return LatLng(la / pts.length, ln / pts.length);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Best-effort: start permission + location flow once when widget mounts.
    if (!_locAttempted) {
      _locAttempted = true;
      Future<void>(() => _loadUserLocation());
    }
  }

  Future<void> _loadUserLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(pos.latitude, pos.longitude);
      });
    } catch (_) {
      // Ignore errors; map still works with hospital pins.
    }
  }

  void _centerOnUser() {
    final p = _userLocation ?? widget.userLocation;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location not available yet. Check permissions.'),
        ),
      );
      return;
    }
    _mapController.move(p, 13);
  }

  @override
  Widget build(BuildContext context) {
    final pts = _withCoords(widget.hospitals);
    final effectiveUser = _userLocation ?? widget.userLocation;
    final center = _mapCenter(pts, effectiveUser);
    final showMap = pts.isNotEmpty || effectiveUser != null;

    if (!showMap) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: _MapPlaceholder(),
      );
    }

    final lat = widget.queryLat ?? effectiveUser?.latitude;
    final lon = widget.queryLon ?? effectiveUser?.longitude;
    final caption = lat != null && lon != null
        ? '© OSM · Near you · GET /api/hospitals/?lat=${lat.toStringAsFixed(4)}&lon=${lon.toStringAsFixed(4)}'
        : '© OpenStreetMap contributors · ${pts.length} location${pts.length == 1 ? '' : 's'} on map';

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: effectiveUser != null ? 10 : 11,
                  interactionOptions: InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  keepAlive: true,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.emergencytime.app.emergency_time',
                  ),
                  MarkerLayer(
                    markers: [
                      if (effectiveUser != null)
                        Marker(
                          point: effectiveUser,
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.my_location_rounded,
                            color: Colors.blue.shade700,
                            size: 36,
                            shadows: const [
                              Shadow(
                                blurRadius: 3,
                                offset: Offset(0, 1),
                                color: Colors.black38,
                              ),
                            ],
                          ),
                        ),
                      for (final h in pts)
                        Marker(
                          point: LatLng(h.latitude, h.longitude),
                          width: 40,
                          height: 40,
                          alignment: Alignment.bottomCenter,
                          child: Icon(
                            Icons.location_on_rounded,
                            color: AppColors.primary,
                            size: 40,
                            shadows: const [
                              Shadow(
                                blurRadius: 3,
                                offset: Offset(0, 1),
                                color: Colors.black38,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'My location',
                    onPressed: _centerOnUser,
                    icon: const Icon(Icons.my_location_rounded),
                    color: AppColors.primary,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: Colors.black.withValues(alpha: 0.5),
                  child: Text(
                    caption,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Decorative fallback when there are no coordinates or offline (no OSM tiles).
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            const Color(0xFFE53935).withValues(alpha: 0.20),
            const Color(0xFFE53935).withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: Icon(
              Icons.map_outlined,
              size: 70,
              color: Colors.red.shade300.withValues(alpha: 0.6),
            ),
          ),
          Positioned(
            left: 14,
            top: 14,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.my_location_rounded,
                color: Colors.red.shade600,
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: 14,
            child: Column(
              children: [
                _zoomButtonPlaceholder(Icons.add),
                const SizedBox(height: 10),
                _zoomButtonPlaceholder(Icons.remove),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoomButtonPlaceholder(IconData icon) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: Colors.grey.shade800),
    );
  }
}

class _HospitalCard extends StatelessWidget {
  const _HospitalCard({required this.hospital, required this.onTap});

  final Hospital hospital;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: hospital.photoUrl != null
                      ? Image.network(
                          hospital.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderIcon(),
                        )
                      : _placeholderIcon(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hospital.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hospital.address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 15,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              hospital.address,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (hospital.distanceKm > 0)
                          _chip(
                            Icons.social_distance_rounded,
                            '${hospital.distanceKm.toStringAsFixed(hospital.distanceKm < 10 ? 1 : 0)} km',
                            Colors.blue.shade700,
                          ),
                        if (hospital.waitTimeMinutes > 0)
                          _chip(
                            Icons.hourglass_top_rounded,
                            '~${hospital.waitTimeMinutes} min wait',
                            Colors.orange.shade800,
                          ),
                        if (hospital.rating > 0)
                          _chip(
                            Icons.star_rounded,
                            hospital.rating.toStringAsFixed(1),
                            Colors.amber.shade800,
                          ),
                        if (hospital.aiRating != null && hospital.aiRating! > 0)
                          _chip(
                            Icons.auto_awesome,
                            'AI ${hospital.aiRating!.toStringAsFixed(1)}',
                            AppColors.primary,
                          ),
                        _chip(
                          hospital.isOpen
                              ? Icons.check_circle_outline
                              : Icons.cancel_outlined,
                          hospital.isOpen ? 'Open' : 'Closed',
                          hospital.isOpen
                              ? Colors.green.shade800
                              : Colors.grey.shade700,
                        ),
                        _chip(
                          Icons.local_hospital_rounded,
                          hospital.facilityType.trim().isEmpty
                              ? 'Facility'
                              : hospital.facilityType,
                          Colors.purple.shade800,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return ColoredBox(
      color: AppColors.primary.withValues(alpha: 0.08),
      child: const Icon(
        Icons.local_hospital_rounded,
        color: AppColors.primary,
        size: 36,
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
