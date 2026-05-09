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
import 'osm_tools_screen.dart';

class HospitalsListScreen extends StatefulWidget {
  const HospitalsListScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<HospitalsListScreen> createState() => _HospitalsListScreenState();
}

class _HospitalsListScreenState extends State<HospitalsListScreen> {
  late final EmergencyApiClient _mapsClient =
      EmergencyApiClient.maps(tokenRepository: widget.apiClient.tokenRepo);
  late final CatalogApi _api = CatalogApi(_mapsClient);
  late final CatalogApi _emrApi = CatalogApi(widget.apiClient);
  late Future<HospitalsListResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.loadHospitalsList();
  }

  String _searchQuery = '';
  int _filter = 0; // 0=All, 1=Emergency Room, 2=Urgent Care

  void _reload() {
    setState(() => _future = _api.loadHospitalsList());
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _choiceChip(
                  label: 'All',
                  selected: _filter == 0,
                  icon: Icons.layers_outlined,
                  onSelected: () => setState(() => _filter = 0),
                ),
                const SizedBox(width: 10),
                _choiceChip(
                  label: 'Emergency Room',
                  selected: _filter == 1,
                  icon: Icons.warning_amber_rounded,
                  onSelected: () => setState(() => _filter = 1),
                ),
                const SizedBox(width: 10),
                _choiceChip(
                  label: 'Urgent Care',
                  selected: _filter == 2,
                  icon: Icons.local_hospital_outlined,
                  onSelected: () => setState(() => _filter = 2),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              final next = _api.loadHospitalsList();
              setState(() => _future = next);
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
                  // Maps API can require auth; fallback to EMR hospitals list (public).
                  return FutureBuilder<HospitalsListResult>(
                    future: _emrApi.loadHospitalsList(),
                    builder: (context, fb) {
                      if (fb.connectionState != ConnectionState.done) {
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
                      final emr = fb.data;
                      if (emr == null || emr.hasError) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.15,
                            ),
                            ApiAccessPlaceholder(
                              title: 'Hospitals unavailable',
                              message:
                                  'Maps API refused guest access and EMR fallback failed.',
                              requireSignIn: false,
                              onRetry: _reload,
                              showSignInAction: false,
                              secondaryActionLabel: 'Search hospitals (guest)',
                              secondaryActionIcon: Icons.public_rounded,
                              onSecondaryAction: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => OsmToolsScreen(
                                      apiClient: widget.apiClient,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      }

                      return _HospitalsListBody(
                        theme: theme,
                        result: emr,
                        filter: _filter,
                        searchQuery: _searchQuery,
                        onReload: _reload,
                        onTapHospital: (h) {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => HospitalDetailScreen(
                                apiClient: widget.apiClient,
                                uuid: h.id,
                                listSnapshot: h,
                              ),
                            ),
                          );
                        },
                      );
                    },
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
                  onReload: _reload,
                  onTapHospital: (h) {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => HospitalDetailScreen(
                          apiClient: widget.apiClient,
                          uuid: h.id,
                          listSnapshot: h,
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
    required this.onReload,
    required this.onTapHospital,
  });

  final ThemeData theme;
  final HospitalsListResult result;
  final int filter;
  final String searchQuery;
  final VoidCallback onReload;
  final void Function(Hospital h) onTapHospital;

  @override
  Widget build(BuildContext context) {
    var rows = result.hospitals;

    if (filter == 1) {
      rows = rows
          .where(
            (h) =>
                h.facilityType.toLowerCase().contains('emergency') ||
                h.facilityType.toLowerCase().contains('er'),
          )
          .toList();
    } else if (filter == 2) {
      rows = rows
          .where((h) => h.facilityType.toLowerCase().contains('urgent'))
          .toList();
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

    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _HospitalMapPreview(hospitals: result.hospitals),
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: rows.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) return _HospitalMapPreview(hospitals: result.hospitals);
        if (i == 1) {
          return Padding(
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
          );
        }
        final h = rows[i - 2];
        return _HospitalCard(
          hospital: h,
          onTap: () => onTapHospital(h),
        );
      },
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
/// Also shows device location (if permission granted).
class _HospitalMapPreview extends StatefulWidget {
  const _HospitalMapPreview({required this.hospitals});

  final List<Hospital> hospitals;

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

  static LatLng _center(List<Hospital> pts) {
    if (pts.isEmpty) return const LatLng(37.323, -122.032);
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
    final p = _userLocation;
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
    if (pts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: _MapPlaceholder(),
      );
    }
    final center = _center(pts);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 170,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 11,
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
                      if (_userLocation != null)
                        Marker(
                          point: _userLocation!,
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                  color: Colors.black26,
                                ),
                              ],
                            ),
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
                    '© OpenStreetMap contributors · Markers: GET /api/hospitals/',
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
      height: 170,
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
                          hospital.facilityType,
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
