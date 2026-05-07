import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../theme/app_theme.dart';
import '../widgets/api_access_placeholder.dart';

class PatientsProvidersScreen extends StatefulWidget {
  const PatientsProvidersScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<PatientsProvidersScreen> createState() => _PatientsProvidersScreenState();
}

class _PatientsProvidersScreenState extends State<PatientsProvidersScreen> {
  late final EmrFeaturesApi _api = EmrFeaturesApi(widget.apiClient);

  late Future<dynamic> _providersF = _api.providers();
  late Future<dynamic> _patientsF = _api.patients();
  late Future<dynamic> _scheduleF = _loadSchedule();

  Future<dynamic> _loadSchedule() async {
    try {
      return await _api.allAppointments(); // staff-only
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return await _api.myAppointments(); // patient fallback
      }
      rethrow;
    }
  }

  void _reload() {
    setState(() {
      _providersF = _api.providers();
      _patientsF = _api.patients();
      _scheduleF = _loadSchedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFD32F2F),
            child: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: [
                Tab(icon: Icon(Icons.people_outline), text: 'Patients'),
                Tab(icon: Icon(Icons.badge_outlined), text: 'Physicians'),
                Tab(icon: Icon(Icons.event_note_outlined), text: 'Schedule'),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                _reload();
              },
              child: TabBarView(
                children: [
                  _PatientsTab(future: _patientsF, onRetry: _reload),
                  _ProvidersTab(future: _providersF, onRetry: _reload),
                  _ScheduleTab(future: _scheduleF, onRetry: _reload),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientsTab extends StatelessWidget {
  const _PatientsTab({required this.future, required this.onRetry});

  final Future<dynamic> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snap.hasError) {
          final e = snap.error;
          final u = ApiAccessPlaceholder.isUnauthorized(e);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.12),
              ApiAccessPlaceholder(
                title: u ? 'Sign in required' : 'Could not load patients',
                message: ApiAccessPlaceholder.shortMessage(e),
                requireSignIn: u,
                onRetry: onRetry,
              ),
            ],
          );
        }
        final data = snap.data;
        final List<dynamic> rows = data is List ? data : (data is Map ? (data['results'] ?? data['data'] ?? const []) : const []);
        if (rows.isEmpty) {
          return const Center(child: Text('No patients found'));
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final m = rows[i] is Map ? Map<String, dynamic>.from(rows[i] as Map) : <String, dynamic>{};
            final name = (m['name'] ?? m['full_name'] ?? 'Patient').toString();
            final email = (m['email'] ?? '').toString();
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(name),
                subtitle: Text(email),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProvidersTab extends StatelessWidget {
  const _ProvidersTab({required this.future, required this.onRetry});

  final Future<dynamic> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snap.hasError) {
          final e = snap.error;
          final u = ApiAccessPlaceholder.isUnauthorized(e);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.12),
              ApiAccessPlaceholder(
                title: u ? 'Sign in required' : 'Could not load physicians',
                message: ApiAccessPlaceholder.shortMessage(e),
                requireSignIn: u,
                onRetry: onRetry,
              ),
            ],
          );
        }
        final data = snap.data;
        final List<dynamic> rows = data is List ? data : (data is Map ? (data['results'] ?? data['data'] ?? const []) : const []);
        if (rows.isEmpty) {
          return const Center(child: Text('No physicians found'));
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final m = rows[i] is Map ? Map<String, dynamic>.from(rows[i] as Map) : <String, dynamic>{};
            final name = (m['full_name'] ?? m['name'] ?? 'Provider').toString();
            final email = (m['email'] ?? '').toString();
            final status = (m['status'] ?? '').toString();
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
                title: Text(name),
                subtitle: Text([email, if (status.isNotEmpty) status].join(' · ')),
              ),
            );
          },
        );
      },
    );
  }
}

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({required this.future, required this.onRetry});

  final Future<dynamic> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snap.hasError) {
          final e = snap.error;
          final u = ApiAccessPlaceholder.isUnauthorized(e);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.12),
              ApiAccessPlaceholder(
                title: u ? 'Sign in required' : 'Could not load schedule',
                message: ApiAccessPlaceholder.shortMessage(e),
                requireSignIn: u,
                onRetry: onRetry,
              ),
            ],
          );
        }

        final data = snap.data;
        final raw = data is Map ? (data['appointments'] ?? const []) : const [];
        final List<dynamic> rows = raw is List ? raw : const [];
        if (rows.isEmpty) {
          return const Center(child: Text('No appointments yet'));
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final m = rows[i] is Map ? Map<String, dynamic>.from(rows[i] as Map) : <String, dynamic>{};
            final date = (m['date'] ?? '').toString();
            final time = (m['time'] ?? '').toString();
            final patientName = (m['patient'] is Map ? (m['patient']['name'] ?? '') : '').toString();
            final providerName = (m['provider'] is Map ? (m['provider']['full_name'] ?? '') : '').toString();
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.event_note_outlined)),
                title: Text(providerName.isEmpty ? 'Doctor' : providerName),
                subtitle: Text([
                  if (patientName.isNotEmpty) 'Patient: $patientName',
                  '$date $time',
                ].join('\n')),
                isThreeLine: patientName.isNotEmpty,
              ),
            );
          },
        );
      },
    );
  }
}
