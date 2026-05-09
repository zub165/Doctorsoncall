import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../config/api_paths.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../theme/app_theme.dart';
import 'admin_hub_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<_ConnState> _f = _load();

  Future<_ConnState> _load() async {
    final c = widget.apiClient;
    final api = EmrFeaturesApi(c);

    final emrBaseUrl = ApiConfig.emrApiBaseUrl;
    final mapsBaseUrl = ApiConfig.mapsApiBaseUrl;
    final userMePath = ApiConfig.userMePath;

    bool healthOk = false;
    bool meOk = false;
    String role = 'unknown';
    bool replicateConfigured = false;
    String replicateMsg = '';

    try {
      final r = await c.raw.get<dynamic>(ApiPaths.health);
      healthOk = (r.statusCode ?? 0) >= 200 && (r.statusCode ?? 0) < 300;
    } catch (_) {
      healthOk = false;
    }

    try {
      final r = await c.raw.get<dynamic>(ApiPaths.docOnCallMe);
      final body = r.data;
      Map<String, dynamic> m = {};
      if (body is Map) {
        final data = body['data'];
        if (data is Map) {
          m = Map<String, dynamic>.from(data);
        } else {
          m = Map<String, dynamic>.from(body);
        }
      }
      meOk = true;
      role = (m['role'] ?? 'unknown').toString();
    } catch (_) {
      meOk = false;
    }

    try {
      final res = await api.replicateToken();
      final root = res is Map ? res : const {};
      replicateConfigured = (root['configured'] == true) ||
          ((root['data'] is Map) && ((root['data']['configured'] ?? false) == true));
      replicateMsg = (root['message'] ??
              (root['data'] is Map ? root['data']['message'] : null) ??
              '')
          .toString();
    } catch (e) {
      replicateConfigured = false;
      replicateMsg = e.toString();
    }

    return _ConnState(
      emrBaseUrl: emrBaseUrl,
      mapsBaseUrl: mapsBaseUrl,
      userMePath: userMePath,
      healthOk: healthOk,
      meOk: meOk,
      role: role,
      replicateConfigured: replicateConfigured,
      replicateMessage: replicateMsg,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final f = _load();
        setState(() {
          _f = f;
        });
        await f;
      },
      child: FutureBuilder<_ConnState>(
        future: _f,
        builder: (context, snap) {
          if (!snap.hasData && snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [Text('Failed: ${snap.error}')],
            );
          }
          final s = snap.data!;
          final showAdminHub = _isStaffRole(s.role);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'API connections',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              _kvCard('EMR API base URL', s.emrBaseUrl),
              _kvCard('Maps API base URL', s.mapsBaseUrl),
              _kvCard('User profile path', s.userMePath),
              const SizedBox(height: 12),
              _statusCard(
                title: 'Backend health',
                ok: s.healthOk,
                okText: 'Connected',
                badText: 'Not reachable',
              ),
              _statusCard(
                title: 'Role endpoint',
                ok: s.meOk,
                okText: 'OK (role: ${s.role})',
                badText: 'Failed',
              ),
              _statusCard(
                title: 'AI provider (Replicate)',
                ok: s.replicateConfigured,
                okText: 'Configured',
                badText: 'Not configured',
                subtitle: s.replicateMessage.isEmpty ? null : s.replicateMessage,
              ),
              if (showAdminHub) ...[
                const SizedBox(height: 24),
                Text(
                  'Administration',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    title: const Text(
                      'Admin hub',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Pending approvals, providers, patients, appointments',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              AdminHubScreen(apiClient: widget.apiClient),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Pull down to refresh status.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Matches `GET /api/doctor-on-call/me/` role values used by the backend.
  bool _isStaffRole(String role) {
    final r = role.toLowerCase().trim();
    return r == 'admin' ||
        r == 'administrator' ||
        r == 'staff' ||
        r.contains('admin');
  }

  Widget _kvCard(String k, String v) {
    return Card(
      child: ListTile(
        title: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: SelectableText(v),
      ),
    );
  }

  Widget _statusCard({
    required String title,
    required bool ok,
    required String okText,
    required String badText,
    String? subtitle,
  }) {
    final color = ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Card(
      child: ListTile(
        leading: Icon(ok ? Icons.check_circle_outline : Icons.error_outline, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([ok ? okText : badText, if (subtitle != null) subtitle].join('\n')),
      ),
    );
  }
}

class _ConnState {
  _ConnState({
    required this.emrBaseUrl,
    required this.mapsBaseUrl,
    required this.userMePath,
    required this.healthOk,
    required this.meOk,
    required this.role,
    required this.replicateConfigured,
    required this.replicateMessage,
  });

  final String emrBaseUrl;
  final String mapsBaseUrl;
  final String userMePath;
  final bool healthOk;
  final bool meOk;
  final String role;
  final bool replicateConfigured;
  final String replicateMessage;
}
