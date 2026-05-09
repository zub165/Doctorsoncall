import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../theme/app_theme.dart';
import '../widgets/api_access_placeholder.dart';

class PatientsProvidersScreen extends StatefulWidget {
  const PatientsProvidersScreen({super.key, required this.apiClient, this.role});

  final EmergencyApiClient apiClient;
  final String? role;

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
    final role = (widget.role ?? '').toLowerCase().trim();
    final isAdmin = role == 'admin' || role == 'administrator' || role == 'staff';
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
                  _PatientsTab(
                    future: _patientsF,
                    onRetry: _reload,
                    api: _api,
                    canEdit: isAdmin,
                  ),
                  _ProvidersTab(
                    future: _providersF,
                    onRetry: _reload,
                    api: _api,
                    canEdit: isAdmin,
                  ),
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
  const _PatientsTab({
    required this.future,
    required this.onRetry,
    required this.api,
    required this.canEdit,
  });

  final Future<dynamic> future;
  final VoidCallback onRetry;
  final EmrFeaturesApi api;
  final bool canEdit;

  int? _pickId(Map<String, dynamic> m) {
    final v = m['id'] ?? m['pk'] ?? m['patient_id'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is num) return v.toInt();
    return null;
  }

  Future<void> _editPatient(BuildContext context, Map<String, dynamic> m) async {
    final id = _pickId(m);
    if (id == null) return;
    final nameC =
        TextEditingController(text: (m['name'] ?? m['full_name'] ?? '').toString());
    final emailC =
        TextEditingController(text: (m['email'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit patient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: emailC,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final patch = <String, dynamic>{
      'name': nameC.text.trim(),
      'email': emailC.text.trim(),
    }..removeWhere((k, v) => (v as String).isEmpty);

    await api.adminPatchPatient(id, patch);
  }

  Future<void> _deletePatient(BuildContext context, Map<String, dynamic> m) async {
    final id = _pickId(m);
    if (id == null) return;
    final name = (m['name'] ?? m['full_name'] ?? 'Patient').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete patient?'),
        content: Text('Delete “$name”? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await api.adminDeletePatient(id);
  }

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
                trailing: canEdit
                    ? PopupMenuButton<String>(
                        onSelected: (v) async {
                          try {
                            if (v == 'edit') {
                              await _editPatient(context, m);
                            } else if (v == 'delete') {
                              await _deletePatient(context, m);
                            }
                            onRetry();
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Action failed: $e')),
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

class _ProvidersTab extends StatelessWidget {
  const _ProvidersTab({
    required this.future,
    required this.onRetry,
    required this.api,
    required this.canEdit,
  });

  final Future<dynamic> future;
  final VoidCallback onRetry;
  final EmrFeaturesApi api;
  final bool canEdit;

  int? _pickId(Map<String, dynamic> m) {
    final v = m['id'] ?? m['pk'] ?? m['provider_id'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is num) return v.toInt();
    return null;
  }

  Future<void> _editProvider(BuildContext context, Map<String, dynamic> m) async {
    final id = _pickId(m);
    if (id == null) return;
    final nameC = TextEditingController(
      text: (m['full_name'] ?? m['name'] ?? '').toString(),
    );
    final emailC = TextEditingController(text: (m['email'] ?? '').toString());
    final statusC = TextEditingController(text: (m['status'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit physician'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: emailC,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: statusC,
              decoration: const InputDecoration(labelText: 'Status (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final patch = <String, dynamic>{
      'full_name': nameC.text.trim(),
      'email': emailC.text.trim(),
      'status': statusC.text.trim(),
    }..removeWhere((_, v) => (v as String).isEmpty);

    await api.adminPatchProvider(id, patch);
  }

  Future<void> _deleteProvider(BuildContext context, Map<String, dynamic> m) async {
    final id = _pickId(m);
    if (id == null) return;
    final name = (m['full_name'] ?? m['name'] ?? 'Provider').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete physician?'),
        content: Text('Delete “$name”? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await api.adminDeleteProvider(id);
  }

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
                trailing: canEdit
                    ? PopupMenuButton<String>(
                        onSelected: (v) async {
                          try {
                            if (v == 'edit') {
                              await _editProvider(context, m);
                            } else if (v == 'delete') {
                              await _deleteProvider(context, m);
                            }
                            onRetry();
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Action failed: $e')),
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      )
                    : null,
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

  List<dynamic> _unwrapAppointments(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return const [];

    final root = Map<String, dynamic>.from(data);
    final d = root['data'];
    final results = root['results'];
    final appts = root['appointments'];

    if (appts is List) return appts;
    if (results is List) return results;
    if (d is List) return d;
    if (d is Map) {
      final dm = Map<String, dynamic>.from(d);
      final dappts = dm['appointments'];
      final dresults = dm['results'];
      if (dappts is List) return dappts;
      if (dresults is List) return dresults;
      final dd = dm['data'];
      if (dd is List) return dd;
      if (dd is Map) {
        final ddm = Map<String, dynamic>.from(dd);
        final ddappts = ddm['appointments'];
        final ddresults = ddm['results'];
        if (ddappts is List) return ddappts;
        if (ddresults is List) return ddresults;
      }
    }
    return const [];
  }

  ({String patient, String provider}) _namesFrom(dynamic appt) {
    if (appt is! Map) return (patient: '', provider: '');
    final m = Map<String, dynamic>.from(appt);

    String pickPatient() {
      final p = m['patient'];
      if (p is Map) {
        final pm = Map<String, dynamic>.from(p);
        return (pm['name'] ?? pm['full_name'] ?? pm['fullName'] ?? '').toString();
      }
      return (m['patient_name'] ?? m['patientName'] ?? m['patient_full_name'] ?? '').toString();
    }

    String pickProvider() {
      final p = m['provider'] ?? m['doctor'];
      if (p is Map) {
        final pm = Map<String, dynamic>.from(p);
        return (pm['full_name'] ?? pm['name'] ?? pm['fullName'] ?? '').toString();
      }
      return (m['provider_name'] ?? m['doctor_name'] ?? m['providerName'] ?? '').toString();
    }

    return (patient: pickPatient().trim(), provider: pickProvider().trim());
  }

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
        final rows = _unwrapAppointments(data);
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
            final names = _namesFrom(m);
            final patientName = names.patient;
            final providerName = names.provider;
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
