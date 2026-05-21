import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import '../models/hospital.dart';
import '../services/catalog_api.dart';
import '../services/emergency_api_client.dart';
import '../theme/app_theme.dart';
import '../utils/distance_format.dart';
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

  /// Bay Area default when simulator GPS is slow/denied (matches demo catalog).
  static const _fallbackLat = 37.3327;
  static const _fallbackLon = -122.0312;

  Future<HospitalsListResult> _loadHospitals() async {
    final pos = await _tryCurrentPosition();
    var usedFallback = false;
    if (pos != null) {
      _geoLat = pos.latitude;
      _geoLon = pos.longitude;
    } else {
      _geoLat = _fallbackLat;
      _geoLon = _fallbackLon;
      usedFallback = true;
    }
    if (mounted) {
      setState(() {
        _userLatLng = LatLng(_geoLat!, _geoLon!);
      });
    }

    // Catalog tab: EMR DB only.
    if (_listSource == 0) {
      final catalog = await _emrApi.loadHospitalsList(lat: _geoLat, lon: _geoLon);
      return catalog.copyWith(
        geoNote: catalog.geoNote ??
            'Catalog · ${widget.apiClient.emrApiBaseUrl}GET hospitals/',
        apiSource: widget.apiClient.emrApiBaseUrl,
      );
    }

    // Live tab: Finder (api.mywaitime.com) first; EMR proxy if phone cannot reach Finder.
    final finderBase = ApiConfig.mapsApiBaseUrl;
    final emrBase = widget.apiClient.emrApiBaseUrl;
    final radiusM = radiusMetersForUnit(_distanceUnit);
    const liveMaxKm = 150.0;
    final type = _waitimeTypeForFilter();

    HospitalsListResult finalize(HospitalsListResult result, {String? via}) {
      if (result.needsSignIn) return result;
      if (result.hasError) return result;
      if (result.hospitals.isEmpty) return result;
      if (!result.hospitals.hasAnyNear(_geoLat!, _geoLon!, liveMaxKm)) {
        return result.copyWith(
          hospitals: const [],
          geoNote: _appendGeoNote(
            'Hospitals returned but none within ${liveMaxKm.toStringAsFixed(0)} km.',
            usedFallback,
          ),
        );
      }
      return result.copyWith(
        hospitals: _applyTypeFilter(result.hospitals),
        geoNote: _appendGeoNote(
          via ?? result.geoNote ?? 'Live hospital search',
          usedFallback,
        ),
      );
    }

    Future<HospitalsListResult> finderSearch(String searchType) =>
        _api.loadFinderHospitalSearch(
          lat: _geoLat!,
          lon: _geoLon!,
          radiusM: radiusM,
          type: searchType,
        );

    Future<HospitalsListResult> emrProxySearch(String searchType) =>
        _emrApi.loadWaitimeHospitalSearch(
          lat: _geoLat!,
          lon: _geoLon!,
          radiusM: radiusM,
          type: searchType,
        );

    Future<HospitalsListResult> loadWithFallback(String searchType) async {
      var direct = await finderSearch(searchType);
      if (!direct.hasError && direct.hospitals.isNotEmpty) {
        return finalize(
          direct,
          via: '${direct.geoNote ?? 'Finder'} · $finderBase',
        );
      }

      final proxy = await emrProxySearch(searchType);
      if (!proxy.hasError && proxy.hospitals.isNotEmpty) {
        return finalize(
          proxy,
          via:
              '${proxy.geoNote ?? 'Live search'} · $emrBase (Finder direct unreachable)',
        );
      }

      if (direct.hasError && proxy.hasError) {
        return HospitalsListResult(
          hospitals: const [],
          upstreamDegraded: true,
          errorMessage:
              'Hospital search unavailable. Finder: ${direct.errorMessage}. '
              'EMR proxy: ${proxy.errorMessage}',
          geoNote: _appendGeoNote(
            'Check $finderBase and $emrBase hospitals/search/. Pull to retry.',
            usedFallback,
          ),
          apiSource: finderBase,
        );
      }

      return direct.hasError ? proxy : direct;
    }

    var live = await loadWithFallback(type);
    if (live.hospitals.isNotEmpty) return live;

    if (type != 'emergency') {
      live = await loadWithFallback('emergency');
      if (live.hospitals.isNotEmpty) {
        return live.copyWith(
          geoNote: _appendGeoNote(
            '${live.geoNote ?? 'Live search'} · showing Emergency Room near you',
            usedFallback,
          ),
        );
      }
    }

    if (live.hasError) {
      return live.copyWith(
        upstreamDegraded: true,
        geoNote: _appendGeoNote(
          live.errorMessage ?? 'Hospital search failed. Pull to refresh.',
          usedFallback,
        ),
      );
    }

    return HospitalsListResult(
      hospitals: const [],
      geoNote: _appendGeoNote(
        'No hospitals near you for ${_filterLabel()}. Try another category or pull to refresh.',
        usedFallback,
      ),
      apiSource: finderBase,
    );
  }

  String? _appendGeoNote(String? note, bool usedFallback) {
    final loc = usedFallback
        ? 'Using default map center (enable Location for near you).'
        : null;
    if (note == null || note.isEmpty) return loc;
    if (loc == null) return note;
    return '$note · $loc';
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
          timeLimit: Duration(seconds: 10),
        ),
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw TimeoutException('location'),
      );
    } catch (_) {
      return null;
    }
  }

  String _searchQuery = '';
  /// 0=ER, 1=Urgent Care, 2=Hospital, 3=Walk-in clinic (no "All" — avoids unrelated POIs)
  int _filter = 0;
  /// 0 = EMR catalog (docsoncalls DB), 1 = live MyWaitime search
  int _listSource = 1;
  DistanceUnit _distanceUnit = DistanceUnit.km;

  String _waitimeTypeForFilter() {
    switch (_filter) {
      case 0:
        return 'emergency';
      case 1:
        return 'urgent_care';
      case 2:
        return 'general';
      case 3:
        return 'clinic';
      default:
        return 'emergency';
    }
  }

  String _filterLabel() {
    switch (_filter) {
      case 0:
        return 'Emergency Room';
      case 1:
        return 'Urgent Care';
      case 2:
        return 'Hospital';
      case 3:
        return 'Walk-in clinic';
      default:
        return 'Emergency Room';
    }
  }

  List<Hospital> _applyTypeFilter(List<Hospital> rows) {
    bool match(String facilityType, String name) {
      final blob = '${facilityType.toLowerCase()} ${name.toLowerCase()}';
      switch (_filter) {
        case 0:
          return blob.contains('emergency') || blob.contains(' er');
        case 1:
          return blob.contains('urgent');
        case 2:
          if (blob.contains('pharmacy') ||
              blob.contains('walgreens') ||
              blob.contains('cvs') ||
              blob.contains('retail')) {
            return false;
          }
          return blob.contains('hospital') && !blob.contains('urgent');
        case 3:
          return blob.contains('clinic') || blob.contains('walk');
        default:
          return blob.contains('emergency') || blob.contains(' er');
      }
    }

    return rows.where((h) => match(h.facilityType, h.name)).toList();
  }

  void _reload() {
    setState(() {
      _future = _loadHospitals();
    });
  }

  void _setFilter(int value) {
    setState(() {
      _filter = value;
      if (_listSource == 1 && _geoLat != null) {
        _future = _loadHospitals();
      }
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 1,
                      label: Text('Live search'),
                      icon: Icon(Icons.radar, size: 18),
                    ),
                    ButtonSegment(
                      value: 0,
                      label: Text('Catalog'),
                      icon: Icon(Icons.storage_outlined, size: 18),
                    ),
                  ],
                  selected: {_listSource},
                  onSelectionChanged: (s) {
                    if (s.isEmpty) return;
                    setState(() {
                      _listSource = s.first;
                      _future = _loadHospitals();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<DistanceUnit>(
                segments: const [
                  ButtonSegment(value: DistanceUnit.km, label: Text('km')),
                  ButtonSegment(value: DistanceUnit.miles, label: Text('mi')),
                ],
                selected: {_distanceUnit},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  setState(() {
                    _distanceUnit = s.first;
                    if (_listSource == 1) _future = _loadHospitals();
                  });
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _choiceChip(
                label: 'Emergency Room',
                selected: _filter == 0,
                icon: Icons.warning_amber_rounded,
                onSelected: () => _setFilter(0),
              ),
              _choiceChip(
                label: 'Urgent Care',
                selected: _filter == 1,
                icon: Icons.local_hospital_outlined,
                onSelected: () => _setFilter(1),
              ),
              _choiceChip(
                label: 'Hospital',
                selected: _filter == 2,
                icon: Icons.local_hospital_rounded,
                onSelected: () => _setFilter(2),
              ),
              _choiceChip(
                label: 'Walk-in clinic',
                selected: _filter == 3,
                icon: Icons.medical_information_outlined,
                onSelected: () => _setFilter(3),
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
                  apiClient: widget.apiClient,
                  result: result,
                  filter: _filter,
                  searchQuery: _searchQuery,
                  distanceUnit: _distanceUnit,
                  listSource: _listSource,
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
    required this.apiClient,
    required this.result,
    required this.filter,
    required this.searchQuery,
    required this.distanceUnit,
    required this.listSource,
    required this.userLocation,
    this.queryLat,
    this.queryLon,
    required this.onReload,
    required this.onTapHospital,
  });

  final ThemeData theme;
  final EmergencyApiClient apiClient;
  final HospitalsListResult result;
  final int filter;
  final String searchQuery;
  final DistanceUnit distanceUnit;
  final int listSource;
  final LatLng? userLocation;
  final double? queryLat;
  final double? queryLon;
  final VoidCallback onReload;
  final void Function(Hospital h) onTapHospital;

  static bool _matchesFacilityFilter(Hospital h, int filter) {
    final t = h.facilityType.toLowerCase().trim();
    final name = h.name.toLowerCase();
    final blob = '$t $name';
    if (t.isEmpty && name.isEmpty) return false;
    switch (filter) {
      case 0:
        return blob.contains('emergency') || blob.contains(' er');
      case 1:
        return blob.contains('urgent');
      case 2:
        if (blob.contains('pharmacy') ||
            blob.contains('walgreens') ||
            blob.contains('cvs') ||
            blob.contains('retail')) {
          return false;
        }
        return blob.contains('hospital') &&
            !blob.contains('urgent') &&
            !blob.contains('walk');
      case 3:
        return blob.contains('walk') ||
            (blob.contains('clinic') && !blob.contains('urgent'));
      default:
        return blob.contains('emergency') || blob.contains(' er');
    }
  }

  @override
  Widget build(BuildContext context) {
    var rows = result.hospitals;

    rows = rows.where((h) => _matchesFacilityFilter(h, filter)).toList();

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
    final degraded = result.upstreamDegraded;
    final bannerColor =
        degraded ? Colors.orange.shade50 : Colors.amber.shade50;
    final bannerIcon = degraded
        ? Icons.cloud_off_rounded
        : Icons.info_outline_rounded;
    final bannerIconColor =
        degraded ? Colors.orange.shade900 : Colors.amber.shade900;

    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (geoBanner != null && geoBanner.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: bannerColor,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(bannerIcon, color: bannerIconColor),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              'No hospitals match',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              result.hospitals.isEmpty
                  ? 'Try Catalog tab, pull to refresh, or enable Location in Settings.'
                  : 'Try a different filter or search.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _HospitalMapPreview(
            apiClient: apiClient,
            hospitals: result.hospitals,
            userLocation: userLocation,
            queryLat: queryLat,
            queryLon: queryLon,
            compact: true,
          ),
          const SizedBox(height: 16),
          Icon(
            Icons.local_hospital_outlined,
            size: 56,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 8),
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
              color: bannerColor,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(bannerIcon, color: bannerIconColor),
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
          apiClient: apiClient,
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
                      distanceUnit: distanceUnit,
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

/// TomTom tiles via `GET …/api/tomtom/tiles/{z}/{x}/{y}.png` (nginx → Django), else OSM fallback.
class _HospitalMapPreview extends StatefulWidget {
  const _HospitalMapPreview({
    required this.apiClient,
    required this.hospitals,
    this.userLocation,
    this.queryLat,
    this.queryLon,
    this.compact = false,
  });

  final EmergencyApiClient apiClient;
  final List<Hospital> hospitals;
  final LatLng? userLocation;
  final double? queryLat;
  final double? queryLon;
  final bool compact;

  @override
  State<_HospitalMapPreview> createState() => _HospitalMapPreviewState();
}

class _HospitalMapPreviewState extends State<_HospitalMapPreview> {
  final MapController _mapController = MapController();
  LatLng? _userLocation;
  bool _locAttempted = false;
  String? _tileUrlTemplate;
  bool _useTomTom = false;
  String? _lastMapFitKey;

  static const _osmTiles =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  void initState() {
    super.initState();
    _loadMapConfig();
  }

  Future<void> _loadMapConfig() async {
    try {
      final cfg = await CatalogApi(widget.apiClient).fetchMapConfig();
      final configured = cfg['tomtom_configured'] == true;
      final rel = (cfg['tomtom_tile_url'] ?? '').toString().trim();
      if (!configured || rel.isEmpty) return;
      final base = widget.apiClient.emrApiBaseUrl;
      final template = '$base$rel';
      if (!mounted) return;
      setState(() {
        _tileUrlTemplate = template;
        _useTomTom = true;
      });
    } catch (_) {
      // OSM fallback remains.
    }
  }

  static List<Hospital> _withCoords(List<Hospital> hs) => hs
      .where((h) => h.latitude.abs() > 1e-6 || h.longitude.abs() > 1e-6)
      .toList();

  List<Hospital> _pinsNearQuery(List<Hospital> hs) {
    final lat = widget.queryLat;
    final lon = widget.queryLon;
    if (lat == null || lon == null) return _withCoords(hs);
    return hs.nearLocation(lat, lon, 120);
  }

  void _scheduleMapFit(List<Hospital> pts, LatLng? user) {
    final key =
        '${pts.length}|${pts.map((h) => h.id).join(',')}|${user?.latitude},${user?.longitude}';
    if (key == _lastMapFitKey) return;
    _lastMapFitKey = key;
    _fitMapToPins(pts, user);
  }

  void _fitMapToPins(List<Hospital> pts, LatLng? user) {
    if (pts.isEmpty && user == null) return;
    final points = <LatLng>[
      if (user != null) user,
      for (final h in pts) LatLng(h.latitude, h.longitude),
    ];
    if (points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (points.length == 1) {
          _mapController.move(points.first, 12);
          return;
        }
        final bounds = LatLngBounds.fromPoints(points);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(48),
          ),
        );
      } catch (_) {}
    });
  }

  /// Prefer centroid of nearby pins; include user in fit, not only as center.
  static LatLng _mapCenter(List<Hospital> pts, LatLng? user) {
    if (pts.isNotEmpty) {
      var la = 0.0;
      var ln = 0.0;
      for (final h in pts) {
        la += h.latitude;
        ln += h.longitude;
      }
      return LatLng(la / pts.length, ln / pts.length);
    }
    if (user != null) return user;
    return const LatLng(27.9506, -82.4572);
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

  void _zoomIn() {
    final z = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, (z + 1).clamp(3, 18));
  }

  void _zoomOut() {
    final z = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, (z - 1).clamp(3, 18));
  }

  Widget _mapZoomButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        color: AppColors.primary,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pts = _pinsNearQuery(widget.hospitals);
    final effectiveUser = _userLocation ?? widget.userLocation;
    final center = _mapCenter(pts, effectiveUser);
    final showMap = pts.isNotEmpty || effectiveUser != null;
    _scheduleMapFit(pts, effectiveUser);

    if (!showMap) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: _MapPlaceholder(),
      );
    }

    final lat = widget.queryLat ?? effectiveUser?.latitude;
    final lon = widget.queryLon ?? effectiveUser?.longitude;
    final mapCopy = _useTomTom ? '© TomTom' : '© OpenStreetMap';
    final caption = lat != null && lon != null
        ? '$mapCopy · Pinch or +/- to zoom · Near you'
        : '$mapCopy · ${pts.length} location${pts.length == 1 ? '' : 's'} on map';

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: widget.compact ? 160 : 260,
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
                    urlTemplate: _tileUrlTemplate ?? _osmTiles,
                    userAgentPackageName: 'com.doctoroncall.emr',
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
                right: 10,
                top: 10,
                child: Column(
                  children: [
                    _mapZoomButton(Icons.add, _zoomIn),
                    const SizedBox(height: 8),
                    _mapZoomButton(Icons.remove, _zoomOut),
                  ],
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
  const _HospitalCard({
    required this.hospital,
    required this.distanceUnit,
    required this.onTap,
  });

  final Hospital hospital;
  final DistanceUnit distanceUnit;
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
                            formatDistanceKm(hospital.distanceKm, distanceUnit),
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
