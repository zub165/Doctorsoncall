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
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFD32F2F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.public, color: Color(0xFFD32F2F)),
          ),
          title: Text(item['country_name'] ?? item['country_code'] ?? 'Unknown'),
          subtitle: Text(item['country_code'] ?? ''),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
    });
  }

  Widget _buildSpecialitiesTab() {
    return _ListTab(future: EmrFeaturesApi(apiClient).specialities(), itemBuilder: (item) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF4CAF50).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.medical_services, color: Color(0xFF4CAF50)),
          ),
          title: Text(item['speciality_name'] ?? 'Unknown'),
          subtitle: Text(item['speciality_image'] ?? ''),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
    });
  }

  Widget _buildProvidersTab() {
    return _ListTab(future: EmrFeaturesApi(apiClient).providers(), itemBuilder: (item) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF2196F3),
            child: Text(
              (item['full_name'] ?? 'P')[0].toString().toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(item['full_name'] ?? 'Unknown'),
          subtitle: Text('${item['speciality_id']} • ${item['status'] ?? 'N/A'}'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: item['status'] == 'active' ? const Color(0xFF4CAF50).withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              item['status'] ?? 'N/A',
              style: TextStyle(fontSize: 12, color: item['status'] == 'active' ? const Color(0xFF4CAF50) : Colors.grey),
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
        final data = snap.data;
        List<dynamic> items = [];
        if (data is Map) {
          items = data['results'] ?? data['data'] ?? data['providers'] ?? data['specialities'] ?? data['countries'] ?? [];
        } else if (data is List) {
          items = data;
        }
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
