import 'package:flutter/material.dart';

import '../models/hospital.dart';
import '../services/catalog_api.dart';
import '../services/emergency_api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/api_access_placeholder.dart';

/// **`GET /api/hospitals/<uuid>/`**
class HospitalDetailScreen extends StatelessWidget {
  const HospitalDetailScreen({
    super.key,
    required this.apiClient,
    required this.uuid,
    /// Row from the hospitals list — used when detail API 404s (e.g. synthetic `h_lat_lng` id or Maps-only `place_id`).
    this.listSnapshot,
  });

  final EmergencyApiClient apiClient;
  final String uuid;

  /// Optional hospital row from list tap — avoids blank detail when server has no matching id.
  final Hospital? listSnapshot;

  @override
  Widget build(BuildContext context) {
    final mapsApi = CatalogApi(
      EmergencyApiClient.maps(tokenRepository: apiClient.tokenRepo),
    );
    final emrApi = CatalogApi(apiClient);

    return Scaffold(
      body: FutureBuilder<HospitalDetailResult>(
        future: _loadHospitalDetail(
          mapsApi: mapsApi,
          emrApi: emrApi,
          uuid: uuid,
          listSnapshot: listSnapshot,
        ),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          final result = snap.data!;
          if (result.hasError || result.hospital == null) {
            return ApiAccessPlaceholder(
              title: 'Could not load hospital',
              message: result.errorMessage ?? 'Unknown error',
              icon: Icons.local_hospital_outlined,
              onRetry: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => HospitalDetailScreen(
                      apiClient: apiClient,
                      uuid: uuid,
                      listSnapshot: listSnapshot,
                    ),
                  ),
                );
              },
            );
          }

          final h = result.hospital!;
          final raw = result.raw;
          final heroImage = h.photoUrl ?? raw['image']?.toString();
          final phone = h.phoneNumber ?? raw['phone']?.toString();
          final email = h.email ?? raw['email']?.toString();
          final description = h.description ?? raw['description']?.toString();

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    h.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primaryDark,
                              AppColors.primary,
                              Color(0xFFEF5350),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      if (heroImage != null && heroImage.startsWith('http'))
                        Image.network(
                          heroImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      const Center(
                        child: Icon(
                          Icons.local_hospital_rounded,
                          size: 72,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (h.rating > 0)
                            _metricChip(
                              Icons.star_rounded,
                              '${h.rating.toStringAsFixed(1)} rating',
                              Colors.amber.shade900,
                            ),
                          if (h.aiRating != null && h.aiRating! > 0)
                            _metricChip(
                              Icons.auto_awesome,
                              'AI ${h.aiRating!.toStringAsFixed(1)}',
                              AppColors.primary,
                            ),
                          if (h.waitTimeMinutes > 0)
                            _metricChip(
                              Icons.hourglass_top_rounded,
                              '~${h.waitTimeMinutes} min wait',
                              Colors.deepOrange,
                            ),
                          if (h.distanceKm > 0)
                            _metricChip(
                              Icons.social_distance_rounded,
                              '${h.distanceKm.toStringAsFixed(1)} km',
                              Colors.blue.shade800,
                            ),
                          _metricChip(
                            h.isOpen
                                ? Icons.check_circle_outline
                                : Icons.cancel_outlined,
                            h.isOpen ? 'Open now' : 'Closed',
                            h.isOpen
                                ? Colors.green.shade800
                                : Colors.grey.shade700,
                          ),
                          _metricChip(
                            Icons.category_rounded,
                            h.facilityType,
                            Colors.purple.shade800,
                          ),
                        ],
                      ),
                      if (h.travelTimeMinutes != null ||
                          h.trafficDelayMinutes != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Routing',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (h.travelTimeMinutes != null)
                                  Text(
                                    'Travel time ≈ ${h.travelTimeMinutes} min',
                                  ),
                                if (h.trafficDelayMinutes != null)
                                  Text(
                                    'Traffic delay ≈ ${h.trafficDelayMinutes} min',
                                  ),
                                if (h.routeType != null)
                                  Text('Route: ${h.routeType}'),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (h.address.isNotEmpty)
                        _buildInfoCard(
                          Icons.place_outlined,
                          'Address',
                          h.address,
                        ),
                      if (phone != null && phone.isNotEmpty)
                        _buildInfoCard(Icons.phone_rounded, 'Phone', phone),
                      if (email != null && email.isNotEmpty)
                        _buildInfoCard(Icons.email_outlined, 'Email', email),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'About',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.calendar_month_rounded),
                          label: const Text('Book appointment'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (phone != null && phone.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Call: $phone')),
                              );
                            },
                            icon: const Icon(Icons.phone_in_talk_rounded),
                            label: const Text('Call now'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _metricChip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide.none,
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        subtitle: SelectableText(
          value,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// Loads hospital detail: Maps API first, then EMR, then optional [listSnapshot] if APIs 404.
Future<HospitalDetailResult> _loadHospitalDetail({
  required CatalogApi mapsApi,
  required CatalogApi emrApi,
  required String uuid,
  Hospital? listSnapshot,
}) async {
  // Synthetic id when list had no server pk — show row from list only.
  if (uuid.startsWith('h_') && listSnapshot != null) {
    return HospitalDetailResult(hospital: listSnapshot, raw: const {});
  }

  var r = await mapsApi.loadHospitalDetail(uuid);
  if (!r.hasError && r.hospital != null) return r;
  if (r.needsSignIn) {
    return emrApi.loadHospitalDetail(uuid);
  }

  final r2 = await emrApi.loadHospitalDetail(uuid);
  if (!r2.hasError && r2.hospital != null) return r2;

  if (listSnapshot != null) {
    return HospitalDetailResult(hospital: listSnapshot, raw: const {});
  }

  return r2.hasError ? r2 : r;
}
