import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/emergency_api_client.dart';
import '../theme/app_theme.dart';
import '../services/health_api.dart';
import '../services/user_api.dart';
import 'login_screen.dart';

/// Overview: **`GET /api/user-data/`**, **`GET /api/health/`**, quick links to modules.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.apiClient,
    this.onNavigateToTab,
  });

  final EmergencyApiClient apiClient;

  /// Opens [AppShell] drawer destinations by index (matches `_titles` order).
  final ValueChanged<int>? onNavigateToTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _profileInner;
  bool _guest = false;
  Map<String, dynamic>? _health;
  String? _loadError;

  bool get _ready => _profileInner != null || _loadError != null;

  @override
  void initState() {
    super.initState();
    HealthApi(widget.apiClient)
        .check()
        .then((data) {
          if (mounted) setState(() => _health = data);
        })
        .catchError((_) {});
    _loadProfile();
  }

  String _profileTitle(Map<String, dynamic> p) {
    final composed = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    if (composed.isNotEmpty) return composed;
    return p['full_name']?.toString() ??
        p['username']?.toString() ??
        p['email']?.toString() ??
        'User';
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loadError = null;
      _profileInner = null;
      _guest = false;
    });

    try {
      final api = UserApi(widget.apiClient);
      final envelope = await api.fetchUserDataEnvelope();
      final inner = UserApi.unwrapData(envelope);
      final authenticated = inner['is_authenticated'] == true;
      if (!mounted) return;
      setState(() {
        _profileInner = inner;
        _guest = !authenticated;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _profileInner = null;
        _guest = false;
        _loadError = e.response?.statusCode == 401
            ? 'Unauthorized (check Token header)'
            : (e.message ?? 'Failed to load ${ApiConfig.userMePath}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_ready) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.dashboard_customize_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading your dashboard…',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          LoginScreen(apiClientOverride: widget.apiClient),
                    ),
                  );
                },
                child: const Text('Back to login'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Welcome header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.emergency_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Doctor On Call',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_guest)
                      Chip(
                        label: const Text(
                          'Guest',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _guest
                      ? 'Welcome — browse as guest'
                      : 'Welcome back, ${_profileTitle(_profileInner ?? {})}!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
                if ((_profileInner?['email'] ?? '') != '') ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_profileInner!['email']}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Quick Stats
          Text(
            'Quick Overview',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  theme,
                  Icons.calendar_today,
                  'Appointments',
                  '0',
                  const Color(0xFF4CAF50),
                  onTap: () => widget.onNavigateToTab?.call(6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  theme,
                  Icons.local_hospital,
                  'Hospitals',
                  '0',
                  const Color(0xFF2196F3),
                  onTap: () => widget.onNavigateToTab?.call(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  theme,
                  Icons.people,
                  'Providers',
                  '0',
                  const Color(0xFF9C27B0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  theme,
                  Icons.medical_services,
                  'System',
                  _health != null ? 'OK' : 'Check',
                  const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Quick Actions
          Text(
            'Quick Actions',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildQuickActions(context),
          const SizedBox(height: 24),

          // Info card
          if (_health != null && _health!.isNotEmpty) ...[
            Card(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'System Healthy',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'API is reachable',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                Icons.add_circle,
                'Book Appt',
                () => widget.onNavigateToTab?.call(8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                Icons.local_hospital,
                'Hospitals',
                () => widget.onNavigateToTab?.call(1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                Icons.event_note,
                'My Appts',
                () => widget.onNavigateToTab?.call(6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                Icons.feedback,
                'Feedback',
                () => widget.onNavigateToTab?.call(11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                Icons.folder_shared_outlined,
                'Medical records',
                () => widget.onNavigateToTab?.call(17),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                Icons.psychology_outlined,
                'AI assistant',
                () => widget.onNavigateToTab?.call(17),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
