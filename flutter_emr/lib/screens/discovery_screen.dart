import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';

/// Bundles Laravel parity APIs: **countries**, **specialities**, **providers**.
class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

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
                Tab(icon: Icon(Icons.public), text: 'Countries'),
                Tab(icon: Icon(Icons.medical_services), text: 'Specialities'),
                Tab(icon: Icon(Icons.people), text: 'Providers'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildCountriesTab(),
                _buildSpecialitiesTab(),
                _buildProvidersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountriesTab() {
    return _ListTab(future: EmrFeaturesApi(apiClient).countries(), itemBuilder: (item) {
      final name = item['country_name'] ?? item['name'] ?? item['title'] ?? item['country_code'] ?? item['code'] ?? 'Unknown';
      final code = item['country_code'] ?? item['code'] ?? item['iso2'] ?? item['abbr'] ?? '';
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFD32F2F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.public, color: Color(0xFFD32F2F)),
          ),
          title: Text(name.toString()),
          subtitle: Text(code.toString()),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
    });
  }

  Widget _buildSpecialitiesTab() {
    return _ListTab(future: EmrFeaturesApi(apiClient).specialities(), itemBuilder: (item) {
      final name = item['speciality_name'] ?? item['name'] ?? item['title'] ?? 'Unknown';
      final img = item['speciality_image'] ?? item['image'] ?? item['icon'] ?? '';
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF4CAF50).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.medical_services, color: Color(0xFF4CAF50)),
          ),
          title: Text(name.toString()),
          subtitle: Text(img.toString()),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
    });
  }

  Widget _buildProvidersTab() {
    return _ListTab(future: EmrFeaturesApi(apiClient).providers(), itemBuilder: (item) {
      final fullName = (item['full_name'] ?? item['name'] ?? item['fullName'] ?? 'Provider').toString();
      final email = (item['email'] ?? '').toString();
      final status = (item['status'] ?? item['state'] ?? '').toString();
      final spec = (item['speciality_name'] ?? item['speciality'] ?? item['speciality_id'] ?? '').toString();
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF2196F3),
            child: Text(
              fullName.isEmpty ? 'P' : fullName[0].toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(fullName.isEmpty ? 'Unknown' : fullName),
          subtitle: Text([spec, email, status].where((x) => x.trim().isNotEmpty).join(' • ')),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'active' ? const Color(0xFF4CAF50).withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status.isEmpty ? 'N/A' : status,
              style: TextStyle(fontSize: 12, color: status == 'active' ? const Color(0xFF4CAF50) : Colors.grey),
            ),
          ),
        ),
      );
    });
  }
}

class _ListTab extends StatelessWidget {
  final Future<dynamic> future;
  final Widget Function(Map<String, dynamic>) itemBuilder;

  const _ListTab({required this.future, required this.itemBuilder});

  List<dynamic> _unwrapList(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return const [];

    dynamic pickList(dynamic v) {
      if (v is List) return v;
      if (v is Map) {
        final r = v['results'];
        if (r is List) return r;
        final d = v['data'];
        if (d is List) return d;
        if (d is Map) {
          final rr = d['results'];
          if (rr is List) return rr;
          final dd = d['data'];
          if (dd is List) return dd;
        }
      }
      return null;
    }

    return (pickList(data['results']) ??
            pickList(data['data']) ??
            pickList(data['items']) ??
            pickList(data['providers']) ??
            pickList(data['specialities']) ??
            pickList(data['countries']) ??
            pickList(data)) ??
        const [];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Text('Failed to load data'),
                Text(snap.error.toString(), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          );
        }
        final items = _unwrapList(snap.data);
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.inbox, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('No data available'),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index] is Map ? Map<String, dynamic>.from(items[index]) : <String, dynamic>{};
            return itemBuilder(item);
          },
        );
      },
    );
  }
}
