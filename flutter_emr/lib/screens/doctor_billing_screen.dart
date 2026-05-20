import 'package:flutter/material.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../theme/app_theme.dart';

class DoctorBillingScreen extends StatefulWidget {
  final EmergencyApiClient apiClient;
  const DoctorBillingScreen({super.key, required this.apiClient});

  @override
  State<DoctorBillingScreen> createState() => _DoctorBillingScreenState();
}

class _DoctorBillingScreenState extends State<DoctorBillingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = EmrFeaturesApi(widget.apiClient);
      final summaryRaw = await api.doctorBillingSummary();
      final txRaw = await api.doctorTransactions();

      final Map<String, dynamic> sBody = summaryRaw is Map
          ? Map<String, dynamic>.from(summaryRaw)
          : <String, dynamic>{};
      final Map<String, dynamic> sData = sBody['data'] is Map
          ? Map<String, dynamic>.from(sBody['data'])
          : sBody;

      final Map<String, dynamic> tBody = txRaw is Map
          ? Map<String, dynamic>.from(txRaw)
          : <String, dynamic>{};
      final Map<String, dynamic> tData = tBody['data'] is Map
          ? Map<String, dynamic>.from(tBody['data'])
          : tBody;
      final txs = ((tData['transactions'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _summary = sData;
        _transactions = txs;
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Billing'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Invoices'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverview(),
                    _buildCreateInvoice(),
                    _buildHistory(),
                  ],
                ),
    );
  }

  Widget _buildOverview() {
    final summary = _summary ?? {};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Earnings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _statRow('Total Earned', '\$${(summary['total_earned'] ?? 0).toStringAsFixed(2)}'),
                  _statRow('This Month', '\$${(summary['month_earned'] ?? 0).toStringAsFixed(2)}'),
                  _statRow('Pending', '\$${(summary['pending_amount'] ?? 0).toStringAsFixed(2)}'),
                  _statRow('Platform Fees', '\$${(summary['platform_fees'] ?? 0).toStringAsFixed(2)}'),
                  const Divider(),
                  _statRow('Transactions', '${summary['transaction_count'] ?? 0}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Payouts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if ((summary['payouts'] as List?)?.isEmpty ?? true)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No payouts yet', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ...((summary['payouts'] as List?)?.cast<Map<String, dynamic>>() ?? []).map(
                      (p) => ListTile(
                        title: Text('\$${(p['amount'] ?? 0).toStringAsFixed(2)}'),
                        subtitle: Text(p['status'] ?? ''),
                        trailing: Text(p['requested_at']?.toString().substring(0, 10) ?? ''),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _requestPayout,
                    icon: const Icon(Icons.payments),
                    label: const Text('Request Payout'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildCreateInvoice() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Create Invoice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Patient ID',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _invoicePatientId = int.tryParse(v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Amount (\$)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _invoiceAmount = double.tryParse(v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    onChanged: (v) => _invoiceNotes = v,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _invoiceBusy ? null : _submitInvoice,
                    icon: const Icon(Icons.send),
                    label: Text(_invoiceBusy ? 'Sending...' : 'Create Invoice'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? _invoicePatientId;
  double? _invoiceAmount;
  String _invoiceNotes = '';
  bool _invoiceBusy = false;

  Future<void> _submitInvoice() async {
    if (_invoicePatientId == null || _invoiceAmount == null) return;
    setState(() => _invoiceBusy = true);
    try {
      await EmrFeaturesApi(widget.apiClient).doctorCreateInvoice(
        patientId: _invoicePatientId!,
        amount: _invoiceAmount!,
        notes: _invoiceNotes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice created!')),
      );
      _load();
      _tabController.animateTo(2);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _invoiceBusy = false);
    }
  }

  Widget _buildHistory() {
    if (_transactions.isEmpty) {
      return const Center(child: Text('No transactions yet'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _transactions.length,
        itemBuilder: (ctx, i) {
          final tx = _transactions[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                tx['status'] == 'completed'
                    ? Icons.check_circle
                    : tx['status'] == 'pending'
                        ? Icons.schedule
                        : Icons.cancel,
                color: tx['status'] == 'completed'
                    ? Colors.green
                    : tx['status'] == 'pending'
                        ? Colors.orange
                        : Colors.red,
              ),
              title: Text('Dr. ${tx['provider_name'] ?? ''}'),
              subtitle: Text('Patient: ${tx['patient_name'] ?? ''}\n${tx['notes'] ?? ''}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('\$${(tx['amount'] ?? 0).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('You get: \$${(tx['provider_payout'] ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 12)),
                ],
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }

  Future<void> _requestPayout() async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Payout'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Amount (\$)',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text);
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: const Text('Request'),
          ),
        ],
      ),
    );
    if (amount == null) return;
    try {
      await EmrFeaturesApi(widget.apiClient).doctorRequestPayout(amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payout requested!')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
