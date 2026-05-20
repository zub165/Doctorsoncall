import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../theme/app_theme.dart';

class PatientBillingScreen extends StatefulWidget {
  final EmergencyApiClient apiClient;
  const PatientBillingScreen({super.key, required this.apiClient});

  @override
  State<PatientBillingScreen> createState() => _PatientBillingScreenState();
}

class _PatientBillingScreenState extends State<PatientBillingScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bills = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await EmrFeaturesApi(widget.apiClient).patientBills();
      final Map<String, dynamic> body =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final Map<String, dynamic> data =
          body['data'] is Map ? Map<String, dynamic>.from(body['data']) : body;
      final bills = ((data['bills'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _bills = bills;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _payBill(int txId) async {
    try {
      final raw = await EmrFeaturesApi(widget.apiClient).patientPayBill(txId);
      final body = raw is Map ? Map<String, dynamic>.from(raw) : {};
      final data = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : body;
      final url = (data['url'] ?? '').toString();
      if (url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bills'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
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
              : _bills.isEmpty
                  ? const Center(child: Text('No bills'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _bills.length,
                        itemBuilder: (ctx, i) {
                          final bill = _bills[i];
                          final status = (bill['status'] ?? '').toString();
                          final isPending = status == 'pending';
                          final isCompleted = status == 'completed';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        bill['provider_name'] ?? 'Doctor',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isCompleted
                                              ? Colors.green.shade100
                                              : isPending
                                                  ? Colors.orange.shade100
                                                  : Colors.red.shade100,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            color: isCompleted
                                                ? Colors.green.shade800
                                                : isPending
                                                    ? Colors.orange.shade800
                                                    : Colors.red.shade800,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Amount: \$${(bill['amount'] ?? 0).toStringAsFixed(2)}',
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                      if (bill['created_at'] != null)
                                        Text(
                                          bill['created_at'].toString().substring(0, 10),
                                          style: TextStyle(color: Colors.grey.shade600),
                                        ),
                                    ],
                                  ),
                                  if ((bill['notes'] ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(bill['notes'], style: TextStyle(color: Colors.grey.shade700)),
                                  ],
                                  if (isPending) ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () => _payBill(bill['id'] as int),
                                        icon: const Icon(Icons.lock_outline),
                                        label: const Text('Pay Now'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
