import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/medical_record.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../services/medical_records_api.dart';
import '../theme/app_theme.dart';
import '../widgets/api_access_placeholder.dart';
import '../widgets/person_avatar.dart';
import 'medical_record_detail_screen.dart';

class PatientsProvidersScreen extends StatefulWidget {
  const PatientsProvidersScreen({super.key, required this.apiClient, this.role});

  final EmergencyApiClient apiClient;
  final String? role;

  @override
  State<PatientsProvidersScreen> createState() => _PatientsProvidersScreenState();
}

class _HubData {
  const _HubData({
    required this.view,
    required this.patients,
    required this.providers,
    required this.appointments,
  });

  final String view;
  final List<Map<String, dynamic>> patients;
  final List<Map<String, dynamic>> providers;
  final List<Map<String, dynamic>> appointments;

  static _HubData empty() => const _HubData(
        view: 'guest',
        patients: [],
        providers: [],
        appointments: [],
      );

  static _HubData fromResponse(dynamic raw) {
    final root = raw is Map ? raw : const {};
    final data = root['data'] is Map ? root['data'] as Map : root;
    return _HubData(
      view: (data['view'] ?? '').toString(),
      patients: _parseList(data['patients']),
      providers: _parseList(data['providers']),
      appointments: _parseList(data['appointments']),
    );
  }

  static List<Map<String, dynamic>> _parseList(dynamic v) {
    if (v is List) {
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }
}

class _PatientsProvidersScreenState extends State<PatientsProvidersScreen>
    with SingleTickerProviderStateMixin {
  late final EmrFeaturesApi _api = EmrFeaturesApi(widget.apiClient);
  late TabController _tabController;
  late Future<_HubData> _hubF;
  final _search = TextEditingController();

  bool get _isAdmin {
    final role = (widget.role ?? '').toLowerCase().trim();
    return role == 'admin' || role == 'administrator' || role == 'staff';
  }

  bool get _isDoctor {
    final role = (widget.role ?? '').toLowerCase().trim();
    return role == 'doctor' || role == 'provider' || role == 'physician';
  }

  int get _tabCount => _isAdmin ? 3 : 2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _search.addListener(() => setState(() {}));
    _hubF = _loadHub();
  }

  @override
  void dispose() {
    _search.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<_HubData> _loadHub() async {
    try {
      final raw = await _api.patientsProviders();
      return _HubData.fromResponse(raw);
    } on DioException catch (_) {
      // Fallback: stitch lists from separate endpoints.
      final patientsRaw = await _api.patients();
      final providersRaw = await _api.providers();
      dynamic apptsRaw;
      try {
        apptsRaw = _isAdmin || _isDoctor
            ? await _api.allAppointments()
            : await _api.myAppointments();
      } catch (_) {
        apptsRaw = await _api.myAppointments();
      }
      return _HubData(
        view: _isAdmin ? 'admin' : (_isDoctor ? 'doctor' : 'patient'),
        patients: _HubData._parseList(
          patientsRaw is Map ? (patientsRaw['data'] ?? patientsRaw['results'] ?? patientsRaw) : patientsRaw,
        ),
        providers: _HubData._parseList(
          providersRaw is Map ? (providersRaw['data'] ?? providersRaw['results'] ?? providersRaw) : providersRaw,
        ),
        appointments: _HubData._parseList(
          apptsRaw is Map
              ? ((apptsRaw['appointments'] ??
                      (apptsRaw['data'] is Map ? (apptsRaw['data'] as Map)['appointments'] : null)) ??
                  const [])
              : apptsRaw,
        ),
      );
    }
  }

  void _reload() => setState(() => _hubF = _loadHub());

  List<Map<String, dynamic>> _filter(
    List<Map<String, dynamic>> rows,
    List<String> fields,
  ) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((m) {
      for (final f in fields) {
        if ((m[f] ?? '').toString().toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _isAdmin
        ? const [
            Tab(icon: Icon(Icons.people_outline), text: 'Patients'),
            Tab(icon: Icon(Icons.badge_outlined), text: 'Physicians'),
            Tab(icon: Icon(Icons.event_note_outlined), text: 'Schedule'),
          ]
        : _isDoctor
            ? const [
                Tab(icon: Icon(Icons.people_outline), text: 'My patients'),
                Tab(icon: Icon(Icons.event_note_outlined), text: 'Schedule'),
              ]
            : const [
                Tab(icon: Icon(Icons.medical_services_outlined), text: 'My doctors'),
                Tab(icon: Icon(Icons.event_note_outlined), text: 'Schedule'),
              ];

    return Column(
      children: [
        Container(
          color: const Color(0xFFD32F2F),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            isScrollable: tabs.length > 3,
            tabs: tabs,
          ),
        ),
        Expanded(
          child: FutureBuilder<_HubData>(
            future: _hubF,
            builder: (context, snap) {
              if (!snap.hasData && snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              }
              if (snap.hasError) {
                final e = snap.error;
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.12),
                    ApiAccessPlaceholder(
                      title: ApiAccessPlaceholder.isUnauthorized(e)
                          ? 'Sign in required'
                          : 'Could not load',
                      message: ApiAccessPlaceholder.shortMessage(e),
                      requireSignIn: ApiAccessPlaceholder.isUnauthorized(e),
                      onRetry: _reload,
                    ),
                  ],
                );
              }

              final hub = snap.data ?? _HubData.empty();
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => _reload(),
                child: TabBarView(
                  controller: _tabController,
                  children: _isAdmin
                      ? [
                          _PatientsList(
                            patients: _filter(hub.patients, ['name', 'email']),
                            canEdit: true,
                            api: _api,
                            apiClient: widget.apiClient,
                            openServerChart: true,
                            onReload: _reload,
                            search: _search,
                            subtitle: '${hub.patients.length} patients',
                          ),
                          _ProvidersList(
                            providers: _filter(hub.providers, ['full_name', 'email', 'speciality_name']),
                            canEdit: true,
                            api: _api,
                            onReload: _reload,
                            search: _search,
                            subtitle: '${hub.providers.length} physicians',
                          ),
                          _ScheduleList(
                            appointments: hub.appointments,
                            search: _search,
                            isPatientView: false,
                          ),
                        ]
                      : _isDoctor
                          ? [
                              _PatientsList(
                                patients: _filter(hub.patients, ['name', 'email']),
                                canEdit: false,
                                api: _api,
                                apiClient: widget.apiClient,
                                openServerChart: true,
                                onReload: _reload,
                                search: _search,
                                subtitle: '${hub.patients.length} patients linked to you',
                              ),
                              _ScheduleList(
                                appointments: hub.appointments,
                                search: _search,
                                isPatientView: false,
                              ),
                            ]
                          : [
                              _ProvidersList(
                                providers: _filter(
                                  hub.providers,
                                  ['full_name', 'email', 'speciality_name'],
                                ),
                                canEdit: false,
                                api: _api,
                                onReload: _reload,
                                search: _search,
                                subtitle: '${hub.providers.length} doctors from your bookings',
                              ),
                              _ScheduleList(
                                appointments: hub.appointments,
                                search: _search,
                                isPatientView: true,
                              ),
                            ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.controller, required this.hint, required this.subtitle});

  final TextEditingController controller;
  final String hint;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(subtitle, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PatientsList extends StatelessWidget {
  const _PatientsList({
    required this.patients,
    required this.canEdit,
    required this.api,
    required this.apiClient,
    required this.openServerChart,
    required this.onReload,
    required this.search,
    required this.subtitle,
  });

  final List<Map<String, dynamic>> patients;
  final bool canEdit;
  final EmrFeaturesApi api;
  final EmergencyApiClient apiClient;
  final bool openServerChart;
  final VoidCallback onReload;
  final TextEditingController search;
  final String subtitle;

  void _openChart(BuildContext context, Map<String, dynamic> m) {
    final pid = int.tryParse('${m['id'] ?? ''}');
    if (pid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient ID missing')),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PatientServerChartScreen(
          apiClient: apiClient,
          patientId: pid,
          patient: m,
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> m) {
    final name = (m['name'] ?? m['full_name'] ?? 'Patient').toString();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PersonAvatar(
              name: name,
              imageUrl: (m['image'] ?? '').toString(),
              size: 88,
            ),
            const SizedBox(height: 12),
            Text(name, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            if ((m['email'] ?? '').toString().isNotEmpty)
              Text((m['email'] ?? '').toString(), style: TextStyle(color: Colors.grey.shade700)),
            if ((m['profile_status'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Chip(label: Text((m['profile_status'] ?? '').toString())),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (patients.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _SearchHeader(controller: search, hint: 'Search patients…', subtitle: subtitle),
          const SizedBox(height: 40),
          const Center(child: Text('No patients yet')),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: patients.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _SearchHeader(controller: search, hint: 'Search patients…', subtitle: subtitle);
        }
        final m = patients[i - 1];
        final name = (m['name'] ?? m['full_name'] ?? 'Patient').toString();
        final email = (m['email'] ?? '').toString();
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: PersonAvatar(
              name: name,
              imageUrl: (m['image'] ?? '').toString(),
              size: 52,
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              email.isEmpty
                  ? (openServerChart ? 'Tap for server chart' : 'Tap for details')
                  : email,
            ),
            trailing: Icon(
              openServerChart ? Icons.folder_shared_outlined : Icons.chevron_right_rounded,
              color: openServerChart ? AppColors.primary : null,
            ),
            onTap: () => openServerChart ? _openChart(context, m) : _showDetail(context, m),
          ),
        );
      },
    );
  }
}

class _ProvidersList extends StatelessWidget {
  const _ProvidersList({
    required this.providers,
    required this.canEdit,
    required this.api,
    required this.onReload,
    required this.search,
    required this.subtitle,
  });

  final List<Map<String, dynamic>> providers;
  final bool canEdit;
  final EmrFeaturesApi api;
  final VoidCallback onReload;
  final TextEditingController search;
  final String subtitle;

  void _showDetail(BuildContext context, Map<String, dynamic> m) {
    final name = (m['full_name'] ?? m['name'] ?? 'Doctor').toString();
    final spec = (m['speciality_name'] ?? '').toString();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PersonAvatar(
              name: name,
              imageUrl: (m['profile_image'] ?? m['profile_picture'] ?? '').toString(),
              size: 88,
              useSpecialityStyle: true,
              specialityName: spec.isNotEmpty ? spec : name,
              specialityImageUrl: (m['speciality_image'] ?? '').toString(),
            ),
            const SizedBox(height: 12),
            Text(name, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            if (spec.isNotEmpty) Text(spec, style: TextStyle(color: Colors.grey.shade700)),
            if ((m['email'] ?? '').toString().isNotEmpty)
              Text((m['email'] ?? '').toString()),
            if ((m['consultation_fee'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Fee: ${m['consultation_fee']}'),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _SearchHeader(controller: search, hint: 'Search doctors…', subtitle: subtitle),
          const SizedBox(height: 40),
          Center(
            child: Text(
              _isPatientSubtitle(subtitle)
                  ? 'Book an appointment to see your doctors here.'
                  : 'No physicians linked yet.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: providers.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _SearchHeader(controller: search, hint: 'Search doctors…', subtitle: subtitle);
        }
        final m = providers[i - 1];
        final name = (m['full_name'] ?? m['name'] ?? 'Doctor').toString();
        final spec = (m['speciality_name'] ?? '').toString();
        final email = (m['email'] ?? '').toString();
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: PersonAvatar(
              name: name,
              imageUrl: (m['profile_image'] ?? '').toString(),
              size: 52,
              useSpecialityStyle: true,
              specialityName: spec.isNotEmpty ? spec : name,
              specialityImageUrl: (m['speciality_image'] ?? '').toString(),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [if (spec.isNotEmpty) spec, if (email.isNotEmpty) email].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showDetail(context, m),
          ),
        );
      },
    );
  }

  static bool _isPatientSubtitle(String s) => s.contains('bookings');
}

class _ScheduleList extends StatelessWidget {
  const _ScheduleList({
    required this.appointments,
    required this.search,
    required this.isPatientView,
  });

  final List<Map<String, dynamic>> appointments;
  final TextEditingController search;
  final bool isPatientView;

  String _dateKey(Map<String, dynamic> m) {
    final s = (m['date'] ?? '').toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _statusLabel(Map<String, dynamic> m) {
    final s = (m['approved'] ?? m['status'] ?? 'pending').toString().toLowerCase();
    if (s == 'approved' || s == 'yes') return 'Confirmed';
    if (s == 'rejected' || s == 'no') return 'Cancelled';
    return 'Pending';
  }

  Color _statusColor(String label) {
    switch (label) {
      case 'Confirmed':
        return Colors.green;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = search.text.trim().toLowerCase();
    final rows = appointments.where((m) {
      if (q.isEmpty) return true;
      final p = m['patient'] is Map ? (m['patient'] as Map)['name'] : '';
      final pr = m['provider'] is Map ? (m['provider'] as Map)['full_name'] : '';
      final blob = '${m['date']} ${m['time']} $p $pr'.toLowerCase();
      return blob.contains(q);
    }).toList();

    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _SearchHeader(
            controller: search,
            hint: 'Search schedule…',
            subtitle: '${appointments.length} appointments',
          ),
          const SizedBox(height: 40),
          const Center(child: Text('No visits scheduled yet')),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: rows.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _SearchHeader(
            controller: search,
            hint: 'Search schedule…',
            subtitle: '${rows.length} visit${rows.length == 1 ? '' : 's'}',
          );
        }
        final m = rows[i - 1];
        final patient = m['patient'] is Map ? Map<String, dynamic>.from(m['patient'] as Map) : <String, dynamic>{};
        final provider =
            m['provider'] is Map ? Map<String, dynamic>.from(m['provider'] as Map) : <String, dynamic>{};
        final patientName = (patient['name'] ?? patient['full_name'] ?? 'Patient').toString();
        final providerName = (provider['full_name'] ?? provider['name'] ?? 'Doctor').toString();
        final spec = (provider['speciality_name'] ?? '').toString();
        final date = _dateKey(m);
        final time = (m['time'] ?? '').toString();
        final status = _statusLabel(m);

        final sub = isPatientView
            ? [if (spec.isNotEmpty) spec, '$date · $time'].join(' · ')
            : ['Patient: $patientName', '$date · $time'].join('\n');

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isPatientView) ...[
                  PersonAvatar(
                    name: patientName,
                    imageUrl: (patient['image'] ?? '').toString(),
                    size: 44,
                  ),
                  const SizedBox(width: 8),
                ],
                PersonAvatar(
                  name: providerName,
                  imageUrl: (provider['profile_image'] ?? '').toString(),
                  size: 48,
                  useSpecialityStyle: true,
                  specialityName: spec.isNotEmpty ? spec : providerName,
                  specialityImageUrl: (provider['speciality_image'] ?? '').toString(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        providerName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(sub, style: TextStyle(color: Colors.grey.shade700, height: 1.3)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Server-side chart for one patient (not the patient's phone unless they shared/uploaded).
class PatientServerChartScreen extends StatefulWidget {
  const PatientServerChartScreen({
    super.key,
    required this.apiClient,
    required this.patientId,
    required this.patient,
  });

  final EmergencyApiClient apiClient;
  final int patientId;
  final Map<String, dynamic> patient;

  @override
  State<PatientServerChartScreen> createState() => _PatientServerChartScreenState();
}

class _PatientServerChartScreenState extends State<PatientServerChartScreen> {
  late final MedicalRecordsApi _recordsApi = MedicalRecordsApi(widget.apiClient);
  late Future<_PatientChartData> _future = _load();

  String get _patientName =>
      (widget.patient['name'] ?? widget.patient['full_name'] ?? 'Patient').toString();

  Future<_PatientChartData> _load() async {
    final records = await _recordsApi.listRecordsForPatient(widget.patientId);
    final shares = await _recordsApi.listSharesInbox(patientId: widget.patientId);
    records.sort((a, b) => b.date.compareTo(a.date));
    return _PatientChartData(records: records, shares: shares);
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chart · $_patientName'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _reload,
        child: FutureBuilder<_PatientChartData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            if (snap.hasError) {
              final e = snap.error;
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.12),
                  ApiAccessPlaceholder(
                    title: ApiAccessPlaceholder.isUnauthorized(e)
                        ? 'Sign in required'
                        : 'Could not load chart',
                    message: ApiAccessPlaceholder.shortMessage(e),
                    requireSignIn: ApiAccessPlaceholder.isUnauthorized(e),
                    onRetry: _reload,
                  ),
                ],
              );
            }
            final data = snap.data!;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.cloud_outlined, color: Colors.blue.shade800),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This chart is loaded from the EMR server for patient #${widget.patientId}. '
                            'It does not read the patient\'s phone. Device-only visit data appears here only '
                            'if the patient shared it or staff uploaded it.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    PersonAvatar(
                      name: _patientName,
                      imageUrl: (widget.patient['image'] ?? '').toString(),
                      size: 56,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _patientName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if ((widget.patient['email'] ?? '').toString().isNotEmpty)
                            Text(
                              (widget.patient['email'] ?? '').toString(),
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (data.shares.isNotEmpty) ...[
                  Text(
                    'Patient shares (consent)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final s in data.shares) _ShareCard(share: s),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Server medical records (${data.records.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                if (data.records.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No server records for this patient yet. '
                        'Ask the patient to use Share in Medical records, or upload under Advanced on Doctor visit.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                  )
                else
                  for (final r in data.records) _ServerRecordCard(record: r, api: _recordsApi),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PatientChartData {
  const _PatientChartData({required this.records, required this.shares});
  final List<MedicalRecord> records;
  final List<Map<String, dynamic>> shares;
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.share});
  final Map<String, dynamic> share;

  @override
  Widget build(BuildContext context) {
    final note = (share['patient_note'] ?? '').toString();
    final summary = (share['ai_summary'] ?? '').toString();
    final isTriage = (share['share_kind'] ?? '').toString() == 'triage';
    final vital = share['vital'] is Map ? Map<String, dynamic>.from(share['vital'] as Map) : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isTriage ? Colors.teal.shade50 : Colors.purple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isTriage ? 'Triage shared' : 'Shared with you',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (isTriage) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: const Text('Vitals'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.teal.shade100,
                  ),
                ],
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(note),
            ],
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(summary),
            ],
            if (vital != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (vital['bp_sys'] != null) 'BP ${vital['bp_sys']}/${vital['bp_dia']}',
                  if (vital['pulse_bpm'] != null) 'Pulse ${vital['pulse_bpm']}',
                  if (vital['spo2'] != null) 'SpO2 ${vital['spo2']}%',
                  if (vital['temperature_c'] != null) 'Temp ${vital['temperature_c']}°C',
                ].where((e) => e.isNotEmpty).join(' · '),
                style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServerRecordCard extends StatelessWidget {
  const _ServerRecordCard({required this.record, required this.api});
  final MedicalRecord record;
  final MedicalRecordsApi api;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: const Icon(Icons.description_outlined, color: AppColors.primary),
        title: Text(
          record.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${record.date.toIso8601String().substring(0, 10)} · Server #${record.id}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _chartLine('Summary', record.summary ?? record.notes),
                _chartLine('Presenting', record.presentingComplaints),
                _chartLine('PMH', record.pastMedicalHistory),
                _chartLine('Social', record.socialHistory),
                _chartLine('Surgical', record.surgicalHistory),
                _chartLine('Symptoms', record.symptoms.map((s) => s.name).join(', ')),
                _chartLine('Allergies', record.allergies.join(', ')),
                _chartLine(
                  'Medications',
                  record.medications
                      .map((m) => m['name'] ?? '')
                      .where((e) => e.toString().isNotEmpty)
                      .join(', '),
                ),
                _chartLine(
                  'Labs',
                  record.labs
                      .map((m) {
                        final n = m['name'] ?? '';
                        final v = m['value'] ?? '';
                        final u = m['unit'] ?? '';
                        return '$n $v $u'.trim();
                      })
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                ),
                _chartLine(
                  'Imaging',
                  record.imaging.map((m) => m['name'] ?? '').where((e) => e.isNotEmpty).join(', '),
                ),
                if (record.aiHighlight != null && record.aiHighlight!.isNotEmpty)
                  _chartLine('AI summary', record.aiHighlight!),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => MedicalRecordDetailScreen(
                            api: api,
                            recordId: record.id,
                            preview: record,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open detail'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _chartLine(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}
