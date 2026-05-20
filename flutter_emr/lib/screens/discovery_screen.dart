import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../widgets/country_flag.dart';
import '../widgets/speciality_avatar.dart';
import '../services/emr_features_api.dart';
import '../theme/app_theme.dart';

void _showDiscoveryDetailSheet(
  BuildContext context,
  String title,
  Map<String, dynamic> item,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final lines = item.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.42,
        minChildSize: 0.22,
        maxChildSize: 0.92,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text(
              title,
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            SelectableText(lines.isEmpty ? '(no fields)' : lines),
          ],
        ),
      );
    },
  );
}

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
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, Color(0xFFE57373)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              tabs: const [
                Tab(icon: Icon(Icons.public, size: 20), text: 'Countries'),
                Tab(icon: Icon(Icons.medical_services, size: 20), text: 'Specialities'),
                Tab(icon: Icon(Icons.people, size: 20), text: 'Providers'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _CountriesTab(apiClient: apiClient),
                _buildSpecialitiesTab(context),
                _buildProvidersTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialitiesTab(BuildContext context) {
    return _ListTab(future: EmrFeaturesApi(apiClient).specialities(), itemBuilder: (item) {
      final name = (item['speciality_name'] ?? item['name'] ?? item['title'] ?? 'Unknown').toString();
      final img = (item['speciality_image'] ?? item['image'] ?? item['icon'] ?? '').toString();
      final country = (item['country_name'] ?? '').toString();
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: () => _showDiscoveryDetailSheet(context, name, item),
          leading: SpecialityAvatar(
            name: name,
            imageUrl: img,
            size: 48,
            radius: 12,
            onlineFallback: false,
          ),
          title: Text(name),
          subtitle: Text(country.isNotEmpty ? country : 'Medical specialty'),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
    });
  }

  Widget _buildProvidersTab(BuildContext context) {
    return _ListTab(future: EmrFeaturesApi(apiClient).providers(), itemBuilder: (item) {
      final fullName = (item['full_name'] ?? item['name'] ?? item['fullName'] ?? 'Provider').toString();
      final email = (item['email'] ?? '').toString();
      final status = (item['status'] ?? item['state'] ?? '').toString();
      final spec = (item['speciality_name'] ?? item['speciality'] ?? item['speciality_id'] ?? '').toString();
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: () => _showDiscoveryDetailSheet(
            context,
            fullName.isEmpty ? 'Provider' : fullName,
            item,
          ),
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

class _CountriesTab extends StatefulWidget {
  const _CountriesTab({required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<_CountriesTab> createState() => _CountriesTabState();
}

class _CountriesTabState extends State<_CountriesTab> {
  late final Future<dynamic> _future = EmrFeaturesApi(widget.apiClient).countries();
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final next = _search.text.trim().toLowerCase();
      if (next == _q) return;
      setState(() => _q = next);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
            pickList(data['countries']) ??
            pickList(data)) ??
        const [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search by country name or code…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () => _search.clear(),
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<dynamic>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              if (snap.hasError) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.12),
                    Icon(Icons.public_off_outlined, size: 72, color: Colors.grey.shade400),
                    const SizedBox(height: 14),
                    Text(
                      'Could not load countries',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snap.error.toString(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                );
              }

              final items = _unwrapList(snap.data);
              final rows = items
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .map((item) {
                    final name = (item['country_name'] ??
                            item['name'] ??
                            item['title'] ??
                            item['country_code'] ??
                            item['code'] ??
                            'Unknown')
                        .toString()
                        .trim();
                    final code = (item['country_code'] ??
                            item['code'] ??
                            item['iso2'] ??
                            item['abbr'] ??
                            '')
                        .toString()
                        .trim();
                    return (name: name, code: code);
                  })
                  .where((x) {
                    if (_q.isEmpty) return true;
                    return x.name.toLowerCase().contains(_q) || x.code.toLowerCase().contains(_q);
                  })
                  .toList()
                ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

              if (rows.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.12),
                    Icon(Icons.travel_explore_rounded, size: 72, color: Colors.grey.shade400),
                    const SizedBox(height: 14),
                    Text(
                      'No countries match',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Try a different search.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final code = row.code.toUpperCase();
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _showDiscoveryDetailSheet(
                        context,
                        row.name,
                        {'name': row.name, 'code': row.code},
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            CountryFlag(
                              countryName: row.name,
                              countryCode: row.code,
                              size: 38,
                              radius: 14,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (code.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      code,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (code.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Text(
                                  code,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
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
