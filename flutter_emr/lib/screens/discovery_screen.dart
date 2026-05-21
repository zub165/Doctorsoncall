import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../widgets/country_flag.dart';
import '../widgets/person_avatar.dart';
import '../widgets/speciality_avatar.dart';
import '../services/emr_features_api.dart';
import '../theme/app_theme.dart';

List<Map<String, dynamic>> _normalizeDiscoveryList(dynamic data) {
  if (data == null) return const [];
  if (data is List) {
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  if (data is! Map) return const [];

  dynamic pick(dynamic v) {
    if (v is List) return v;
    if (v is Map) {
      for (final key in ['results', 'data', 'items']) {
        final inner = v[key];
        if (inner is List) return inner;
      }
    }
    return null;
  }

  for (final key in ['results', 'data', 'items', 'providers', 'specialities', 'countries']) {
    final list = pick(data[key]);
    if (list is List) {
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
  }
  final fallback = pick(data);
  if (fallback is List) {
    return fallback.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return const [];
}

/// Bundles Laravel parity APIs: **countries**, **specialities**, **providers**.
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final EmrFeaturesApi _api;

  List<Map<String, dynamic>> _countries = const [];
  List<Map<String, dynamic>> _specialities = const [];
  List<Map<String, dynamic>> _providers = const [];

  bool _loading = true;
  String? _loadError;

  final _countrySearch = TextEditingController();
  final _providerSearch = TextEditingController();
  String _countryQ = '';
  String _providerQ = '';

  int? _filterCountryId;
  String _filterCountryName = '';

  @override
  void initState() {
    super.initState();
    _api = EmrFeaturesApi(widget.apiClient);
    _tabs = TabController(length: 3, vsync: this);
    _countrySearch.addListener(_onCountrySearch);
    _providerSearch.addListener(_onProviderSearch);
    _loadAll();
  }

  void _onCountrySearch() {
    final next = _countrySearch.text.trim().toLowerCase();
    if (next == _countryQ) return;
    setState(() => _countryQ = next);
  }

  void _onProviderSearch() {
    final next = _providerSearch.text.trim().toLowerCase();
    if (next == _providerQ) return;
    setState(() => _providerQ = next);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _countrySearch.dispose();
    _providerSearch.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _api.countries(),
        _api.specialities(),
        _api.providers(),
      ]);
      if (!mounted) return;
      setState(() {
        _countries = _normalizeDiscoveryList(results[0]);
        _specialities = _normalizeDiscoveryList(results[1]);
        _providers = _normalizeDiscoveryList(results[2]);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Set<int> _specialityIdsForCountry(int? countryId, String countryName) {
    final nameLower = countryName.trim().toLowerCase();
    return _specialities
        .where((s) {
          final cid = s['country'];
          final cname = (s['country_name'] ?? '').toString().trim().toLowerCase();
          if (countryId != null && cid != null) {
            final id = cid is int ? cid : int.tryParse('$cid');
            if (id != null && id == countryId) return true;
          }
          if (nameLower.isNotEmpty && cname == nameLower) return true;
          return false;
        })
        .map((s) {
          final id = s['id'];
          return id is int ? id : int.tryParse('$id');
        })
        .whereType<int>()
        .toSet();
  }

  List<Map<String, dynamic>> _providersForCountry(int? countryId, String countryName) {
    final specIds = _specialityIdsForCountry(countryId, countryName);
    if (specIds.isEmpty) {
      return _providers.where((p) {
        final cid = p['country_id'];
        final cname = (p['country_name'] ?? '').toString().trim().toLowerCase();
        final nameLower = countryName.trim().toLowerCase();
        if (countryId != null && cid != null) {
          final id = cid is int ? cid : int.tryParse('$cid');
          if (id != null && id == countryId) return true;
        }
        return nameLower.isNotEmpty && cname == nameLower;
      }).toList();
    }
    return _providers.where((p) {
      final sid = p['speciality_id'];
      final id = sid is int ? sid : int.tryParse('$sid');
      return id != null && specIds.contains(id);
    }).toList();
  }

  List<Map<String, dynamic>> _filteredProviders({bool applyCountryFilter = false}) {
    var list = _providers;
    if (applyCountryFilter &&
        (_filterCountryId != null || _filterCountryName.isNotEmpty)) {
      list = _providersForCountry(_filterCountryId, _filterCountryName);
    }
    if (_providerQ.isEmpty) return list;
    return list.where((p) {
      final hay = [
        p['full_name'],
        p['name'],
        p['email'],
        p['speciality_name'],
        p['country_name'],
        p['status'],
      ].join(' ').toLowerCase();
      return hay.contains(_providerQ);
    }).toList();
  }

  void _openCountryProvidersSheet(Map<String, dynamic> country) {
    final name = (country['country_name'] ?? country['name'] ?? 'Country').toString();
    final code = (country['country_code'] ?? country['code'] ?? '').toString();
    final countryId = country['id'] is int ? country['id'] as int : int.tryParse('${country['id']}');
    final localSpecs = _specialities
        .where((s) => _specialityIdsForCountry(countryId, name).contains(s['id']))
        .toList();
    final localProviders = _providersForCountry(countryId, name);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Row(
                  children: [
                    CountryFlag(countryName: name, countryCode: code, size: 40, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${localProviders.length} doctor${localProviders.length == 1 ? '' : 's'} · '
                  '${localSpecs.length} specialit${localSpecs.length == 1 ? 'y' : 'ies'}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (localProviders.isEmpty) ...[
                  Icon(Icons.person_search_rounded, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  const Text(
                    'No doctors linked to this country yet.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _filterCountryId = null;
                        _filterCountryName = '';
                      });
                      _tabs.animateTo(2);
                    },
                    child: Text('View all ${_providers.length} doctors'),
                  ),
                ] else ...[
                  Text(
                    'Doctors',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...localProviders.map(
                    (p) => _ProviderTile(
                      provider: p,
                      compact: true,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showProviderDetail(p);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _filterCountryId = countryId;
                        _filterCountryName = name;
                        _providerSearch.clear();
                        _providerQ = '';
                      });
                      _tabs.animateTo(2);
                    },
                    icon: const Icon(Icons.people_outline),
                    label: const Text('Open in Providers tab'),
                  ),
                ],
                if (localSpecs.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Specialities',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: localSpecs.take(12).map((s) {
                      final specName = (s['speciality_name'] ?? s['name'] ?? '').toString();
                      return ActionChip(
                        label: Text(specName, overflow: TextOverflow.ellipsis),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _tabs.animateTo(1);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  void _showProviderDetail(Map<String, dynamic> p) {
    final name = (p['full_name'] ?? p['name'] ?? 'Doctor').toString();
    final spec = (p['speciality_name'] ?? '').toString();
    final status = (p['status'] ?? '').toString();
    final fee = (p['consultation_fee'] ?? '').toString();
    final country = (p['country_name'] ?? '').toString();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PersonAvatar(
              name: name,
              imageUrl: (p['profile_image'] ?? '').toString(),
              size: 88,
              useSpecialityStyle: true,
              specialityName: spec.isNotEmpty ? spec : name,
              specialityImageUrl: (p['speciality_image'] ?? '').toString(),
            ),
            const SizedBox(height: 12),
            Text(name, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (spec.isNotEmpty) Text(spec, style: TextStyle(color: Colors.grey.shade700)),
            if (country.isNotEmpty) Text(country, style: TextStyle(color: Colors.grey.shade600)),
            if ((p['email'] ?? '').toString().isNotEmpty)
              Text((p['email'] ?? '').toString()),
            if (fee.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Consultation fee: $fee'),
            ],
            const SizedBox(height: 8),
            _StatusPill(status: status),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            tabs: [
              Tab(
                icon: const Icon(Icons.public, size: 20),
                text: 'Countries (${_countries.length})',
              ),
              Tab(
                icon: const Icon(Icons.medical_services, size: 20),
                text: 'Specialities (${_specialities.length})',
              ),
              Tab(
                icon: const Icon(Icons.people, size: 20),
                text: 'Providers (${_providers.length})',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Material(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user, color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Available doctors on Docs On Call — book online video visits. '
                      'Licensed clinicians can join the platform; some offer volunteer telehealth.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _loadError != null
                  ? _ErrorPane(message: _loadError!, onRetry: _loadAll)
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _buildCountriesTab(context),
                        _buildSpecialitiesTab(context),
                        _buildProvidersTab(context),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildCountriesTab(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _countries
        .map((item) {
          final name = (item['country_name'] ??
                  item['name'] ??
                  item['title'] ??
                  item['country_code'] ??
                  item['code'] ??
                  'Unknown')
              .toString()
              .trim();
          final code = (item['country_code'] ?? item['code'] ?? item['iso2'] ?? '')
              .toString()
              .trim();
          final id = item['id'] is int ? item['id'] as int : int.tryParse('${item['id']}');
          final doctorCount = _providersForCountry(id, name).length;
          return (item: item, name: name, code: code, doctorCount: doctorCount);
        })
        .where((x) {
          if (_countryQ.isEmpty) return true;
          return x.name.toLowerCase().contains(_countryQ) ||
              x.code.toLowerCase().contains(_countryQ);
        })
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: TextField(
            controller: _countrySearch,
            decoration: InputDecoration(
              hintText: 'Search by country name or code…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _countryQ.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () => _countrySearch.clear(),
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text('No countries match', style: theme.textTheme.titleMedium))
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  color: AppColors.primary,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                          onTap: () => _openCountryProvidersSheet(row.item),
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
                                      const SizedBox(height: 4),
                                      Text(
                                        row.doctorCount > 0
                                            ? '${row.doctorCount} doctor${row.doctorCount == 1 ? '' : 's'}'
                                            : 'Tap to browse specialities',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: row.doctorCount > 0
                                              ? AppColors.primary
                                              : Colors.grey.shade600,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (code.isNotEmpty)
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      code,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
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
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSpecialitiesTab(BuildContext context) {
    final items = _specialities;
    if (items.isEmpty) {
      return _EmptyPane(
        icon: Icons.medical_services_outlined,
        title: 'No specialities',
        subtitle: 'Pull down to refresh.',
        onRefresh: _loadAll,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final name =
              (item['speciality_name'] ?? item['name'] ?? item['title'] ?? 'Unknown').toString();
          final img = (item['speciality_image'] ?? item['image'] ?? '').toString();
          final country = (item['country_name'] ?? '').toString();
          final specId = item['id'] is int ? item['id'] as int : int.tryParse('${item['id']}');
          final docCount = _providers
              .where((p) {
                final sid = p['speciality_id'];
                final id = sid is int ? sid : int.tryParse('$sid');
                return specId != null && id == specId;
              })
              .length;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () {
                setState(() {
                  _filterCountryId = null;
                  _filterCountryName = '';
                  _providerQ = name.toLowerCase();
                  _providerSearch.text = name;
                });
                _tabs.animateTo(2);
              },
              leading: SpecialityAvatar(
                name: name,
                imageUrl: img,
                size: 48,
                radius: 12,
                onlineFallback: false,
              ),
              title: Text(name),
              subtitle: Text(
                [
                  if (country.isNotEmpty) country,
                  if (docCount > 0) '$docCount doctor${docCount == 1 ? '' : 's'}',
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProvidersTab(BuildContext context) {
    final list = _filteredProviders(applyCountryFilter: _filterCountryId != null ||
        _filterCountryName.isNotEmpty);
    return Column(
      children: [
        if (_filterCountryName.isNotEmpty)
          Material(
            color: AppColors.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filtered: $_filterCountryName (${list.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _filterCountryId = null;
                      _filterCountryName = '';
                    }),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _providerSearch,
            decoration: InputDecoration(
              hintText: 'Search doctors by name, specialty, email…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _providerQ.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _providerSearch.clear();
                        setState(() {
                          _providerQ = '';
                          _filterCountryId = null;
                          _filterCountryName = '';
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _EmptyPane(
                  icon: Icons.people_outline,
                  title: _providers.isEmpty ? 'No providers in database' : 'No doctors match',
                  subtitle: _providers.isEmpty
                      ? 'Ask admin to add providers, then pull to refresh.'
                      : 'Try clearing search or country filter.',
                  onRefresh: _loadAll,
                )
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  color: AppColors.primary,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: list.length,
                    itemBuilder: (context, index) => _ProviderTile(
                      provider: list[index],
                      onTap: () => _showProviderDetail(list[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    this.onTap,
    this.compact = false,
  });

  final Map<String, dynamic> provider;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fullName =
        (provider['full_name'] ?? provider['name'] ?? provider['fullName'] ?? 'Provider')
            .toString();
    final email = (provider['email'] ?? '').toString();
    final status = (provider['status'] ?? provider['state'] ?? '').toString();
    final spec = (provider['speciality_name'] ?? provider['speciality'] ?? '').toString();
    final country = (provider['country_name'] ?? '').toString();

    return Card(
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      child: ListTile(
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 4 : 8,
        ),
        leading: PersonAvatar(
          name: fullName,
          imageUrl: (provider['profile_image'] ?? '').toString(),
          size: compact ? 44 : 52,
          useSpecialityStyle: true,
          specialityName: spec.isNotEmpty ? spec : fullName,
          specialityImageUrl: (provider['speciality_image'] ?? '').toString(),
        ),
        title: Text(
          fullName.isEmpty ? 'Unknown' : fullName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (spec.isNotEmpty) spec,
            if (country.isNotEmpty) country,
            if (email.isNotEmpty) email,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _StatusPill(status: status),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final active = status.toLowerCase() == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF4CAF50).withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.isEmpty ? 'N/A' : status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? const Color(0xFF4CAF50) : Colors.grey.shade700,
        ),
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.12),
          Icon(icon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Could not load discovery data', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
