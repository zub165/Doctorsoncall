import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:url_launcher/url_launcher.dart';

import '../models/medical_record.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../services/medical_records_api.dart';
import '../services/offline_db.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/api_access_placeholder.dart';
import 'medical_record_detail_screen.dart';

/// Records list + AI assistant (matches **`/api/medical-records/`** family on the server).
class MedicalRecordsHubScreen extends StatefulWidget {
  const MedicalRecordsHubScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<MedicalRecordsHubScreen> createState() =>
      _MedicalRecordsHubScreenState();
}

class _MedicalRecordsHubScreenState extends State<MedicalRecordsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  late final MedicalRecordsApi _api = MedicalRecordsApi(widget.apiClient);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: AppColors.primary,
          child: TabBar(
            controller: _tab,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.folder_shared_outlined), text: 'Records'),
              Tab(icon: Icon(Icons.psychology_outlined), text: 'AI assistant'),
              Tab(icon: Icon(Icons.attach_file_rounded), text: 'Documents'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _RecordsTab(api: _api, apiClient: widget.apiClient),
              _AiAssistantTab(api: _api),
              _DocumentsTab(api: _api),
            ],
          ),
        ),
      ],
    );
  }
}

class _DocumentsTab extends StatefulWidget {
  const _DocumentsTab({required this.api});

  final MedicalRecordsApi api;

  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _docs = const [];
  bool _uploading = false;
  bool _processing = false;
  int? _processingId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await widget.api.listDocuments();
      setState(() {
        _docs = docs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _docs = const [];
        _loading = false;
      });
    }
  }

  Future<void> _pickAndUpload() async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'txt'],
      );
      final path = res?.files.single.path;
      if (path == null || path.isEmpty) {
        setState(() => _uploading = false);
        return;
      }
      final name = res?.files.single.name;
      await widget.api.uploadDocument(
        filePath: path,
        filename: name,
      );
      if (!mounted) return;
      setState(() => _uploading = false);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploaded. Tap Process to generate report.')),
      );
    } catch (e) {
      setState(() {
        _uploading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _process(int id) async {
    setState(() {
      _processing = true;
      _processingId = id;
      _error = null;
    });
    try {
      await widget.api.processDocument(id);
      if (!mounted) return;
      setState(() {
        _processing = false;
        _processingId = null;
      });
      await _reload();
    } catch (e) {
      setState(() {
        _processing = false;
        _processingId = null;
        _error = e.toString();
      });
    }
  }

  Map<String, dynamic> _unwrapDoc(Map<String, dynamic> row) {
    final d = row['document'];
    if (d is Map) return Map<String, dynamic>.from(d);
    return row;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null && _error!.isNotEmpty) {
      return ApiAccessPlaceholder(
        title: 'Documents unavailable',
        message: _error!,
        icon: Icons.attach_file_rounded,
        onRetry: _reload,
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Upload documents',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: _uploading ? null : _pickAndUpload,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_file_rounded),
                label: Text(_uploading ? 'Uploading…' : 'Upload'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'After upload, tap Process to run OCR/text extraction and generate a doctor report.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          if (_docs.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No documents yet.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            )
          else
            ..._docs.map((row) {
              final doc = _unwrapDoc(row);
              final id = (doc['id'] is int)
                  ? doc['id'] as int
                  : int.tryParse('${doc['id'] ?? ''}');
              final name = (doc['original_name'] ??
                      doc['file'] ??
                      'Document')
                  .toString();
              final status = (doc['status'] ?? 'uploaded').toString();
              final err = (doc['error_message'] ?? '').toString();
              final summary = (doc['ai_summary'] ?? '').toString();
              final processingThis = _processing && _processingId == id;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Status: $status',
                          style: TextStyle(color: Colors.grey.shade700)),
                      if (err.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(err,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: (id == null || _processing)
                                  ? null
                                  : () => _process(id),
                              child: processingThis
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Process'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: () async {
                              final fileUrl = (doc['file_url'] ?? '').toString();
                              if (fileUrl.isEmpty) return;
                              final uri = Uri.tryParse(fileUrl);
                              if (uri == null) return;
                              // ignore: deprecated_member_use
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            },
                            child: const Text('View'),
                          ),
                        ],
                      ),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Doctor report',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(summary),
                        ),
                      ],
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

class _RecordsTab extends StatefulWidget {
  const _RecordsTab({required this.api, required this.apiClient});

  final MedicalRecordsApi api;
  final EmergencyApiClient apiClient;

  @override
  State<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<_RecordsTab> {
  late final OfflineDb _db = OfflineDb();
  late Future<List<MedicalRecord>> _future = _load();

  Future<void> _openApiImport() async {
    final urlC = TextEditingController();
    final emailC = TextEditingController();
    final hintC = TextEditingController();
    String fetched = '';
    String aiSummary = '';
    bool busy = false;
    String? err;

    Future<void> fetchAndSummarize(StateSetter setModal) async {
      final url = urlC.text.trim();
      if (url.isEmpty) return;
      setModal(() {
        busy = true;
        err = null;
        fetched = '';
        aiSummary = '';
      });
      try {
        final dio = Dio();
        final r = await dio.get<dynamic>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        fetched = (r.data ?? '').toString();
        if (fetched.length > 200000) fetched = fetched.substring(0, 200000);

        final prompt = '''
Summarize this external medical record for an EMR patient file.
Return plain text summary with key sections:
Chief complaint, History, Medications, Allergies, Labs/Imaging, Assessment/Plan.

RECORD:
$fetched
''';
        final res = await widget.api.aiAssist(query: prompt);
        aiSummary = (res['summary'] ?? res['answer'] ?? res['response'] ?? res)
            .toString();
      } catch (e) {
        err = e.toString();
      } finally {
        setModal(() => busy = false);
      }
    }

    Future<void> submit(StateSetter setModal) async {
      final url = urlC.text.trim();
      final email = emailC.text.trim();
      if (url.isEmpty || email.isEmpty) return;
      setModal(() {
        busy = true;
        err = null;
      });
      try {
        await EmrFeaturesApi(widget.apiClient).importSubmit(
          sourceUrl: url,
          patientEmail: email,
          patientHint: hintC.text.trim(),
          rawPayload: fetched,
          aiSummary: aiSummary,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submitted to Admin for merge.')),
        );
      } catch (e) {
        setModal(() => err = e.toString());
      } finally {
        setModal(() => busy = false);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
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
                      'Import via API link',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: urlC,
                      decoration: const InputDecoration(
                        labelText: 'Hospital/Facility API URL',
                        hintText: 'https://...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailC,
                      decoration: const InputDecoration(
                        labelText: 'Patient email (to match/merge)',
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: hintC,
                      decoration: const InputDecoration(
                        labelText: 'Patient hint (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                busy ? null : () => fetchAndSummarize(setModal),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Fetch & summarize'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: busy || fetched.isEmpty
                                ? null
                                : () => submit(setModal),
                            icon: const Icon(Icons.send_rounded),
                            label: const Text('Submit'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (busy) const LinearProgressIndicator(),
                    if (err != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Error: $err',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (aiSummary.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'AI summary',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(aiSummary),
                      ),
                    ],
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    urlC.dispose();
    emailC.dispose();
    hintC.dispose();
  }

  void _reload() {
    final f = _load();
    setState(() {
      _future = f;
    });
  }

  Future<List<MedicalRecord>> _load() async {
    // Always show offline records, then merge server records when available.
    final offlineRows = await (_db.select(_db.localMedicalRecords)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(200))
        .get();
    final offline = <MedicalRecord>[];
    for (final r in offlineRows) {
      try {
        final m = jsonDecode(r.json);
        if (m is Map) {
          offline.add(MedicalRecord.fromJson(Map<String, dynamic>.from(m)));
        }
      } catch (_) {
        // ignore malformed local row
      }
    }

    try {
      final online = await widget.api.listRecords();
      final byId = <String, MedicalRecord>{};
      for (final r in online) {
        byId[r.id] = r;
      }
      // Prefer offline copy (it may include latest AI summary before sync).
      for (final r in offline) {
        byId[r.id] = r;
      }
      final merged = byId.values.toList();
      merged.sort((a, b) => b.date.compareTo(a.date));
      return merged;
    } catch (_) {
      return offline;
    }
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _CreateMedicalRecordScreen(
          api: widget.api,
          apiClient: widget.apiClient,
          db: _db,
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        final n = widget.api.listRecords();
        setState(() => _future = n);
        await n;
      },
      child: FutureBuilder<List<MedicalRecord>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          if (snap.hasError) {
            final e = snap.error;
            if (e is DioException && e.response?.statusCode == 401) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                  ApiAccessPlaceholder(
                    title: 'Sign in for medical records',
                    message: 'Your account is required to view clinical data.',
                    requireSignIn: true,
                    onRetry: _reload,
                  ),
                ],
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                ApiAccessPlaceholder(
                  title: 'Could not load records',
                  message: e.toString(),
                  icon: Icons.folder_off_outlined,
                  onRetry: _reload,
                ),
              ],
            );
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.12),
                Icon(
                  Icons.article_outlined,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No medical records yet',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'When your provider syncs visits, labs, and notes they will appear here. '
                  'Use the AI tab to ask questions once records exist.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _openCreate,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create medical record (offline)'),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = list[i];
              if (i == 0) {
                return Column(
                  children: [
                    Card(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      child: ListTile(
                        leading: const Icon(
                          Icons.link_rounded,
                          color: AppColors.primary,
                        ),
                        title: const Text(
                          'Import via API link',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Fetch a facility API → AI summary → Admin merges into your file',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _openApiImport,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _openCreate,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _RecordTile(theme: theme, r: r, api: widget.api),
                  ],
                );
              }
              return _RecordTile(theme: theme, r: r, api: widget.api);
            },
          );
        },
      ),
    );
  }

}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.theme, required this.r, required this.api});

  final ThemeData theme;
  final MedicalRecord r;
  final MedicalRecordsApi api;

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          child: Icon(
            Icons.description_outlined,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          r.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.recordType != null)
              Text(r.recordType!, style: theme.textTheme.bodySmall),
            Text(
              _formatDate(r.date),
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            if (r.aiHighlight != null && r.aiHighlight!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: Colors.purple.shade700,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r.aiHighlight!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.purple.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => MedicalRecordDetailScreen(
                api: api,
                recordId: r.id,
                preview: r,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CreateMedicalRecordScreen extends StatefulWidget {
  const _CreateMedicalRecordScreen({
    required this.api,
    required this.apiClient,
    required this.db,
  });

  final MedicalRecordsApi api;
  final EmergencyApiClient apiClient;
  final OfflineDb db;

  @override
  State<_CreateMedicalRecordScreen> createState() =>
      _CreateMedicalRecordScreenState();
}

class _CreateMedicalRecordScreenState extends State<_CreateMedicalRecordScreen> {
  final _hospitalName = TextEditingController();
  final _hospitalId = TextEditingController();
  final _presenting = TextEditingController();
  final _pmh = TextEditingController();
  final _social = TextEditingController();
  final _surgical = TextEditingController();
  final _notes = TextEditingController();

  final _symptomName = TextEditingController();
  final _symptomSeverity = TextEditingController();

  bool _busyAi = false;
  String? _aiError;

  final List<Symptom> _symptoms = [];
  final List<Map<String, String>> _medications = [];
  final List<String> _allergies = [];
  final List<Map<String, String>> _labs = [];
  final List<Map<String, String>> _imaging = [];

  @override
  void dispose() {
    _hospitalName.dispose();
    _hospitalId.dispose();
    _presenting.dispose();
    _pmh.dispose();
    _social.dispose();
    _surgical.dispose();
    _notes.dispose();
    _symptomName.dispose();
    _symptomSeverity.dispose();
    super.dispose();
  }

  String _newLocalId() => 'local-${DateTime.now().millisecondsSinceEpoch}';

  Future<void> _addAllergy() async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add allergy'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: 'e.g. Penicillin'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) setState(() => _allergies.add(v));
  }

  Future<void> _addMapItem({
    required String title,
    required List<Map<String, String>> target,
    required List<String> keys,
  }) async {
    final controllers = {for (final k in keys) k: TextEditingController()};
    final r = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: controllers[k],
                  decoration: InputDecoration(labelText: k),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final m = <String, String>{};
              for (final k in keys) {
                final val = controllers[k]!.text.trim();
                if (val.isNotEmpty) m[k] = val;
              }
              Navigator.pop(context, m.isEmpty ? null : m);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (r != null && r.isNotEmpty) setState(() => target.add(r));
  }

  Future<void> _generateAiSummary() async {
    setState(() {
      _busyAi = true;
      _aiError = null;
    });
    try {
      final prompt = StringBuffer()
        ..writeln('Summarize this visit as a clinician note with assessment and next steps.')
        ..writeln('Presenting complaints: ${_presenting.text.trim()}')
        ..writeln('Symptoms: ${_symptoms.map((s) => '${s.name}(${s.severity ?? ''})').join(', ')}')
        ..writeln('PMH: ${_pmh.text.trim()}')
        ..writeln('Social: ${_social.text.trim()}')
        ..writeln('Surgical: ${_surgical.text.trim()}')
        ..writeln('Meds: ${_medications.map((m) => m['name'] ?? m.toString()).join(', ')}')
        ..writeln('Allergies: ${_allergies.join(', ')}')
        ..writeln('Labs: ${_labs.map((m) => m['name'] ?? m.toString()).join(', ')}')
        ..writeln('Imaging: ${_imaging.map((m) => m['name'] ?? m.toString()).join(', ')}');

      final res = await widget.api.aiAssist(query: prompt.toString());
      final summary = res['summary']?.toString() ??
          res['answer']?.toString() ??
          res['text']?.toString() ??
          res.toString();
      _notes.text = summary;
    } on DioException catch (e) {
      setState(() => _aiError = e.message ?? 'AI request failed');
    } catch (e) {
      setState(() => _aiError = e.toString());
    } finally {
      if (mounted) setState(() => _busyAi = false);
    }
  }

  Future<void> _save() async {
    final record = MedicalRecord(
      id: _newLocalId(),
      date: DateTime.now(),
      time: TimeOfDay.now().format(context),
      symptoms: _symptoms,
      status: 'Completed',
      hospitalId: _hospitalId.text.trim(),
      hospitalName: _hospitalName.text.trim(),
      notes: _notes.text.trim(),
      presentingComplaints: _presenting.text.trim(),
      pastMedicalHistory: _pmh.text.trim(),
      socialHistory: _social.text.trim(),
      surgicalHistory: _surgical.text.trim(),
      medications: _medications,
      allergies: _allergies,
      labs: _labs,
      imaging: _imaging,
      aiHighlight: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      raw: {
        'source': 'offline_create',
      },
    );

    await widget.api.saveOffline(db: widget.db, record: record);
    // Best-effort: try to sync immediately (safe if offline).
    try {
      await SyncService(client: widget.apiClient, db: widget.db).syncAll();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create medical record'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _hospitalName,
            decoration: const InputDecoration(labelText: 'Hospital name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hospitalId,
            decoration: const InputDecoration(labelText: 'Hospital ID'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _presenting,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Presenting complaints'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pmh,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Past medical history'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _social,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Social history'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _surgical,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Surgical history'),
          ),
          const SizedBox(height: 16),
          Text('Symptoms', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _symptomName,
                  decoration: const InputDecoration(hintText: 'Name'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _symptomSeverity,
                  decoration: const InputDecoration(hintText: 'Severity'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () {
                  final name = _symptomName.text.trim();
                  if (name.isEmpty) return;
                  setState(
                    () => _symptoms.add(
                      Symptom(
                        name: name,
                        severity: _symptomSeverity.text.trim().isEmpty
                            ? null
                            : _symptomSeverity.text.trim(),
                      ),
                    ),
                  );
                  _symptomName.clear();
                  _symptomSeverity.clear();
                },
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (_symptoms.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in _symptoms)
                  Chip(
                    label: Text('${s.name}${s.severity == null ? '' : ' (${s.severity})'}'),
                    onDeleted: () => setState(() => _symptoms.remove(s)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _SectionRow(
            title: 'Medications',
            onAdd: () => _addMapItem(
              title: 'Add medication',
              target: _medications,
              keys: const ['name', 'dosage', 'frequency'],
            ),
          ),
          _MapChips(items: _medications, onRemove: (i) => setState(() => _medications.removeAt(i))),
          const SizedBox(height: 12),
          _SectionRow(
            title: 'Allergies',
            onAdd: _addAllergy,
          ),
          if (_allergies.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final a in _allergies)
                  Chip(
                    label: Text(a),
                    onDeleted: () => setState(() => _allergies.remove(a)),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          _SectionRow(
            title: 'Labs',
            onAdd: () => _addMapItem(
              title: 'Add lab',
              target: _labs,
              keys: const ['name', 'value', 'unit', 'note'],
            ),
          ),
          _MapChips(items: _labs, onRemove: (i) => setState(() => _labs.removeAt(i))),
          const SizedBox(height: 12),
          _SectionRow(
            title: 'Imaging',
            onAdd: () => _addMapItem(
              title: 'Add imaging',
              target: _imaging,
              keys: const ['name', 'finding', 'note'],
            ),
          ),
          _MapChips(items: _imaging, onRemove: (i) => setState(() => _imaging.removeAt(i))),
          const SizedBox(height: 16),
          _SectionRow(
            title: 'AI summary → Notes',
            onAdd: _busyAi ? null : _generateAiSummary,
            addLabel: _busyAi ? 'Generating…' : 'Generate',
            addIcon: Icons.auto_awesome,
          ),
          if (_aiError != null) ...[
            const SizedBox(height: 8),
            Text(_aiError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save locally (and sync when online)'),
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.title,
    required this.onAdd,
    this.addLabel = 'Add',
    this.addIcon = Icons.add_rounded,
  });

  final String title;
  final VoidCallback? onAdd;
  final String addLabel;
  final IconData addIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: Icon(addIcon),
          label: Text(addLabel),
        ),
      ],
    );
  }
}

class _MapChips extends StatelessWidget {
  const _MapChips({required this.items, required this.onRemove});

  final List<Map<String, String>> items;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      children: [
        for (var i = 0; i < items.length; i++)
          Chip(
            label: Text(items[i]['name'] ?? items[i].values.first),
            onDeleted: () => onRemove(i),
          ),
      ],
    );
  }
}

class _AiAssistantTab extends StatefulWidget {
  const _AiAssistantTab({required this.api});

  final MedicalRecordsApi api;

  @override
  State<_AiAssistantTab> createState() => _AiAssistantTabState();
}

class _AiAssistantTabState extends State<_AiAssistantTab> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _last;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.api.aiAssist(query: q);
      setState(() => _last = res);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        setState(() => _error = 'sign_in');
      } else {
        setState(() => _error = e.message ?? 'Request failed');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_error == 'sign_in') {
      return ApiAccessPlaceholder(
        title: 'Sign in to use AI',
        message:
            'The assistant needs an authenticated session to reference your charts safely.',
        requireSignIn: true,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.deepPurple.shade50,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.deepPurple.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'AI responses are informational only — not a diagnosis. '
                    'Always follow your clinician’s advice. Backend must implement **`POST …/medical-records/ai-assist/`**.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.deepPurple.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: 'Ask about your records',
            hintText: 'Summarize my last labs and flag anything urgent',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _send,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded),
          label: const Text('Get AI insight'),
        ),
        if (_error != null && _error != 'sign_in') ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (_last != null) ...[
          const SizedBox(height: 20),
          Text(
            'Response',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_last!['summary'] != null)
                    Text(
                      _last!['summary'].toString(),
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (_last!['suggestions'] is List) ...[
                    const SizedBox(height: 12),
                    Text('Suggestions', style: theme.textTheme.labelLarge),
                    ...(_last!['suggestions'] as List).map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• '),
                            Expanded(child: Text(s.toString())),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
