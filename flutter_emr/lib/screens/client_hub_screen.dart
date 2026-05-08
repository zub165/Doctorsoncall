import 'package:flutter/material.dart';

import '../config/api_paths.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../services/user_api.dart';
import '../theme/app_theme.dart';

class ClientHubScreen extends StatelessWidget {
  const ClientHubScreen({
    super.key,
    required this.apiClient,
    this.onNavigateToShellTab,
  });

  final EmergencyApiClient apiClient;

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
              builder: (_) => _HealthOverviewScreen(apiClient: apiClient),
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
    return ListView(
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
                const Text(
                  'Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '\$49/month',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Up to 15 Appointments/month',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'AI Assistant Access',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Active until Dec 31, 2026',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Available Plans',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildPlanCard(context, 'Basic', '\$5/month', 'Free', [
          '1 Visit/month',
          'Basic Support',
        ]),
        const SizedBox(height: 12),
        _buildPlanCard(context, 'Pro', '\$30/month', 'Popular', [
          '3 Visits/month',
          'Priority Support',
        ]),
        const SizedBox(height: 12),
        _buildPlanCard(context, 'Enterprise', '\$75/month', 'Best Value', [
          '7 Visits/month',
          '24/7 Support',
          'AI Features',
        ]),
      ],
    );
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

  Widget _buildPlanCard(
    BuildContext context,
    String name,
    String price,
    String badge,
    List<String> features,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: badge == 'Popular' || badge == 'Best Value'
                      ? const BoxDecoration(
                          color: Color(0xFFD32F2F),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        )
                      : null,
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      color: badge != 'Free' ? Colors.white : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              price,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD32F2F),
              ),
            ),
            const SizedBox(height: 8),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 8),
                    Text(f, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                            child: Text(
                              'No invoices yet.',
                              style: TextStyle(color: Colors.grey.shade700),
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

class _HealthOverviewScreen extends StatefulWidget {
  const _HealthOverviewScreen({required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<_HealthOverviewScreen> createState() => _HealthOverviewScreenState();
}

class _HealthOverviewScreenState extends State<_HealthOverviewScreen> {
  bool _loading = true;
  String? _error;
  int _apptCount = 0;
  int _invCount = 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = EmrFeaturesApi(widget.apiClient);
      final a = await api.myAppointments();
      final i = await api.myInvoices();

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

      setState(() {
        _apptCount = appts;
        _invCount = invs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
                              _kv('Vitals', 'Connected (stub)'),
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
                            'Vitals are currently a stub endpoint on the backend (empty list).',
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
