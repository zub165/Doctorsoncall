import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../widgets/api_access_placeholder.dart';
import '../widgets/country_flag.dart';
import '../widgets/speciality_avatar.dart';

class AdminHubScreen extends StatefulWidget {
  const AdminHubScreen({
    super.key,
    required this.apiClient,
    this.embeddedInShell = false,
  });

  final EmergencyApiClient apiClient;

  /// When true (main [AppShell] tab), omit nested [Scaffold]/[AppBar].
  final bool embeddedInShell;

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = <String>[
    'Roles',
    'Plans',
    'Specialities',
    'Countries',
    'Providers',
    'Patients',
    'Appointments',
  ];

  static const _icons = [
    Icons.admin_panel_settings,
    Icons.card_membership,
    Icons.medical_services,
    Icons.public,
    Icons.people,
    Icons.person,
    Icons.event,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFFD32F2F);
    final canPop = !widget.embeddedInShell && Navigator.canPop(context);

    final body = Column(
      children: [
        Material(
          color: primary,
          elevation: 0,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: [for (final t in _tabs) Tab(text: t)],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (int i = 0; i < _tabs.length; i++)
                _AdminTabAlive(
                  key: PageStorageKey<String>('admin_tab_${_tabs[i]}'),
                  child: _AdminTab(
                    title: _tabs[i],
                    icon: _icons[i],
                    apiClient: widget.apiClient,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    if (canPop) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin hub'),
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
        body: body,
      );
    }
    return body;
  }
}

/// Keeps off-screen admin tabs alive so [TabController] / network images are not torn down mid-load.
class _AdminTabAlive extends StatefulWidget {
  const _AdminTabAlive({super.key, required this.child});

  final Widget child;

  @override
  State<_AdminTabAlive> createState() => _AdminTabAliveState();
}

class _AdminTabAliveState extends State<_AdminTabAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _AdminTab extends StatelessWidget {
  const _AdminTab({
    required this.title,
    required this.icon,
    required this.apiClient,
  });

  final String title;
  final IconData icon;
  final EmergencyApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    final api = EmrFeaturesApi(apiClient);

    if (title == 'Roles') {
      return _AdminRolesTab(
        api: api,
        icon: icon,
        load: () async {
          final data = await api.roles();
          final v = (data is Map ? (data['data'] ?? data['results'] ?? data) : data);
          if (v is List) {
            return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          }
          return const <Map<String, dynamic>>[];
        },
        itemTitle: (m) => (m['name'] ?? '').toString(),
        itemSubtitle: (m) => (m['description'] ?? '').toString(),
        trailingPill: (m) => (m['status'] ?? '').toString(),
        editorFields: const [
          _EditorField(keyName: 'name', label: 'Name'),
          _EditorField(keyName: 'status', label: 'Status (active/inactive)'),
          _EditorField(keyName: 'description', label: 'Description (optional)'),
        ],
        onSave: (id, patch) => api.adminPatchRole(id, patch),
      );
    }

    if (title == 'Plans') {
      return _AdminCrudList(
        title: title,
        icon: icon,
        load: () async {
          final data = await api.plans();
          final v = (data is Map ? (data['data'] ?? data['results'] ?? data) : data);
          if (v is List) {
            return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          }
          return const <Map<String, dynamic>>[];
        },
        itemTitle: (m) => (m['plan_name'] ?? m['name'] ?? '').toString(),
        itemSubtitle: (m) =>
            '${(m['duration'] ?? '').toString()} · ${(m['price'] ?? '').toString()}',
        trailingPill: (m) => (m['ai_bot'] ?? '').toString(),
        editorFields: const [
          _EditorField(keyName: 'plan_name', label: 'Plan name'),
          _EditorField(keyName: 'duration', label: 'Duration'),
          _EditorField(keyName: 'price', label: 'Price'),
          _EditorField(keyName: 'number_appointments', label: 'Number of appointments'),
          _EditorField(keyName: 'ai_bot', label: 'AI bot (yes/no)'),
          _EditorField(keyName: 'discount', label: 'Discount (optional)'),
        ],
        onSave: (id, patch) => api.adminPatchPlan(id, patch),
      );
    }

    if (title == 'Countries') {
      return _AdminCountriesTab(api: api, icon: icon);
    }

    if (title == 'Specialities') {
      return _AdminSpecialitiesTab(api: api, icon: icon);
    }

    if (title == 'Providers') {
      return _AdminPeopleTab(
        title: title,
        icon: icon,
        api: api,
        kind: 'doctor',
        loadAll: () async {
          final data = await api.providers();
          final v = (data is Map ? (data['data'] ?? data['results'] ?? data['providers'] ?? data) : data);
          if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          return const <Map<String, dynamic>>[];
        },
        itemTitle: (m) => (m['full_name'] ?? m['name'] ?? '').toString(),
        itemSubtitle: (m) => 'ID: ${m['id']}',
        trailingPill: (m) => (m['status'] ?? '').toString(),
        editorFields: const [
          _EditorField(keyName: 'full_name', label: 'Full name'),
          _EditorField(keyName: 'email', label: 'Email'),
          _EditorField(keyName: 'status', label: 'Status (active/inactive/pending)'),
          _EditorField(keyName: 'is_verified', label: 'Verified (true/false)'),
          _EditorField(keyName: 'is_staff', label: 'Staff access (true/false)'),
          _EditorField(keyName: 'speciality_id', label: 'Speciality ID'),
          _EditorField(keyName: 'consultation_fee', label: 'Consultation fee'),
        ],
        onSave: (id, patch) => api.adminPatchProvider(id, patch),
        onDelete: (id) => api.adminDeleteProvider(id),
        pendingTitle: (m) => (m['full_name'] ?? '').toString(),
        pendingSubtitle: (m) => (m['email'] ?? '').toString(),
        pendingId: (m) => (m['id'] ?? 0).toString(),
      );
    }

    if (title == 'Patients') {
      return _AdminPeopleTab(
        title: title,
        icon: icon,
        api: api,
        kind: 'patient',
        loadAll: () async {
          final data = await api.patients();
          final v = (data is Map ? (data['data'] ?? data['results'] ?? data) : data);
          if (v is List) {
            return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          }
          return const <Map<String, dynamic>>[];
        },
        itemTitle: (m) => (m['name'] ?? m['full_name'] ?? '').toString(),
        itemSubtitle: (m) => (m['email'] ?? '').toString(),
        trailingPill: (m) => (m['profile_status'] ?? m['status'] ?? '').toString(),
        editorFields: const [
          _EditorField(keyName: 'name', label: 'Name'),
          _EditorField(keyName: 'email', label: 'Email'),
          _EditorField(keyName: 'profile_status', label: 'Profile status'),
          _EditorField(keyName: 'is_staff', label: 'Staff access (true/false)'),
          _EditorField(keyName: 'is_superuser', label: 'Superuser (true/false)'),
        ],
        onSave: (id, patch) => api.adminPatchPatient(id, patch),
        onDelete: (id) => api.adminDeletePatient(id),
        pendingTitle: (m) => (m['name'] ?? m['full_name'] ?? '').toString(),
        pendingSubtitle: (m) => (m['email'] ?? '').toString(),
        pendingId: (m) => (m['id'] ?? 0).toString(),
      );
    }

    if (title == 'Appointments') {
      return _AdminAppointmentsTab(api: api, icon: icon);
    }

    // All known [_tabs] entries return above; this is a safe fallback if tabs change.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Admin section "$title" is not wired yet.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

// (Removed obsolete styleWith extension)

/// Admin specialities — image-rich list + editor (preview, presets, generated avatar).
class _AdminSpecialitiesTab extends StatefulWidget {
  const _AdminSpecialitiesTab({required this.api, required this.icon});

  final EmrFeaturesApi api;
  final IconData icon;

  @override
  State<_AdminSpecialitiesTab> createState() => _AdminSpecialitiesTabState();
}

class _AdminSpecialitiesTabState extends State<_AdminSpecialitiesTab>
    with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  Object? _loadError;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await widget.api.specialities();
      final v = (data is Map ? (data['data'] ?? data['results'] ?? data) : data);
      final items = v is List
          ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  void _reload() {
    if (!mounted) return;
    _load();
  }

  Future<void> _downloadAllAvatars() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download all speciality avatars?'),
        content: const Text(
          'Downloads PNG images to the server (your media folder) and saves a permanent URL on each speciality — no more ui-avatars.com links.\n\nThis may take a minute.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Download')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFFD32F2F))),
    );

    try {
      final result = await widget.api.adminSeedSpecialityAvatars(force: true);
      if (!mounted) return;
      Navigator.pop(context);
      final updated = result['updated'] ?? 0;
      final errors = result['errors'];
      final errCount = errors is List ? errors.length : 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errCount > 0
                ? 'Downloaded $updated avatars ($errCount failed)'
                : 'Downloaded $updated speciality avatars to server',
          ),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: ${ApiAccessPlaceholder.shortMessage(e)}')),
      );
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final idRaw = item['id'];
    final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
    if (id == null) return;

    final nameC = TextEditingController(
      text: (item['speciality_name'] ?? item['name'] ?? '').toString(),
    );
    final imageC = TextEditingController(
      text: (item['speciality_image'] ?? '').toString(),
    );
    final countryC = TextEditingController(
      text: (item['country'] ?? item['country_id'] ?? '').toString(),
    );
    var previewName = nameC.text;
    var previewUrl = imageC.text;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void refreshPreview() {
              setModalState(() {
                previewName = nameC.text;
                previewUrl = imageC.text;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Edit speciality',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: SpecialityAvatar(
                        key: ValueKey<String>('preview-$previewName-$previewUrl'),
                        name: previewName,
                        imageUrl: previewUrl,
                        size: 96,
                        radius: 16,
                        onlineFallback: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        previewName.isEmpty ? 'Speciality name' : previewName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameC,
                      decoration: InputDecoration(
                        labelText: 'Speciality name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (_) => refreshPreview(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: imageC,
                      decoration: InputDecoration(
                        labelText: 'Image URL',
                        hintText: 'https://api…/media/specialities/… or use Download all',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(
                          tooltip: 'Generate avatar from name',
                          icon: const Icon(Icons.auto_awesome_rounded),
                          onPressed: () {
                            imageC.text = SpecialityImagePresets.avatarFor(nameC.text);
                            refreshPreview();
                          },
                        ),
                      ),
                      onChanged: (_) => refreshPreview(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: countryC,
                      decoration: InputDecoration(
                        labelText: 'Country ID (optional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Quick image picks',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: SpecialityImagePresets.catalog.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final p = SpecialityImagePresets.catalog[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              imageC.text = p.url;
                              refreshPreview();
                            },
                            child: Column(
                              children: [
                                SpecialityAvatar(name: p.label, imageUrl: p.url, size: 48, radius: 10),
                                const SizedBox(height: 4),
                                Text(p.label, style: const TextStyle(fontSize: 10)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Save changes'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final patchName = nameC.text.trim();
    final patchImage = imageC.text.trim();
    final patchCountryRaw = countryC.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameC.dispose();
      imageC.dispose();
      countryC.dispose();
    });

    if (saved != true) return;

    final patch = <String, dynamic>{
      'speciality_name': patchName,
      'speciality_image': patchImage,
    };
    if (patchCountryRaw.isNotEmpty) {
      patch['country'] = int.tryParse(patchCountryRaw) ?? patchCountryRaw;
    }

    if (!mounted) return;

    try {
      await widget.api.adminPatchSpeciality(id, patch);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speciality saved')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: ${ApiAccessPlaceholder.shortMessage(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD32F2F)));
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Failed to load: ${ApiAccessPlaceholder.shortMessage(_loadError)}',
          ),
        ),
      );
    }

    final items = _items;
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? items
        : items.where((m) {
            final name = (m['speciality_name'] ?? '').toString().toLowerCase();
            final country = (m['country_name'] ?? '').toString().toLowerCase();
            return name.contains(q) || country.contains(q);
          }).toList();

    return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const SpecialityAvatar(name: 'MD', size: 44, radius: 12, onlineFallback: false),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Specialities',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            '${items.length} specialties · hosted images on server',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Download all avatars to server',
                      onPressed: _downloadAllAvatars,
                      icon: const Icon(Icons.cloud_download_rounded),
                    ),
                    IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search specialities…',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty) const Text('No specialities found.'),
            for (final m in filtered)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _edit(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        SpecialityAvatar(
                          key: ValueKey<int?>((m['id'] as num?)?.toInt()),
                          name: (m['speciality_name'] ?? '').toString(),
                          imageUrl: (m['speciality_image'] ?? '').toString(),
                          size: 56,
                          radius: 14,
                          onlineFallback: (m['speciality_image'] ?? '').toString().trim().isEmpty,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (m['speciality_name'] ?? 'Speciality').toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _specialitySubtitle(m),
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.edit_rounded, color: Color(0xFFD32F2F)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
  }

  String _specialitySubtitle(Map<String, dynamic> m) {
    final country = (m['country_name'] ?? '').toString().trim();
    final img = (m['speciality_image'] ?? '').toString().trim();
    if (country.isNotEmpty && img.isNotEmpty) return '$country · custom image';
    if (country.isNotEmpty) return country;
    if (img.isNotEmpty) return 'Custom image';
    return 'Auto avatar from name';
  }
}

/// Countries — flags, search, add / edit / delete.
class _AdminCountriesTab extends StatefulWidget {
  const _AdminCountriesTab({required this.api, required this.icon});

  final EmrFeaturesApi api;
  final IconData icon;

  @override
  State<_AdminCountriesTab> createState() => _AdminCountriesTabState();
}

class _AdminCountriesTabState extends State<_AdminCountriesTab>
    with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  Object? _loadError;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await widget.api.countries();
      final v = (data is Map ? (data['data'] ?? data['results'] ?? data) : data);
      final items = v is List
          ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  void _reload() {
    if (!mounted) return;
    _load();
  }

  Future<void> _add() async {
    final nameC = TextEditingController();
    final codeC = TextEditingController();
    final imageC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add country'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Country name')),
            TextField(controller: codeC, decoration: const InputDecoration(labelText: 'Code (US, GB, …)')),
            TextField(controller: imageC, decoration: const InputDecoration(labelText: 'Flag URL (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final code = codeC.text.trim().toUpperCase();
      await widget.api.adminCreateCountry({
        'country_name': nameC.text.trim(),
        'country_code': code,
        if (imageC.text.trim().isNotEmpty) 'image': imageC.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Country added')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add failed: ${ApiAccessPlaceholder.shortMessage(e)}')),
      );
    } finally {
      nameC.dispose();
      codeC.dispose();
      imageC.dispose();
    }
  }

  Future<void> _edit(Map<String, dynamic> m) async {
    final id = (m['id'] as num?)?.toInt();
    if (id == null) return;
    final nameC = TextEditingController(text: (m['country_name'] ?? '').toString());
    final codeC = TextEditingController(text: (m['country_code'] ?? '').toString());
    final imageC = TextEditingController(text: (m['image'] ?? '').toString());
    var previewName = nameC.text;
    var previewCode = codeC.text;
    var previewImage = imageC.text;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          void refresh() => setModal(() {
            previewName = nameC.text;
            previewCode = codeC.text;
            previewImage = imageC.text;
          });
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Edit country', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                CountryFlag(
                  countryName: previewName,
                  countryCode: previewCode,
                  imageUrl: previewImage,
                  size: 88,
                  radius: 12,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: 'Country name'),
                  onChanged: (_) => refresh(),
                ),
                TextField(
                  controller: codeC,
                  decoration: const InputDecoration(labelText: 'Country code'),
                  onChanged: (_) => refresh(),
                ),
                TextField(
                  controller: imageC,
                  decoration: InputDecoration(
                    labelText: 'Flag image URL',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.flag_rounded),
                      onPressed: () {
                        imageC.text = CountryFlag.flagCdnUrl(codeC.text);
                        refresh();
                      },
                    ),
                  ),
                  onChanged: (_) => refresh(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (saved != true) {
      nameC.dispose();
      codeC.dispose();
      imageC.dispose();
      return;
    }
    try {
      await widget.api.adminPatchCountry(id, {
        'country_name': nameC.text.trim(),
        'country_code': codeC.text.trim().toUpperCase(),
        'image': imageC.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: ${ApiAccessPlaceholder.shortMessage(e)}')),
      );
    } finally {
      nameC.dispose();
      codeC.dispose();
      imageC.dispose();
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final id = (m['id'] as num?)?.toInt();
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete country?'),
        content: Text('Remove “${m['country_name']}”?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.adminDeleteCountry(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${ApiAccessPlaceholder.shortMessage(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fabBottom = 16.0 + MediaQuery.paddingOf(context).bottom;

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD32F2F)));
    }
    if (_loadError != null) {
      return Center(
        child: Text('Failed to load: ${ApiAccessPlaceholder.shortMessage(_loadError)}'),
      );
    }

    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _items
        : _items.where((m) {
            final n = (m['country_name'] ?? '').toString().toLowerCase();
            final c = (m['country_code'] ?? '').toString().toLowerCase();
            return n.contains(q) || c.contains(q);
          }).toList();

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, fabBottom + 72),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Card(
                    color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                    child: ListTile(
                      leading: const Icon(Icons.public_rounded, color: Color(0xFFD32F2F)),
                      title: const Text('Countries', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${_items.length} countries · search by name or code'),
                      trailing: IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search countries…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (filtered.isEmpty) const Text('No countries found.'),
                ]),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, fabBottom + 72),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final m = filtered[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CountryFlag(
                          key: ValueKey<int?>((m['id'] as num?)?.toInt()),
                          countryName: (m['country_name'] ?? '').toString(),
                          countryCode: (m['country_code'] ?? '').toString(),
                          imageUrl: (m['image'] ?? '').toString(),
                          size: 48,
                          radius: 8,
                        ),
                        title: Text(
                          (m['country_name'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text((m['country_code'] ?? '').toString()),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _edit(m);
                            if (v == 'delete') _delete(m);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: fabBottom,
          child: FloatingActionButton.extended(
            heroTag: 'admin_fab_countries',
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add country'),
            backgroundColor: const Color(0xFFD32F2F),
          ),
        ),
      ],
    );
  }
}

List<Map<String, dynamic>> _apiMapList(dynamic data, {List<String> nestedKeys = const []}) {
  if (data is List) {
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  if (data is Map) {
    if (data['appointments'] is List) {
      return (data['appointments'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    final inner = data['data'];
    if (inner is Map && inner['appointments'] is List) {
      return (inner['appointments'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    for (final k in ['data', 'results', ...nestedKeys]) {
      final v = data[k];
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (v is Map && v['appointments'] is List) {
        return (v['appointments'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
  }
  return const [];
}

String _appointmentPatientLabel(Map<String, dynamic> m) {
  if (m['patient'] is Map) return (m['patient'] as Map)['name']?.toString() ?? '';
  return '';
}

String _appointmentProviderLabel(Map<String, dynamic> m) {
  if (m['provider'] is Map) {
    final p = m['provider'] as Map;
    return (p['full_name'] ?? p['name'] ?? '').toString();
  }
  return '';
}

int? _nestedId(Map<String, dynamic> m, String key) {
  final direct = m['${key}_id'] ?? m[key];
  if (direct is num) return direct.toInt();
  if (direct is Map && direct['id'] is num) return (direct['id'] as num).toInt();
  return int.tryParse(direct?.toString() ?? '');
}

/// Appointments — add / edit / delete for staff.
class _AdminAppointmentsTab extends StatefulWidget {
  const _AdminAppointmentsTab({required this.api, required this.icon});

  final EmrFeaturesApi api;
  final IconData icon;

  @override
  State<_AdminAppointmentsTab> createState() => _AdminAppointmentsTabState();
}

class _AdminAppointmentsTabState extends State<_AdminAppointmentsTab> {
  late Future<List<Map<String, dynamic>>> _future = _loadAppointments();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _patients = const [];
  List<Map<String, dynamic>> _providers = const [];

  @override
  void initState() {
    super.initState();
    _loadPicklists();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPicklists() async {
    try {
      final pData = await widget.api.patients();
      final prData = await widget.api.providers();
      if (!mounted) return;
      setState(() {
        _patients = _apiMapList(pData);
        _providers = _apiMapList(prData, nestedKeys: ['providers']);
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadAppointments() async {
    final data = await widget.api.allAppointments();
    return _apiMapList(data, nestedKeys: ['appointments']);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _loadAppointments();
    });
  }

  String _rowTitle(Map<String, dynamic> m) => '${m['date'] ?? ''} ${m['time'] ?? ''}'.trim();

  String _rowSubtitle(Map<String, dynamic> m) {
    final p = _appointmentPatientLabel(m);
    final pr = _appointmentProviderLabel(m);
    final st = (m['approved'] ?? m['status'] ?? '').toString();
    final parts = <String>[
      if (p.isNotEmpty) 'Patient: $p',
      if (pr.isNotEmpty) 'Provider: $pr',
      if (st.isNotEmpty) 'Status: $st',
    ];
    return parts.join(' · ');
  }

  Future<void> _showForm({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final id = isEdit ? (existing['id'] as num?)?.toInt() : null;
    final dateC = TextEditingController(text: (existing?['date'] ?? '').toString());
    final timeC = TextEditingController(text: (existing?['time'] ?? '').toString());
    final statusC = TextEditingController(
      text: (existing?['approved'] ?? existing?['status'] ?? 'approved').toString(),
    );
    int? patientId = _nestedId(existing ?? {}, 'patient');
    int? providerId = _nestedId(existing ?? {}, 'provider');

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isEdit ? 'Edit appointment' : 'Add appointment',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_patients.isEmpty)
                    TextField(
                      decoration: const InputDecoration(labelText: 'Patient ID'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => patientId = int.tryParse(v.trim()),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: patientId,
                      decoration: const InputDecoration(labelText: 'Patient'),
                      items: [
                        for (final p in _patients)
                          DropdownMenuItem<int>(
                            value: (p['id'] as num?)?.toInt(),
                            child: Text(
                              '${p['name'] ?? p['full_name'] ?? 'Patient'} (#${p['id']})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setModal(() => patientId = v),
                    ),
                  const SizedBox(height: 8),
                  if (_providers.isEmpty)
                    TextField(
                      decoration: const InputDecoration(labelText: 'Provider ID'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => providerId = int.tryParse(v.trim()),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: providerId,
                      decoration: const InputDecoration(labelText: 'Provider'),
                      items: [
                        for (final p in _providers)
                          DropdownMenuItem<int>(
                            value: (p['id'] as num?)?.toInt(),
                            child: Text(
                              '${p['full_name'] ?? p['name'] ?? 'Provider'} (#${p['id']})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setModal(() => providerId = v),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dateC,
                    decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: timeC,
                    decoration: const InputDecoration(labelText: 'Time (HH:MM or HH:MM:SS)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: statusC,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      hintText: 'approved, pending, cancelled…',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(isEdit ? 'Save' : 'Create'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (ok != true) {
      dateC.dispose();
      timeC.dispose();
      statusC.dispose();
      return;
    }

    if (patientId == null || providerId == null) {
      dateC.dispose();
      timeC.dispose();
      statusC.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient and provider are required')),
        );
      }
      return;
    }

    try {
      if (isEdit && id != null) {
        await widget.api.adminPatchAppointment(id, {
          'patient_id': patientId,
          'provider_id': providerId,
          'date': dateC.text.trim(),
          'time': timeC.text.trim(),
          'status': statusC.text.trim(),
        });
      } else {
        await widget.api.adminCreateAppointment(
          patientId: patientId!,
          providerId: providerId!,
          date: dateC.text.trim(),
          time: timeC.text.trim(),
          status: statusC.text.trim(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEdit ? 'Appointment updated' : 'Appointment created')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${ApiAccessPlaceholder.shortMessage(e)}')),
      );
    } finally {
      dateC.dispose();
      timeC.dispose();
      statusC.dispose();
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final id = (m['id'] as num?)?.toInt();
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete appointment?'),
        content: Text('Remove ${_rowTitle(m)}?\n${_rowSubtitle(m)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.adminDeleteAppointment(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${ApiAccessPlaceholder.shortMessage(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.event_available_outlined, color: Color(0xFFD32F2F)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Schedule or update appointments',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showForm(),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Add appointment'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
                  if (!snap.hasData && snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFD32F2F)));
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Failed to load: ${ApiAccessPlaceholder.shortMessage(snap.error)}',
                        ),
                      ),
                    );
                  }
                  final items = snap.data ?? const [];
                  final q = _search.text.trim().toLowerCase();
                  final filtered = q.isEmpty
                      ? items
                      : items.where((m) {
                          final blob = [
                            _rowTitle(m),
                            _rowSubtitle(m),
                            (m['id'] ?? '').toString(),
                            (m['approved'] ?? '').toString(),
                          ].join(' ').toLowerCase();
                          return blob.contains(q);
                        }).toList();

                  final bottomPad = 16.0 + MediaQuery.paddingOf(context).bottom;
                  return ListView(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
                    children: [
                      Card(
                        color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                        child: ListTile(
                          leading: Icon(widget.icon, color: const Color(0xFFD32F2F)),
                          title: const Text('Appointments', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${items.length} total · search by date, patient, provider'),
                          trailing: IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          hintText: 'Search appointments…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                        ),
                        onChanged: (_) {
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      if (filtered.isEmpty) const Text('No appointments found.'),
                      for (final m in filtered)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFD32F2F).withValues(alpha: 0.12),
                              child: const Icon(Icons.event_note_rounded, color: Color(0xFFD32F2F)),
                            ),
                            title: Text(_rowTitle(m), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(_rowSubtitle(m)),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') _showForm(existing: m);
                                if (v == 'delete') _delete(m);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                            onTap: () => _showForm(existing: m),
                          ),
                        ),
                    ],
                  );
                },
          ),
        ),
      ],
    );
  }
}

Future<void> _showCreateUserDialog(
  BuildContext context, {
  required EmrFeaturesApi api,
  required String kind,
  VoidCallback? onCreated,
}) async {
  final nameC = TextEditingController();
  final emailC = TextEditingController();
  final passC = TextEditingController();
  final phoneC = TextEditingController();
  int? specialityId;
  List<Map<String, dynamic>> specs = const [];
  if (kind == 'doctor') {
    try {
      final data = await api.specialities();
      final v = (data is Map ? (data['data'] ?? data['results'] ?? data) : data);
      if (v is List) {
        specs = v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
  }

  if (!context.mounted) {
    nameC.dispose();
    emailC.dispose();
    passC.dispose();
    phoneC.dispose();
    return;
  }

  final addLabel = switch (kind) {
    'doctor' => 'Add provider',
    'admin' => 'Add administrator',
    _ => 'Add patient',
  };

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModal) {
        final bottom = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(addLabel, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Full name')),
                const SizedBox(height: 10),
                TextField(
                  controller: emailC,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passC,
                  decoration: const InputDecoration(labelText: 'Password (min 8)'),
                  obscureText: true,
                ),
                if (kind == 'patient') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneC,
                    decoration: const InputDecoration(labelText: 'Phone (optional)'),
                    keyboardType: TextInputType.phone,
                  ),
                ],
                if (kind == 'doctor') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneC,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 10),
                  if (specs.isEmpty)
                    TextField(
                      decoration: const InputDecoration(labelText: 'Speciality ID'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => specialityId = int.tryParse(v.trim()),
                    )
                  else
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Speciality'),
                      items: [
                        for (final s in specs)
                          DropdownMenuItem<int>(
                            value: (s['id'] as num?)?.toInt(),
                            child: Text(
                              (s['speciality_name'] ?? s['name'] ?? 'ID ${s['id']}').toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setModal(() => specialityId = v),
                    ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Create'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (ok != true) {
    nameC.dispose();
    emailC.dispose();
    passC.dispose();
    phoneC.dispose();
    return;
  }
  try {
    await api.adminCreateUser(
      kind: kind,
      email: emailC.text.trim(),
      password: passC.text,
      name: nameC.text.trim(),
      specialityId: kind == 'doctor' ? specialityId : null,
      phoneNumber: phoneC.text.trim().isNotEmpty ? phoneC.text.trim() : null,
      profileStatus: kind == 'patient' ? 'approved' : null,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$addLabel created')));
      onCreated?.call();
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${ApiAccessPlaceholder.shortMessage(e)}')),
      );
    }
  } finally {
    nameC.dispose();
    emailC.dispose();
    passC.dispose();
    phoneC.dispose();
  }
}

/// Roles CRUD + FAB to create a new staff administrator account.
class _AdminRolesTab extends StatelessWidget {
  const _AdminRolesTab({
    required this.api,
    required this.icon,
    required this.load,
    required this.itemTitle,
    required this.itemSubtitle,
    required this.trailingPill,
    required this.editorFields,
    required this.onSave,
  });

  final EmrFeaturesApi api;
  final IconData icon;
  final _Loader load;
  final _TextFor itemTitle;
  final _TextFor itemSubtitle;
  final _TextFor trailingPill;
  final List<_EditorField> editorFields;
  final _Saver onSave;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _AdminCrudList(
          title: 'Roles',
          icon: icon,
          load: load,
          itemTitle: itemTitle,
          itemSubtitle: itemSubtitle,
          trailingPill: trailingPill,
          editorFields: editorFields,
          onSave: onSave,
          listPaddingBottom: 88,
          searchHint: 'Search roles by name or description…',
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'admin_fab_roles',
            onPressed: () => _showCreateUserDialog(context, api: api, kind: 'admin'),
            icon: const Icon(Icons.admin_panel_settings_rounded),
            label: const Text('Add administrator'),
            backgroundColor: const Color(0xFFD32F2F),
          ),
        ),
      ],
    );
  }
}

/// Doctors, patients — list + add / edit / delete.
class _AdminPeopleTab extends StatefulWidget {
  const _AdminPeopleTab({
    required this.title,
    required this.icon,
    required this.api,
    required this.kind,
    required this.loadAll,
    required this.itemTitle,
    required this.itemSubtitle,
    required this.trailingPill,
    required this.editorFields,
    required this.onSave,
    this.onDelete,
    required this.pendingTitle,
    required this.pendingSubtitle,
    required this.pendingId,
  });

  final String title;
  final IconData icon;
  final EmrFeaturesApi api;
  /// `patient`, `doctor`, or `admin` for create-user API.
  final String kind;
  final _Loader loadAll;
  final _TextFor itemTitle;
  final _TextFor itemSubtitle;
  final _TextFor trailingPill;
  final List<_EditorField> editorFields;
  final _Saver onSave;
  final _Deleter? onDelete;
  final _TextFor pendingTitle;
  final _TextFor pendingSubtitle;
  final _TextFor pendingId;

  @override
  State<_AdminPeopleTab> createState() => _AdminPeopleTabState();
}

class _AdminPeopleTabState extends State<_AdminPeopleTab> {
  int _reloadKey = 0;

  String get _approvalKind => widget.kind == 'doctor' ? 'provider' : widget.kind;

  String get _addLabel => switch (widget.kind) {
        'doctor' => 'Add provider',
        _ => 'Add patient',
      };

  void _reloadLists() => setState(() => _reloadKey++);

  void _openAdd() => _showCreateUserDialog(
        context,
        api: widget.api,
        kind: widget.kind,
        onCreated: _reloadLists,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Icon(
                  widget.kind == 'doctor' ? Icons.medical_services_outlined : Icons.person_add_alt_1_outlined,
                  color: const Color(0xFFD32F2F),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.kind == 'doctor'
                        ? 'Create a new doctor / provider account'
                        : 'Create a new patient account',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _openAdd,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(_addLabel),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _AdminApprovalsAndCrud(
            key: ValueKey(_reloadKey),
            title: widget.title,
            icon: widget.icon,
            api: widget.api,
            kind: _approvalKind,
            loadAll: widget.loadAll,
            itemTitle: widget.itemTitle,
            itemSubtitle: widget.itemSubtitle,
            trailingPill: widget.trailingPill,
            editorFields: widget.editorFields,
            onSave: widget.onSave,
            onDelete: widget.onDelete,
            pendingTitle: widget.pendingTitle,
            pendingSubtitle: widget.pendingSubtitle,
            pendingId: widget.pendingId,
            searchHint: widget.kind == 'doctor'
                ? 'Search providers by name, email, or ID…'
                : 'Search patients by name, email, or ID…',
            leadingBuilder: widget.kind == 'doctor'
                ? (m) => SpecialityAvatar(
                      name: (m['full_name'] ?? m['name'] ?? '?').toString(),
                      imageUrl: (m['profile_image'] ?? m['image'] ?? '').toString(),
                      size: 44,
                    )
                : (m) {
                    final name = (m['name'] ?? m['full_name'] ?? '?').toString();
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                    return CircleAvatar(
                      backgroundColor: const Color(0xFFD32F2F).withValues(alpha: 0.12),
                      child: Text(
                        initial,
                        style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold),
                      ),
                    );
                  },
            extraSearchText: (m) {
              final email = (m['email'] ?? '').toString();
              final id = (m['id'] ?? '').toString();
              final status = (m['status'] ?? m['profile_status'] ?? '').toString();
              return '$email $id $status';
            },
          ),
        ),
      ],
    );
  }
}

typedef _Loader = Future<List<Map<String, dynamic>>> Function();
typedef _Saver = Future<void> Function(int id, Map<String, dynamic> patch);
typedef _TextFor = String Function(Map<String, dynamic> m);

String _initialFieldText(Map<String, dynamic> item, _EditorField f) {
  final key = f.initialFromKey ?? f.keyName;
  if (f.keyName == 'is_staff') {
    final v = item['user_is_staff'] ?? item['is_staff'];
    return v == true ? 'true' : (v == false ? 'false' : v?.toString() ?? '');
  }
  if (f.keyName == 'is_superuser') {
    final v = item['user_is_superuser'] ?? item['is_superuser'];
    return v == true ? 'true' : (v == false ? 'false' : v?.toString() ?? '');
  }
  if (f.keyName == 'is_verified') {
    final v = item['is_verified'];
    return v == true ? 'true' : (v == false ? 'false' : v?.toString() ?? '');
  }
  return (item[key] ?? item[f.keyName] ?? '').toString();
}

Widget _trailingPill(String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFF4CAF50).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFF2E7D32),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

typedef _Deleter = Future<void> Function(int id);

class _AdminCrudList extends StatefulWidget {
  const _AdminCrudList({
    required this.title,
    required this.icon,
    required this.load,
    required this.itemTitle,
    required this.itemSubtitle,
    required this.editorFields,
    required this.onSave,
    this.trailingPill,
    this.onDelete,
    this.listPaddingBottom = 16,
    this.searchHint = 'Search…',
    this.leadingBuilder,
    this.extraSearchText,
    this.onAdd,
    this.addButtonLabel,
  });

  final String title;
  final IconData icon;
  final _Loader load;
  final _TextFor itemTitle;
  final _TextFor itemSubtitle;
  final _TextFor? trailingPill;
  final List<_EditorField> editorFields;
  final _Saver onSave;
  final _Deleter? onDelete;
  final double listPaddingBottom;
  final String searchHint;
  final Widget Function(Map<String, dynamic>)? leadingBuilder;
  final _TextFor? extraSearchText;
  final VoidCallback? onAdd;
  final String? addButtonLabel;

  @override
  State<_AdminCrudList> createState() => _AdminCrudListState();
}

class _AdminCrudListState extends State<_AdminCrudList> {
  late Future<List<Map<String, dynamic>>> _f = widget.load();
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _f = widget.load();
    });
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final idRaw = item['id'];
    final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
    if (id == null) return;

    final ctrls = <String, TextEditingController>{
      for (final f in widget.editorFields)
        f.keyName: TextEditingController(
          text: _initialFieldText(item, f),
        ),
    };

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit ${widget.title}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                if (widget.editorFields.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No editable fields configured for this list.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                    ),
                  ),
                for (final f in widget.editorFields) ...[
                  TextField(
                    controller: ctrls[f.keyName],
                    decoration: InputDecoration(
                      labelText: f.label,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Save changes'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );

    if (saved != true) {
      for (final c in ctrls.values) {
        c.dispose();
      }
      return;
    }

    final patch = <String, dynamic>{};
    for (final f in widget.editorFields) {
      final raw = ctrls[f.keyName]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      patch[f.keyName] = raw;
    }

    for (final c in ctrls.values) {
      c.dispose();
    }

    if (patch.isEmpty) return;

    try {
      await widget.onSave(id, patch);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: ${ApiAccessPlaceholder.shortMessage(e)}')),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    if (widget.onDelete == null) return;
    final idRaw = item['id'];
    final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
    if (id == null) return;
    final title = widget.itemTitle(item);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.title}?'),
        content: Text('Remove “$title”? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.onDelete!(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${ApiAccessPlaceholder.shortMessage(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load: ${ApiAccessPlaceholder.shortMessage(snap.error)}',
              ),
            ),
          );
        }

        final items = (snap.data ?? const <Map<String, dynamic>>[]);
        final q = _q.text.trim().toLowerCase();
        final filtered = q.isEmpty
            ? items
            : items.where((m) {
                final t = widget.itemTitle(m).toLowerCase();
                final s = widget.itemSubtitle(m).toLowerCase();
                final x = (widget.extraSearchText?.call(m) ?? '').toLowerCase();
                return t.contains(q) || s.contains(q) || x.contains(q);
              }).toList();

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, widget.listPaddingBottom),
          children: [
            Card(
              color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon, color: const Color(0xFFD32F2F), size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                          Text(
                            widget.onAdd != null
                                ? 'Tap a row to edit · use Add to create'
                                : 'Tap a row to edit',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onAdd != null) ...[
                      FilledButton.icon(
                        onPressed: widget.onAdd,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.person_add_rounded, size: 20),
                        label: Text(
                          widget.addButtonLabel ?? 'Add',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (_) {
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty) const Text('No records found.'),
            for (final m in filtered)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: widget.leadingBuilder != null
                      ? widget.leadingBuilder!(m)
                      : CircleAvatar(
                          backgroundColor: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                          child: Text(
                            (m['id'] ?? '').toString(),
                            style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold),
                          ),
                        ),
                  title: Text(widget.itemTitle(m), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(widget.itemSubtitle(m)),
                  trailing: widget.onDelete == null
                      ? (widget.trailingPill == null
                          ? const Icon(Icons.chevron_right_rounded)
                          : _trailingPill(widget.trailingPill!(m)))
                      : PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') {
                              _edit(m);
                            } else if (v == 'delete') {
                              _delete(m);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                  onTap: widget.onDelete == null ? () => _edit(m) : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EditorField {
  const _EditorField({
    required this.keyName,
    required this.label,
    this.initialFromKey,
  });

  final String keyName;
  final String label;

  /// Initial TextField value uses `item[initialFromKey]` when set (e.g. API returns `approved`, PATCH sends `status`).
  final String? initialFromKey;
}

class _AdminApprovalsOnly extends StatefulWidget {
  const _AdminApprovalsOnly({
    required this.title,
    required this.icon,
    required this.api,
    required this.kind,
    required this.pendingTitle,
    required this.pendingSubtitle,
    required this.pendingId,
  });

  final String title;
  final IconData icon;
  final EmrFeaturesApi api;
  final String kind;
  final _TextFor pendingTitle;
  final _TextFor pendingSubtitle;
  final _TextFor pendingId;

  @override
  State<_AdminApprovalsOnly> createState() => _AdminApprovalsOnlyState();
}

class _AdminApprovalsOnlyState extends State<_AdminApprovalsOnly> {
  bool _busy = false;
  Map<String, dynamic>? _data;
  Object? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final res = await widget.api.registrationsPending();
      if (mounted) {
        setState(() => _data = (res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{}));
      }
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _approve(int id) async {
    try {
      await widget.api.registrationsApprove(kind: widget.kind, id: id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Approved')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = _data;
    final data = (payload is Map<String, dynamic> ? (payload['data'] ?? payload) : null);
    final listRaw = (data is Map
        ? (widget.kind == 'provider' ? data['providers'] : data['patients'])
        : null);
    final rows = (listRaw is List ? listRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const <Map<String, dynamic>>[]);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
          child: ListTile(
            leading: Icon(widget.icon, color: const Color(0xFFD32F2F)),
            title: Text('${widget.title} approvals', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Pending registrations'),
            trailing: IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded)),
          ),
        ),
        const SizedBox(height: 12),
        if (_err != null) Text('Failed to load: $_err'),
        if (_busy) const LinearProgressIndicator(),
        if (!_busy && rows.isEmpty) const Text('No pending registrations.'),
        for (final m in rows)
          Card(
            child: ListTile(
              title: Text(widget.pendingTitle(m), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(widget.pendingSubtitle(m)),
              trailing: FilledButton(
                onPressed: _busy ? null : () {
                  final id = int.tryParse(widget.pendingId(m)) ?? 0;
                  if (id > 0) _approve(id);
                },
                child: const Text('Approve'),
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminApprovalsAndCrud extends StatelessWidget {
  const _AdminApprovalsAndCrud({
    super.key,
    required this.title,
    required this.icon,
    required this.api,
    required this.kind,
    required this.loadAll,
    required this.itemTitle,
    required this.itemSubtitle,
    required this.trailingPill,
    required this.editorFields,
    required this.onSave,
    required this.pendingTitle,
    required this.pendingSubtitle,
    required this.pendingId,
    this.onDelete,
    this.listPaddingBottom = 16,
    this.searchHint = 'Search…',
    this.leadingBuilder,
    this.extraSearchText,
    this.onAdd,
    this.addButtonLabel,
  });

  final String title;
  final IconData icon;
  final EmrFeaturesApi api;
  final String kind;
  final _Loader loadAll;
  final _TextFor itemTitle;
  final _TextFor itemSubtitle;
  final _TextFor trailingPill;
  final List<_EditorField> editorFields;
  final _Saver onSave;
  final _TextFor pendingTitle;
  final _TextFor pendingSubtitle;
  final _TextFor pendingId;
  final _Deleter? onDelete;
  final double listPaddingBottom;
  final String searchHint;
  final Widget Function(Map<String, dynamic>)? leadingBuilder;
  final _TextFor? extraSearchText;
  final VoidCallback? onAdd;
  final String? addButtonLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: _AdminApprovalsOnly(
            title: title,
            icon: icon,
            api: api,
            kind: kind,
            pendingTitle: (m) => pendingTitle(m),
            pendingSubtitle: (m) => pendingSubtitle(m),
            pendingId: (m) => pendingId(m),
          ),
        ),
        Expanded(
          flex: 3,
          child: _AdminCrudList(
            title: title,
            icon: icon,
            load: loadAll,
            itemTitle: itemTitle,
            itemSubtitle: itemSubtitle,
            trailingPill: trailingPill,
            editorFields: editorFields,
            onSave: onSave,
            onDelete: onDelete,
            listPaddingBottom: listPaddingBottom,
            searchHint: searchHint,
            leadingBuilder: leadingBuilder,
            extraSearchText: extraSearchText,
            onAdd: onAdd,
            addButtonLabel: addButtonLabel,
          ),
        ),
      ],
    );
  }
}
