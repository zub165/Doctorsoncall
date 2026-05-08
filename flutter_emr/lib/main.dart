import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'theme/app_theme.dart' show AppColors, buildAppTheme;
import 'screens/login_screen.dart';
import 'services/emergency_api_client.dart';
import 'services/offline_db.dart';
import 'services/sync_service.dart';
import 'services/token_repository.dart';
import 'services/user_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DoctorOnCallApp());
}

class DoctorOnCallApp extends StatelessWidget {
  const DoctorOnCallApp({super.key, this.offlineDbFactory});

  /// Optional override to construct the offline database.
  /// Keep `null` in widget tests to avoid background isolates/timers.
  final OfflineDb Function()? offlineDbFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doctor On Call',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _SessionGate(offlineDbFactory: offlineDbFactory),
    );
  }
}

/// Routes to [AppShell] when a saved DRF `Token` exists.
class _SessionGate extends StatefulWidget {
  const _SessionGate({this.offlineDbFactory});

  final OfflineDb Function()? offlineDbFactory;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late final Future<({EmergencyApiClient client, String? token, String? role})>
      _boot;
  OfflineDb? _offlineDb;

  @override
  void initState() {
    super.initState();
    _boot = () async {
      final repo = TokenRepository();
      final token = await repo.readToken();
      final client = EmergencyApiClient(tokenRepository: repo);
      String? role;
      if (token != null && token.isNotEmpty) {
        try {
          final me = await UserApi(client).fetchDoctorOnCallMe();
          role = (me['role'] ?? me['portal'] ?? me['user_role'])
              ?.toString()
              .toLowerCase()
              .trim();

          // Best-effort background sync on app start (safe when offline).
          final mkDb = widget.offlineDbFactory ?? () => OfflineDb();
          _offlineDb ??= mkDb();
          await SyncService(client: client, db: _offlineDb!).syncAll();
        } catch (_) {
          role = null;
        }
      }
      return (client: client, token: token, role: role);
    }();
  }

  @override
  void dispose() {
    _offlineDb?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({EmergencyApiClient client, String? token, String? role})>(
      future: _boot,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(
            backgroundColor: AppColors.surfaceWarm,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.emergency_rounded,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
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
                    'Loading Doctor On Call…',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final data = snap.requireData;
        if (data.token != null && data.token!.isNotEmpty) {
          final role = (data.role ?? '').toLowerCase();
          // Minimal role routing: Admins land on Admin hub, Doctors on Appointments.
          final initialIndex = role == 'admin' || role == 'administrator' || role == 'staff'
              ? 16
              : (role == 'doctor' ? 6 : 0);
          return AppShell(
            apiClient: data.client,
            initialIndex: initialIndex,
            role: role,
          );
        }
        return LoginScreen(apiClientOverride: data.client);
      },
    );
  }
}
