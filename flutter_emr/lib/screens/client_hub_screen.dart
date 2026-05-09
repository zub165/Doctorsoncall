import 'package:flutter/material.dart';

import '../config/api_paths.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../services/offline_db.dart';
import '../services/user_api.dart';
import '../theme/app_theme.dart';
import '../utils/api_envelope.dart';
import 'package:url_launcher/url_launcher.dart';

class ClientHubScreen extends StatelessWidget {
  const ClientHubScreen({
    super.key,
    required this.apiClient,
    required this.offlineDb,
    this.onNavigateToShellTab,
  });

  final EmergencyApiClient apiClient;
  final OfflineDb offlineDb;

  /// Switch main [AppShell] tab (e.g. open Medical records).
  final ValueChanged<int>? onNavigateToShellTab;

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
                Tab(icon: Icon(Icons.home), text: 'Home'),
                Tab(icon: Icon(Icons.person), text: 'Profile'),
                Tab(icon: Icon(Icons.card_membership), text: 'Plan'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildHomeTab(context),
                _buildProfileTab(context),
                _buildPlanTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          context,
          icon: Icons.folder_shared_outlined,
          title: 'Medical records & AI',
          subtitle: 'Charts, visits, and AI-assisted summaries',
          color: const Color(0xFF673AB7),
          onTap: () => onNavigateToShellTab?.call(17),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          context,
          icon: Icons.medical_services,
          title: 'Health Overview',
          subtitle: 'Your medical summary at a glance',
          color: const Color(0xFF4CAF50),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _HealthOverviewScreen(apiClient: apiClient, offlineDb: offlineDb),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          context,
          icon: Icons.history,
          title: 'Appointment History',
          subtitle: 'View past and upcoming visits',
          color: const Color(0xFF2196F3),
          onTap: () => onNavigateToShellTab?.call(6),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          context,
          icon: Icons.receipt_long,
          title: 'Billing & Invoices',
          subtitle: 'Manage your payments',
          color: const Color(0xFF9C27B0),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _InvoicesScreen(apiClient: apiClient),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Recent Activity',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE8F5E9),
              child: Icon(Icons.check_circle, color: Color(0xFF4CAF50)),
            ),
            title: const Text('Appointment Completed'),
            subtitle: const Text('Dr. Smith - General Checkup'),
            trailing: const Text(
              '2 days ago',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE3F2FD),
              child: Icon(Icons.payment, color: Color(0xFF2196F3)),
            ),
            title: const Text('Payment Successful'),
            subtitle: const Text('Invoice #1234 - \$50.00'),
            trailing: const Text(
              '5 days ago',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTab(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: UserApi(apiClient).fetchDoctorOnCallMe(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        final data = snap.data is Map ? Map<String, dynamic>.from(snap.data as Map) : <String, dynamic>{};
        final user = (data['user'] is Map) ? Map<String, dynamic>.from(data['user'] as Map) : <String, dynamic>{};
        final patient = (data['patient'] is Map) ? Map<String, dynamic>.from(data['patient'] as Map) : <String, dynamic>{};
        final fullName = (patient['name'] ?? user['full_name'] ?? user['username'] ?? 'User').toString();
        final email = (patient['email'] ?? user['email'] ?? '').toString();
        final phone = (user['phone_number'] ?? user['phone'] ?? '').toString();
        final dob = (patient['date_of_birth'] ?? '').toString();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Color(0xFFD32F2F),
                    child: Icon(Icons.person, size: 50, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    fullName,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    email,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildInfoTile(Icons.badge, 'Full Name', fullName),
            _buildInfoTile(Icons.email, 'Email', email.isEmpty ? '—' : email),
            _buildInfoTile(Icons.phone, 'Phone', phone.isEmpty ? '—' : phone),
            _buildInfoTile(Icons.calendar_today, 'Date of Birth', dob.isEmpty ? '—' : dob),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final updated = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => _EditPatientProfileScreen(
                      apiClient: apiClient,
                      initial: {
                        'name': fullName,
                        'email': email,
                        'date_of_birth': dob,
                        'phone_number': phone,
                      },
                    ),
                  ),
                );
                // Simple refresh: re-open Profile tab will refetch data.
                if (updated == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile updated')),
                  );
                }
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Profile'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlanTab(BuildContext context) {
    return _PlanTab(apiClient: apiClient);
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFD32F2F)),
        title: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // (deprecated) old static plan card removed in favor of live billing checkout.
}

class _EditPatientProfileScreen extends StatefulWidget {
  const _EditPatientProfileScreen({required this.apiClient, required this.initial});

  final EmergencyApiClient apiClient;
  final Map<String, dynamic> initial;

  @override
  State<_EditPatientProfileScreen> createState() => _EditPatientProfileScreenState();
}

class _EditPatientProfileScreenState extends State<_EditPatientProfileScreen> {
  late final _name = TextEditingController(text: (widget.initial['name'] ?? '').toString());
  late final _email = TextEditingController(text: (widget.initial['email'] ?? '').toString());
  late final _dob = TextEditingController(text: (widget.initial['date_of_birth'] ?? '').toString());
  late final _phone = TextEditingController(text: (widget.initial['phone_number'] ?? '').toString());

  bool _saving = false;
  String? _error;
  String? _ok;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _dob.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _ok = null;
    });
    try {
      // Patient model supports: name, date_of_birth, email, etc.
      await widget.apiClient.raw.patch<dynamic>(
        ApiPaths.patientMe,
        data: {
          'name': _name.text.trim(),
          'email': _email.text.trim(),
          'date_of_birth': _dob.text.trim(),
          // phone is stored in User/Provider models; keep UI field read-only for now.
        },
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _ok = 'Saved';
      });
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name'),
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
            enabled: !_saving,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dob,
            decoration: const InputDecoration(labelText: 'Date of birth'),
            enabled: !_saving,
            // Keep validation server-side for now.
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone (view only)'),
            enabled: false,
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          if (_ok != null)
            Text(_ok!, style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _InvoicesScreen extends StatefulWidget {
  const _InvoicesScreen({required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<_InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<_InvoicesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _unwrap(dynamic data) {
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final inner = m['data'];
      final root = inner is Map ? Map<String, dynamic>.from(inner) : m;
      final list = root['invoices'] ?? root['results'] ?? root['items'];
      if (list is List) {
        return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await EmrFeaturesApi(widget.apiClient).myInvoices();
      setState(() {
        _items = _unwrap(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _items = const [];
        _loading = false;
      });
    }
  }

  Future<void> _loadFixtures() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await EmrFeaturesApi(widget.apiClient).myInvoices(fixture: true);
      setState(() {
        _items = _unwrap(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _items = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billing & invoices')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 44, color: Colors.red),
                        const SizedBox(height: 10),
                        const Text('Could not load invoices'),
                        const SizedBox(height: 8),
                        Text(_error!, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_items.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No invoices yet.',
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _loadFixtures,
                                  icon: const Icon(Icons.auto_awesome),
                                  label: const Text('Load demo invoices'),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._items.map((inv) {
                          final id = (inv['id'] ?? '').toString();
                          final amount = (inv['amount'] ?? '').toString();
                          final date = (inv['invoice_date'] ?? inv['date'] ?? '').toString();
                          final name = (inv['name'] ?? 'Invoice').toString();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFF3E5F5),
                                child: Icon(Icons.receipt_long, color: Color(0xFF9C27B0)),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text([if (id.isNotEmpty) '#$id', if (date.isNotEmpty) date].join(' • ')),
                              trailing: Text(
                                amount.isEmpty ? '—' : '\$$amount',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _PlanTab extends StatefulWidget {
  const _PlanTab({required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<_PlanTab> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _active;
  List<Map<String, dynamic>> _plans = const [];
  bool _busy = false;

  Future<void> _load({bool requestDemoSeed = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = EmrFeaturesApi(widget.apiClient);
      final plansRaw = await api.plans(fixture: requestDemoSeed);
      final billingRaw = await api.billingStatus();

      final plans = ApiEnvelope.coercePlanList(plansRaw);

      Map<String, dynamic>? active;
      if (billingRaw is Map) {
        final root = Map<String, dynamic>.from(billingRaw);
        final inner =
            root['data'] is Map ? Map<String, dynamic>.from(root['data'] as Map) : root;
        final a = inner['active'];
        if (a is Map) active = Map<String, dynamic>.from(a);
      }

      setState(() {
        _plans = plans;
        _active = active;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _loadFixtures() {
    _load(requestDemoSeed: true);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _subscribe(int planId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await EmrFeaturesApi(widget.apiClient).billingCheckout(planId);
      final body = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final inner =
          body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : body;
      final url = (inner['url'] ?? inner['checkout_url'] ?? '').toString();
      if (url.isEmpty) {
        throw Exception('Checkout URL missing (Stripe not configured).');
      }
      final uri = Uri.tryParse(url);
      if (uri == null) throw Exception('Invalid checkout URL');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.red),
              const SizedBox(height: 10),
              const Text('Plans unavailable'),
              const SizedBox(height: 8),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _loadFixtures,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Load demo plans'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final activePlan = _active?['plan'] is Map
        ? Map<String, dynamic>.from(_active!['plan'] as Map)
        : null;
    final activeName = (activePlan?['plan_name'] ?? '').toString();
    final activeStatus = (_active?['status'] ?? '').toString();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 4,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Plan',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activeName.isEmpty ? 'None' : activeName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    activeStatus.isEmpty ? 'Not subscribed' : activeStatus,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Payments are handled securely by Stripe. Apple Pay / Google Pay will appear automatically when enabled in Stripe.',
                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Available Plans',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_plans.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No plans in the Django database yet.',
                      style: TextStyle(
                        color: Colors.grey.shade900,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This list comes from GET /api/plans/ (Admin → Plans on the same server as your API). '
                      'Creating products only in Stripe does not fill this tab — add Plan rows in Django, '
                      'or use Stripe buy buttons from app settings (separate from this list).',
                      style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _load(requestDemoSeed: true),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Try load demo plans'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Demo seed only works when the API allows it (e.g. DEBUG or ALLOW_PLAN_DEMO_SEED) and the Plan table is empty.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._plans.map((p) {
              final id = int.tryParse('${p['id'] ?? ''}');
              final name = (p['plan_name'] ?? p['name'] ?? 'Plan').toString();
              final price = (p['price'] ?? '').toString();
              final duration = (p['duration'] ?? '').toString();
              final appts = (p['number_appointments'] ?? '').toString();
              final ai = (p['ai_bot'] ?? '').toString();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            price.isEmpty ? '' : '\$$price',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFD32F2F),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (duration.isNotEmpty) duration,
                          if (appts.isNotEmpty) '$appts appointments',
                          if (ai.isNotEmpty) 'AI: $ai',
                        ].join(' • '),
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: (_busy || id == null) ? null : () => _subscribe(id),
                        icon: const Icon(Icons.lock_outline),
                        label: Text(_busy ? 'Please wait…' : 'Subscribe'),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _HealthOverviewScreen extends StatefulWidget {
  const _HealthOverviewScreen({required this.apiClient, required this.offlineDb});

  final EmergencyApiClient apiClient;
  final OfflineDb offlineDb;

  @override
  State<_HealthOverviewScreen> createState() => _HealthOverviewScreenState();
}

class _HealthOverviewScreenState extends State<_HealthOverviewScreen> {
  bool _loading = true;
  String? _error;
  int _apptCount = 0;
  int _invCount = 0;
  int _vitalsCount = 0;
  int _completedPreventive = 0;
  int _pendingPreventive = 0;
  List<String> _pendingItems = const [];
  List<String> _completedItems = const [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = EmrFeaturesApi(widget.apiClient);
      final a = await api.myAppointments();
      final i = await api.myInvoices();
      final v = await api.vitals();

      int appts = 0;
      if (a is Map && a['appointments'] is List) appts = (a['appointments'] as List).length;
      if (a is Map && a['data'] is Map && (a['data']['appointments'] is List)) {
        appts = (a['data']['appointments'] as List).length;
      }
      if (a is Map && a['results'] is List) appts = (a['results'] as List).length;

      int invs = 0;
      if (i is Map && i['invoices'] is List) invs = (i['invoices'] as List).length;
      if (i is Map && i['data'] is Map && (i['data']['invoices'] is List)) {
        invs = (i['data']['invoices'] as List).length;
      }

      int vitals = 0;
      if (v is Map && v['vitals'] is List) vitals = (v['vitals'] as List).length;
      if (v is Map && v['data'] is Map && (v['data']['vitals'] is List)) {
        vitals = (v['data']['vitals'] as List).length;
      }
      if (v is Map && v['results'] is List) vitals = (v['results'] as List).length;

      final preventive = await _computePreventiveCareStatus();

      setState(() {
        _apptCount = appts;
        _invCount = invs;
        _vitalsCount = vitals;
        _completedPreventive = preventive.completedCount;
        _pendingPreventive = preventive.pendingCount;
        _pendingItems = preventive.pendingItems;
        _completedItems = preventive.completedItems;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<({
    int completedCount,
    int pendingCount,
    List<String> completedItems,
    List<String> pendingItems,
  })> _computePreventiveCareStatus() async {
    // Minimal, safe default checklist. We mark "completed" if we see matching
    // lab names in the locally-synced `lab-results` cache.
    const recommended = <String, List<String>>{
      'CBC (Complete Blood Count)': ['cbc', 'complete blood count'],
      'CMP (Comprehensive Metabolic Panel)': ['cmp', 'comprehensive metabolic'],
      'Lipid panel (Cholesterol)': ['lipid', 'cholesterol'],
      'HbA1c (Diabetes screening)': ['a1c', 'hba1c', 'hemoglobin a1c'],
    };

    final labRows = await (widget.offlineDb.select(widget.offlineDb.localLabResults)
          ..where((t) => t.isDeleted.equals(false)))
        .get();

    final allText = labRows
        .map((r) => r.json.toLowerCase())
        .join(' ');

    final completed = <String>[];
    final pending = <String>[];

    for (final entry in recommended.entries) {
      final hit = entry.value.any((k) => allText.contains(k));
      if (hit) {
        completed.add(entry.key);
      } else {
        pending.add(entry.key);
      }
    }

    return (
      completedCount: completed.length,
      pendingCount: pending.length,
      completedItems: completed,
      pendingItems: pending,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health overview')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 44, color: Colors.red),
                        const SizedBox(height: 10),
                        const Text('Could not load overview'),
                        const SizedBox(height: 8),
                        Text(_error!, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'At a glance',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 12),
                              _kv('Appointments', '$_apptCount'),
                              const SizedBox(height: 8),
                              _kv('Invoices', '$_invCount'),
                              const SizedBox(height: 8),
                              _kv('Vitals', _vitalsCount == 0 ? 'No data yet' : '$_vitalsCount entries'),
                              const SizedBox(height: 8),
                              _kv(
                                'Preventive care',
                                _pendingPreventive == 0
                                    ? 'All completed'
                                    : '$_completedPreventive completed · $_pendingPreventive pending',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_pendingItems.isNotEmpty || _completedItems.isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Preventive care (Labs)',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 10),
                                if (_pendingItems.isNotEmpty) ...[
                                  Text(
                                    'Pending',
                                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.orange.shade800,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  for (final it in _pendingItems)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.schedule, size: 18, color: Colors.orange.shade700),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(it)),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                ],
                                if (_completedItems.isNotEmpty) ...[
                                  Text(
                                    'Completed',
                                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.green.shade700,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  for (final it in _completedItems)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(it)),
                                        ],
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'This screen summarizes your account using live endpoints. '
                            'Vitals will appear once recorded (manual entry or device integration). '
                            'Preventive care uses your lab history to mark common screening labs as pending/completed.',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      children: [
        Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
