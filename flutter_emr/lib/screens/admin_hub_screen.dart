import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';

class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

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
  Widget build(BuildContext context) {
    const primary = Color(0xFFD32F2F);
    final canPop = Navigator.canPop(context);
    // Scaffold gives Material context; TabBar must have a Material ancestor.
    // Opening from Settings ([Navigator.push]) had no Material above this widget.
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: canPop
            ? AppBar(
                title: const Text('Admin hub'),
                backgroundColor: primary,
                foregroundColor: Colors.white,
              )
            : null,
        body: Column(
          children: [
            Material(
              color: primary,
              elevation: 0,
              child: TabBar(
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
                children: [
                  for (int i = 0; i < _tabs.length; i++)
                    _AdminTab(
                      title: _tabs[i],
                      icon: _icons[i],
                      apiClient: apiClient,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      return _AdminCrudList(
        title: title,
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
      return _AdminCrudList(
        title: title,
        icon: icon,
        load: () async {
          final data = await api.countries();
          final v = (data is Map ? (data['data'] ?? data['results'] ?? data) : data);
          if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          return const <Map<String, dynamic>>[];
        },
        itemTitle: (m) => (m['country_name'] ?? m['name'] ?? '').toString(),
        itemSubtitle: (m) => (m['country_code'] ?? '').toString(),
        editorFields: const [
          _EditorField(keyName: 'country_name', label: 'Country name'),
          _EditorField(keyName: 'country_code', label: 'Country code'),
        ],
        onSave: (id, patch) => api.adminPatchCountry(id, patch),
      );
    }

    if (title == 'Specialities') {
      return _AdminCrudList(
        title: title,
        icon: icon,
        load: () async {
          final data = await api.specialities();
          final v = (data is Map ? (data['data'] ?? data['results'] ?? data) : data);
          if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          return const <Map<String, dynamic>>[];
        },
        itemTitle: (m) => (m['speciality_name'] ?? m['name'] ?? '').toString(),
        itemSubtitle: (m) => (m['country'] ?? m['country_id'] ?? '').toString(),
        editorFields: const [
          _EditorField(keyName: 'speciality_name', label: 'Speciality name'),
          _EditorField(keyName: 'speciality_image', label: 'Image URL (optional)'),
        ],
        onSave: (id, patch) => api.adminPatchSpeciality(id, patch),
      );
    }

    if (title == 'Providers') {
      return _AdminApprovalsAndCrud(
        title: title,
        icon: icon,
        api: api,
        kind: 'provider',
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
          _EditorField(keyName: 'speciality_id', label: 'Speciality ID'),
          _EditorField(keyName: 'consultation_fee', label: 'Consultation fee'),
        ],
        onSave: (id, patch) => api.adminPatchProvider(id, patch),
        pendingTitle: (m) => (m['full_name'] ?? '').toString(),
        pendingSubtitle: (m) => (m['email'] ?? '').toString(),
        pendingId: (m) => (m['id'] ?? 0).toString(),
      );
    }

    if (title == 'Patients') {
      return _AdminApprovalsOnly(
        title: title,
        icon: icon,
        api: api,
        kind: 'patient',
        pendingTitle: (m) => (m['name'] ?? m['full_name'] ?? '').toString(),
        pendingSubtitle: (m) => (m['email'] ?? '').toString(),
        pendingId: (m) => (m['id'] ?? 0).toString(),
      );
    }

    if (title == 'Appointments') {
      return _AdminCrudList(
        title: title,
        icon: icon,
        load: () async {
          final data = await api.allAppointments();
          final root = data is Map ? data : const {};
          final d = root['data'] is Map ? root['data'] as Map : root;
          final list = d['appointments'];
          if (list is List) {
            return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          }
          return const <Map<String, dynamic>>[];
        },
        itemTitle: (m) => '${m['date'] ?? ''} ${m['time'] ?? ''}'.trim(),
        itemSubtitle: (m) {
          final p = m['patient'] is Map ? (m['patient'] as Map)['name'] : '';
          final pr = m['provider'] is Map ? (m['provider'] as Map)['full_name'] : '';
          return 'Patient: $p · Provider: $pr';
        },
        editorFields: const [],
        onSave: (id, patch) async {},
      );
    }

    final mockData = List.generate(5, (i) => {
          'id': i + 1,
          'name': '$title Item ${i + 1}',
          'status': i % 2 == 0 ? 'Active' : 'Inactive'
        });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header Card
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
                  child: Icon(icon, color: const Color(0xFFD32F2F), size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Manage ${title.toLowerCase()} records', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Add New'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.filter_list),
                label: const Text('Filter'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Data List
        Text('Recent Records', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...mockData.map((item) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFD32F2F).withValues(alpha: 0.1),
              child: Text(item['id'].toString(), style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
            ),
            title: Text(item['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('ID: ${item['id']}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: item['status'] == 'Active' ? const Color(0xFF4CAF50).withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                item['status']?.toString() ?? '',
                style: TextStyle(
                  color: item['status'] == 'Active' ? const Color(0xFF4CAF50) : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            onTap: () {},
          ),
        )),
        const SizedBox(height: 16),

        // Summary Stats
        Row(
          children: [
            Expanded(child: _buildStatCard('Total', '${mockData.length}', const Color(0xFF2196F3))),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('Active', '${mockData.where((e) => e['status'] == 'Active').length}', const Color(0xFF4CAF50))),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('Inactive', '${mockData.where((e) => e['status'] == 'Inactive').length}', Colors.grey)),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// (Removed obsolete styleWith extension)

typedef _Loader = Future<List<Map<String, dynamic>>> Function();
typedef _Saver = Future<void> Function(int id, Map<String, dynamic> patch);
typedef _TextFor = String Function(Map<String, dynamic> m);

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
  });

  final String title;
  final IconData icon;
  final _Loader load;
  final _TextFor itemTitle;
  final _TextFor itemSubtitle;
  final _TextFor? trailingPill;
  final List<_EditorField> editorFields;
  final _Saver onSave;

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

  void _reload() => setState(() => _f = widget.load());

  Future<void> _edit(Map<String, dynamic> item) async {
    final idRaw = item['id'];
    final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
    if (id == null) return;

    final ctrls = <String, TextEditingController>{
      for (final f in widget.editorFields)
        f.keyName: TextEditingController(text: (item[f.keyName] ?? '').toString())
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit ${widget.title}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
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
        SnackBar(content: Text('Save failed: $e')),
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
              child: Text('Failed to load: ${snap.error}'),
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
                return t.contains(q) || s.contains(q);
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
                          Text('Tap a row to edit', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                        ],
                      ),
                    ),
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
                hintText: 'Search…',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty) const Text('No records found.'),
            for (final m in filtered)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                    child: Text(
                      (m['id'] ?? '').toString(),
                      style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(widget.itemTitle(m), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(widget.itemSubtitle(m)),
                  trailing: widget.trailingPill == null
                      ? const Icon(Icons.chevron_right_rounded)
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.trailingPill!(m),
                            style: const TextStyle(
                              color: Color(0xFF2E7D32),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                  onTap: () => _edit(m),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EditorField {
  const _EditorField({required this.keyName, required this.label});
  final String keyName;
  final String label;
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
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final res = await widget.api.registrationsPending();
      setState(() => _data = (res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{}));
    } catch (e) {
      setState(() => _err = e);
    } finally {
      setState(() => _busy = false);
    }
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
          ),
        ),
      ],
    );
  }
}
