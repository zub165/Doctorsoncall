import 'package:flutter/material.dart';

import '../services/auth_api.dart';
import '../services/emergency_api_client.dart';
import '../services/offline_db.dart';
import '../theme/app_theme.dart';
import 'admin_hub_screen.dart';
import 'appointments_screen.dart';
import 'book_appointment_screen.dart';
import 'change_password_screen.dart';
import 'client_hub_screen.dart';
import 'courses_screen.dart';
import 'dashboard_screen.dart';
import 'discovery_screen.dart';
import 'doctor_visit_screen.dart';
import 'feedback_screen.dart';
import 'hospitals_list_screen.dart';
import 'login_screen.dart';
import 'osm_tools_screen.dart';
import 'patients_providers_screen.dart';
import 'medical_records_hub_screen.dart';
import 'provider_apply_screen.dart';
import 'replicate_token_screen.dart';
import 'ai_assistant_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.apiClient,
    required this.offlineDb,
    this.initialIndex = 0,
    this.role,
  });

  final EmergencyApiClient apiClient;
  final OfflineDb offlineDb;
  final int initialIndex;
  final String? role;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;
  final ValueNotifier<DateTime> _appointmentFocusDate = ValueNotifier<DateTime>(
    DateTime.now(),
  );

  @override
  void dispose() {
    _appointmentFocusDate.dispose();
    super.dispose();
  }

  static const _titles = <String>[
    'Dashboard',
    'Hospitals',
    'Triage',
    'Courses',
    'AI assistant',
    'Doctor notes (SOAP)',
    'Appointments',
    'Doctor visit',
    'Book appointment',
    'Countries · Specialities · Providers',
    'Patients · Providers',
    'Feedback',
    'Settings',
    'Change password',
    'Client (home · profile · plan)',
    'Provider apply',
    'Admin (CRUD parity)',
    'Medical records & AI',
  ];

  @override
  Widget build(BuildContext context) {
    final c = widget.apiClient;
    final theme = Theme.of(context);
    final role = (widget.role ?? '').toLowerCase().trim();
    final isAdmin = role == 'admin' || role == 'administrator' || role == 'staff';
    final isDoctor = role == 'doctor' || role == 'provider' || role == 'physician';
    final isPatient = !isAdmin && !isDoctor; // default

    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      drawer: Drawer(
        backgroundColor: AppColors.drawerMuted,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _DrawerHeader(theme: theme),
              _sectionLabel(context, 'Overview'),
              _tile(context, 0, Icons.dashboard_outlined, 'Dashboard'),
              const Divider(height: 1),
              _sectionLabel(context, 'Explore'),
              _tile(context, 1, Icons.local_hospital_outlined, 'Hospitals'),
              if (!isPatient) _tile(context, 2, Icons.healing_outlined, 'Triage'),
              _tile(context, 3, Icons.school_outlined, 'Courses'),
              _tile(context, 4, Icons.smart_toy_outlined, 'AI assistant'),
              if (!isPatient) _tile(context, 5, Icons.description_outlined, 'Doctor notes (SOAP)'),
              const Divider(height: 1),
              _sectionLabel(context, 'Care'),
              _tile(context, 6, Icons.event_note_outlined, 'Appointments'),
              if (!isPatient) _tile(context, 7, Icons.video_call_outlined, 'Doctor visit'),
              _tile(context, 8, Icons.add_circle_outline, 'Book appointment'),
              _tile(context, 9, Icons.explore_outlined, 'Discovery'),
              if (isAdmin || isDoctor) _tile(context, 10, Icons.link_outlined, 'Patients ↔ providers'),
              _tile(context, 11, Icons.feedback_outlined, 'Feedback'),
              const Divider(height: 1),
              _sectionLabel(context, 'Account'),
              _tile(context, 12, Icons.settings_outlined, 'Settings'),
              _tile(context, 13, Icons.password_outlined, 'Change password'),
              _tile(context, 14, Icons.person_outline, 'Client hub'),
              if (isPatient) _tile(context, 15, Icons.badge_outlined, 'Provider application'),
              if (isAdmin)
                _tile(
                  context,
                  16,
                  Icons.admin_panel_settings_outlined,
                  'Admin hub',
                ),
              _tile(
                context,
                17,
                Icons.folder_shared_outlined,
                'Medical records & AI',
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(
                    Icons.logout_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Sign out',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await AuthApi(c).logout();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                      (_) => false,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(
            apiClient: c,
            onNavigateToTab: (i) => setState(() => _index = i),
          ),
          HospitalsListScreen(apiClient: c),
          OsmToolsScreen(apiClient: c),
          CoursesScreen(apiClient: c),
          AiAssistantScreen(apiClient: c),
          DoctorSoapNoteScreen(apiClient: c),
          AppointmentsScreen(
            apiClient: c,
            onNavigateToTab: (i) => setState(() => _index = i),
            focusDate: _appointmentFocusDate,
            role: widget.role,
          ),
          DoctorVisitScreen(apiClient: c, offlineDb: widget.offlineDb),
          BookAppointmentScreen(
            apiClient: c,
            focusDate: _appointmentFocusDate,
            onBooked: () => setState(() => _index = 6),
          ),
          DiscoveryScreen(apiClient: c),
          PatientsProvidersScreen(apiClient: c, role: widget.role),
          FeedbackScreen(apiClient: c),
          SettingsScreen(apiClient: c),
          ChangePasswordScreen(apiClient: c),
          ClientHubScreen(
            apiClient: c,
            offlineDb: widget.offlineDb,
            onNavigateToShellTab: (i) => setState(() => _index = i),
          ),
          ProviderApplyScreen(apiClient: c),
          AdminHubScreen(apiClient: c),
          MedicalRecordsHubScreen(apiClient: c, role: widget.role),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, int i, IconData icon, String label) {
    final theme = Theme.of(context);
    final selected = _index == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          icon,
          color: selected
              ? AppColors.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.primary : theme.colorScheme.onSurface,
          ),
        ),
        selected: selected,
        selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () {
          setState(() => _index = i);
          Navigator.pop(context);
        },
      ),
    );
  }
}

Widget _sectionLabel(BuildContext context, String text) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.9,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary.withValues(alpha: 0.85),
        ),
      ),
    ),
  );
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.medical_services_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Doctor On Call',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'On-call care · Hospital finder',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
