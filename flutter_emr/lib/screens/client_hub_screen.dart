import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/api_paths.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../services/offline_db.dart';
import '../services/store_purchase_service.dart';
import '../services/user_api.dart';
import '../theme/app_theme.dart';
import '../models/billing.dart';
import '../utils/api_envelope.dart';
import 'package:url_launcher/url_launcher.dart';
import 'patient_billing_screen.dart';
import 'provider_apply_screen.dart';

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
          title: 'Doctor bills & pay',
          subtitle: 'Pay extra visits & doctor invoices (Stripe — not monthly plan)',
          color: const Color(0xFF9C27B0),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PatientBillingScreen(apiClient: apiClient),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          context,
          icon: Icons.description_outlined,
          title: 'Legacy invoices',
          subtitle: 'Older invoice list from EMR',
          color: const Color(0xFF7E57C2),
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
    return _PlanTab(
      apiClient: apiClient,
      onNavigateToShellTab: onNavigateToShellTab,
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
  const _PlanTab({
    required this.apiClient,
    this.onNavigateToShellTab,
  });

  final EmergencyApiClient apiClient;
  final ValueChanged<int>? onNavigateToShellTab;

  @override
  State<_PlanTab> createState() => _PlanTabState();
}

String _friendlyPlanLoadError(Object e) {
  final msg = e.toString();
  if (msg.contains('501')) {
    return 'Subscription billing is not configured on the server yet. '
        'You can still browse plans below once they load from the API.';
  }
  if (msg.contains('403')) {
    return 'You do not have permission to load plans. Sign in as a patient account.';
  }
  return 'Could not load plans from the server. Check your connection and try again.';
}

String _friendlyBillingError(Object e) {
  final msg = e.toString();
  if (msg.contains('501')) {
    return 'Stripe billing is not enabled on the server. Plan list is shown; '
        'subscribe via App Store / Google Play on mobile.';
  }
  return 'Could not load your current subscription status.';
}

String _planBenefitLine(String appts) {
  final n = appts.trim().toLowerCase();
  if (n == '1') {
    return '1 covered visit/month · book available doctors online';
  }
  if (n == '3') {
    return '3 covered visits/month · available doctors on the platform';
  }
  if (n == '5') {
    return '5 covered visits/month · available doctors on the platform';
  }
  if (appts.isNotEmpty) {
    return '$appts covered visits/month · available doctors online';
  }
  return 'Book available doctors on Docs On Call';
}

class _PlanTabState extends State<_PlanTab> {
  bool _loading = true;
  String? _error;
  String? _billingNotice;
  Map<String, dynamic>? _active;
  VisitAllowance? _visitAllowance;
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
      final plans = ApiEnvelope.coercePlanList(plansRaw);

      Map<String, dynamic>? active;
      VisitAllowance? allowance;
      String? billingWarning;
      try {
        final billing = await api.fetchBillingStatus();
        active = billing.activeSubscription;
        allowance = billing.visitAllowance;
      } catch (e) {
        billingWarning = _friendlyBillingError(e);
      }

      setState(() {
        _plans = plans;
        _active = active;
        _visitAllowance = allowance;
        _billingNotice = billingWarning;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = _friendlyPlanLoadError(e);
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

  bool get _useStoreSubscription => StorePurchaseService.isSupported;

  String get _subscribeButtonLabel {
    if (Platform.isIOS) return 'Subscribe with App Store';
    if (Platform.isAndroid) return 'Subscribe with Google Play';
    return 'Subscribe in app store';
  }

  void _showPlanSnack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? null : const Color(0xFF4CAF50),
      ),
    );
  }

  Future<void> _restoreStorePurchases() async {
    if (!_useStoreSubscription) {
      _showPlanSnack('In-app purchase is only on iOS and Android.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = EmrFeaturesApi(widget.apiClient);
      final restored = await StorePurchaseService.instance.restorePurchases();
      if (restored.isEmpty) {
        _showPlanSnack('No purchases to restore in ${StorePurchaseService.storeName}.');
        return;
      }
      for (final purchase in restored) {
        if (!purchase.success) continue;
        final plan = _planForProductId(purchase.productId);
        if (plan == null) continue;
        final id = plan['id'];
        if (id is! int) continue;
        await api.billingVerifyStore(
          planId: id,
          platform: Platform.isIOS ? 'apple' : 'android',
          productId: purchase.productId,
          purchaseId: purchase.purchaseId,
          verificationData: purchase.verificationData,
          localVerificationData: purchase.localVerificationData,
          transactionDate: purchase.transactionDate,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchases restored — plan updated'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showPlanSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic>? _planForProductId(String productId) {
    for (final p in _plans) {
      if ((p['revenuecat_product_id'] ?? '').toString() == productId) {
        return p;
      }
    }
    return null;
  }

  Future<void> _subscribe(int planId, Map<String, dynamic> planRow) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = EmrFeaturesApi(widget.apiClient);

      if (kIsWeb) {
        final res = await api.billingCheckout(planId, platform: 'web');
        final body = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
        final inner = body['data'] is Map
            ? Map<String, dynamic>.from(body['data'] as Map)
            : body;
        final url = (inner['url'] ?? inner['checkout_url'] ?? '').toString();
        if (url.isEmpty) {
          throw Exception('Stripe web checkout is not configured on the server.');
        }
        final uri = Uri.tryParse(url);
        if (uri == null) throw Exception('Invalid checkout URL');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }

      if (!_useStoreSubscription) {
        throw Exception(
          'Monthly plans on mobile use ${StorePurchaseService.storeName} only. '
          'Extra visits: Doctor bills (Stripe).',
        );
      }

      final platform = Platform.isIOS ? 'apple' : 'android';
      var productId = (planRow['revenuecat_product_id'] ?? '').toString().trim();
      if (productId.isEmpty) {
        final res = await api.billingCheckout(planId, platform: platform);
        final body = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
        final inner = body['data'] is Map
            ? Map<String, dynamic>.from(body['data'] as Map)
            : body;
        productId = (inner['product_id'] ?? '').toString();
      }
      if (productId.isEmpty) {
        throw Exception(
          'Plan has no store product id (doc_basic_monthly, etc.). Set in Admin → Plans.',
        );
      }

      final purchase = await StorePurchaseService.instance.purchaseProductId(productId);
      if (!purchase.success) {
        throw Exception(purchase.error ?? 'Purchase failed');
      }

      await api.billingVerifyStore(
        planId: planId,
        platform: platform,
        productId: purchase.productId,
        purchaseId: purchase.purchaseId,
        verificationData: purchase.verificationData,
        localVerificationData: purchase.localVerificationData,
        transactionDate: purchase.transactionDate,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Subscribed via ${StorePurchaseService.storeName}. Plan is active.',
          ),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showPlanSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openExtraVisitBilling() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PatientBillingScreen(apiClient: widget.apiClient),
      ),
    );
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
          if (_billingNotice != null)
            Card(
              color: Colors.orange.shade50,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _billingNotice!,
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_visitAllowance != null)
            VisitAllowanceCard(allowance: _visitAllowance!),
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
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.subscriptions, color: Colors.blue.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Monthly plans (3 tiers)',
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _useStoreSubscription
                        ? 'Basic (1), Gold (3), and Premium (5) visits/month — billed through '
                            '${StorePurchaseService.storeName} (direct, no RevenueCat). '
                            'Extra visits use Stripe in Doctor bills.'
                        : 'Monthly plans require iOS or Android.',
                    style: TextStyle(color: Colors.blue.shade900, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.green.shade50,
            child: ListTile(
              leading: Icon(Icons.people_outline, color: Colors.green.shade800),
              title: Text(
                'Available doctors',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.green.shade900,
                ),
              ),
              subtitle: Text(
                'Browse verified providers by country and speciality in Discovery, '
                'then book a video visit. Some doctors also offer volunteer online care.',
                style: TextStyle(color: Colors.green.shade900, height: 1.3),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onNavigateToShellTab == null
                  ? null
                  : () => widget.onNavigateToShellTab!.call(9),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.teal.shade50,
            child: ListTile(
              leading: Icon(Icons.medical_services_outlined, color: Colors.teal.shade800),
              title: Text(
                'Are you a doctor?',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.teal.shade900,
                ),
              ),
              subtitle: Text(
                'Join our platform for patient reach and paid telehealth. '
                'You can also opt in to volunteer online visits when you apply.',
                style: TextStyle(color: Colors.teal.shade900, height: 1.3),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProviderApplyScreen(apiClient: widget.apiClient),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long, color: Color(0xFF9C27B0)),
              title: const Text('Extra visits & doctor bills'),
              subtitle: const Text(
                'When your plan visits are used up, pay one-time consultation '
                'invoices with Stripe (card) — not for monthly plans.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _openExtraVisitBilling,
            ),
          ),
          if (_useStoreSubscription) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restoreStorePurchases,
              icon: const Icon(Icons.restore),
              label: const Text('Restore App Store / Play purchases'),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Subscribe (Basic · Gold · Premium)',
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
                        _planBenefitLine(appts),
                        style: TextStyle(color: Colors.grey.shade700, height: 1.3),
                      ),
                      if (duration.isNotEmpty || ai.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            [
                              if (duration.isNotEmpty) duration,
                              if (ai.isNotEmpty) 'AI: $ai',
                            ].join(' • '),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if ((p['revenuecat_product_id'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Store product: ${p['revenuecat_product_id']}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: (_busy || id == null || !_useStoreSubscription)
                            ? null
                            : () => _subscribe(id, p),
                        icon: Icon(
                          Platform.isIOS
                              ? Icons.apple
                              : Platform.isAndroid
                                  ? Icons.shop
                                  : Icons.storefront,
                        ),
                        label: Text(
                          _busy
                              ? 'Please wait…'
                              : !_useStoreSubscription
                                  ? 'App Store / Play only on mobile'
                                  : _subscribeButtonLabel,
                        ),
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

      var preventive = (
        completedCount: 0,
        pendingCount: 4,
        completedItems: <String>[],
        pendingItems: const [
          'CBC (Complete Blood Count)',
          'CMP (Comprehensive Metabolic Panel)',
          'Lipid panel (Cholesterol)',
          'HbA1c (Diabetes screening)',
        ],
      );
      try {
        preventive = await _computePreventiveCareStatus();
      } catch (_) {
        // Local lab cache unavailable (e.g. drift isolate closed after hot restart).
      }

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

    final db = await OfflineDb.instanceOrReset();
    final labRows = await (db.select(db.localLabResults)
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
