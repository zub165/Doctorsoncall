import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/medical_record.dart';
import '../services/consented_ai_assist.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../services/medical_records_api.dart';
import '../services/offline_db.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/api_access_placeholder.dart';
import '../widgets/ai_disclosure_banner.dart';
import '../widgets/medical_disclaimer_banner.dart';
import 'medical_record_detail_screen.dart';

/// Records list + AI assistant (matches **`/api/medical-records/`** family on the server).
class MedicalRecordsHubScreen extends StatefulWidget {
  const MedicalRecordsHubScreen({
    super.key,
    required this.apiClient,
    this.role,
  });

  final EmergencyApiClient apiClient;
  final String? role;

  @override
  State<MedicalRecordsHubScreen> createState() =>
      _MedicalRecordsHubScreenState();
}

class _MedicalRecordsHubScreenState extends State<MedicalRecordsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);
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
              Tab(icon: Icon(Icons.ios_share_rounded), text: 'Share'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _RecordsTab(api: _api, apiClient: widget.apiClient, role: widget.role),
              _AiAssistantTab(api: _api),
              _DocumentsTab(api: _api, apiClient: widget.apiClient),
              _ShareTab(api: _api, apiClient: widget.apiClient, role: widget.role),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShareTab extends StatefulWidget {
  const _ShareTab({
    required this.api,
    required this.apiClient,
    required this.role,
  });

  final MedicalRecordsApi api;
  final EmergencyApiClient apiClient;
  final String? role;

  @override
  State<_ShareTab> createState() => _ShareTabState();
}

class _ShareTabState extends State<_ShareTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  List<Map<String, dynamic>> _providers = const [];
  int? _providerId;
  final _note = TextEditingController();
  bool _includeEmail = false;
  bool _busy = false;
  bool _localSharing = false;

  bool get _isDoctorish {
    final r = (widget.role ?? '').toLowerCase().trim();
    return r == 'doctor' || r == 'provider' || r == 'physician' || r == 'admin' || r == 'staff' || r == 'administrator';
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadProviders();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadProviders() async {
    try {
      final data = await EmrFeaturesApi(widget.apiClient).providers();
      List<Map<String, dynamic>> list = [];
      if (data is Map && data['results'] is List) {
        list = (data['results'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } else if (data is List) {
        list = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (!mounted) return;
      setState(() => _providers = list);
    } catch (_) {
      // ignore; share can still work if provider_id is entered elsewhere
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = _isDoctorish ? await widget.api.inboxShares() : await widget.api.myShares();
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      // IMPORTANT: even if backend share endpoints are missing (404),
      // we still want to show local share (Messages/WhatsApp/Bluetooth).
      if (e is DioException && e.response?.statusCode == 404) {
        setState(() {
          _items = const [];
          _loading = false;
          _error = null;
        });
        return;
      }
      setState(() {
        _error = e.toString();
        _items = const [];
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> row) {
    final s = row['share'];
    if (s is Map) return Map<String, dynamic>.from(s);
    return row;
  }

  Future<void> _send() async {
    final pid = _providerId;
    final note = _note.text.trim();
    if (pid == null || pid <= 0 || note.isEmpty) {
      setState(() => _error = 'Select doctor and write a note.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.createShare(
        providerId: pid,
        note: note,
        includePatientEmail: _includeEmail,
      );
      _note.clear();
      _includeEmail = false;
      if (!mounted) return;
      setState(() => _busy = false);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shared with doctor.')),
      );
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _shareViaSystem() async {
    final text = _note.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write something to share first.');
      return;
    }
    setState(() {
      _localSharing = true;
      _error = null;
    });
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: 'Doctor On Call — share',
          sharePositionOrigin: Rect.fromLTWH(
            0,
            0,
            MediaQuery.of(context).size.width,
            MediaQuery.of(context).size.height,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Share failed: $e');
    } finally {
      if (mounted) setState(() => _localSharing = false);
    }
  }

  Future<void> _shareToWhatsApp() async {
    final text = _note.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write something to share first.');
      return;
    }
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() => _error = 'Could not open WhatsApp.');
      }
    } catch (e) {
      setState(() => _error = 'Could not open WhatsApp: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return RefreshIndicator(
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
                    'HIPAA / Safety disclaimer',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'For care coordination only. Do not share highly sensitive information unless necessary. '
                    'AI summaries may be incomplete; clinicians must verify against source documents. '
                    'If emergency, call local emergency services.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share via apps (Bluetooth · Messages · WhatsApp)',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _note,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Text to share',
                      hintText: 'Write or paste the summary/notes you want to share…',
                    ),
                    enabled: !_busy && !_localSharing,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: (_busy || _localSharing) ? null : _shareViaSystem,
                        icon: _localSharing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.share_rounded),
                        label: Text(_localSharing ? 'Sharing…' : 'Share'),
                      ),
                      OutlinedButton.icon(
                        onPressed: (_busy || _localSharing) ? null : _shareToWhatsApp,
                        icon: const Icon(Icons.chat_rounded),
                        label: const Text('WhatsApp'),
                      ),
                    ],
                  ),
                  if (_error != null && _error!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_isDoctorish) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share with doctor',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      value: _providerId,
                      decoration: const InputDecoration(labelText: 'Doctor'),
                      items: _providers
                          .where((p) => p['id'] != null)
                          .map((p) => DropdownMenuItem<int>(
                                value: int.tryParse('${p['id']}'),
                                child: Text((p['full_name'] ?? p['name'] ?? 'Provider').toString()),
                              ))
                          .toList(),
                      onChanged: _busy ? null : (v) => setState(() => _providerId = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _note,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'What do you want to share?',
                        hintText: 'Symptoms, concerns, key history, questions…',
                      ),
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: _includeEmail,
                      onChanged: _busy ? null : (v) => setState(() => _includeEmail = v),
                      title: const Text('Allow doctor to email me the summary'),
                      subtitle: const Text('Consent-based. Uses your patient profile email.'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy ? null : _send,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send),
                      label: Text(_busy ? 'Sharing…' : 'Share'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            _isDoctorish ? 'Inbox' : 'My shares',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (_items.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No shares yet.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            )
          else
            ..._items.map((row) {
              final s = _unwrap(row);
              final id = int.tryParse('${s['id'] ?? ''}');
              final patientName = (s['patient']?['name'] ?? s['patient']?['email'] ?? '').toString();
              final providerName = (s['provider']?['full_name'] ?? '').toString();
              final summary = (s['ai_summary'] ?? '').toString();
              final note = (s['patient_note'] ?? '').toString();
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isDoctorish
                            ? (patientName.isEmpty ? 'Patient share' : patientName)
                            : (providerName.isEmpty ? 'Doctor share' : providerName),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if ((s['share_kind'] ?? '').toString() == 'triage') ...[
                        const SizedBox(height: 6),
                        Chip(
                          label: const Text('Triage vitals'),
                          backgroundColor: Colors.teal.shade100,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(note, style: TextStyle(color: Colors.grey.shade800)),
                      ],
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('AI summary', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.purple.shade800)),
                        const SizedBox(height: 6),
                        Text(summary),
                      ],
                      if (_isDoctorish && id != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                await widget.api.deleteShare(id);
                                if (!mounted) return;
                                await _load();
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete'),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: () async {
                                if (!mounted) return;
                                final messenger = ScaffoldMessenger.of(context);
                                final res = await widget.api.emailShare(id);
                                final msg = (res['message'] ?? 'Sent').toString();
                                messenger.showSnackBar(SnackBar(content: Text(msg)));
                              },
                              icon: const Icon(Icons.email_outlined),
                              label: const Text('Email patient'),
                            ),
                          ],
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

class _DocumentsTab extends StatefulWidget {
  const _DocumentsTab({required this.api, required this.apiClient});

  final MedicalRecordsApi api;
  final EmergencyApiClient apiClient;

  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> {
  late final OfflineDb _db = OfflineDb();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _docs = const [];
  bool _uploading = false;
  bool _processing = false;
  int? _processingId;
  bool _ocring = false;
  String? _ocrText;
  bool _summarizing = false;
  String? _aiSummary;
  int? _shareProviderId;
  bool _shareIncludeEmail = false;
  bool _sharing = false;
  List<Map<String, dynamic>> _providers = const [];

  @override
  void initState() {
    super.initState();
    _reload();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    try {
      final data = await EmrFeaturesApi(widget.apiClient).providers();
      List<Map<String, dynamic>> list = [];
      if (data is Map && data['results'] is List) {
        list = (data['results'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (data is List) {
        list = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (!mounted) return;
      setState(() => _providers = list);
    } catch (_) {
      // ignore
    }
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
      String msg = e.toString();
      if (e is DioException) {
        final code = e.response?.statusCode;
        if (code == 404) {
          msg =
              'This server does not support Documents yet (404).\n\n'
              'Fix: deploy/update the Django EMR backend to include `GET/POST /api/documents/` and `POST /api/documents/<id>/`.\n'
              'If you are running locally, set `--dart-define=EMR_API_BASE_URL=http://127.0.0.1:8012/api/` and restart the app.';
        } else if (code == 401 || code == 403) {
          msg = 'Sign in is required to view documents.';
        }
      }
      setState(() {
        _error = msg;
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

  Future<void> _pickAndOcrDirect() async {
    setState(() {
      _ocring = true;
      _ocrText = null;
      _error = null;
    });
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );
      final path = res?.files.single.path;
      if (path == null || path.isEmpty) {
        setState(() => _ocring = false);
        return;
      }
      final name = res?.files.single.name;
      final lower = (name ?? path).toLowerCase();
      final out = lower.endsWith('.pdf')
          ? await widget.api.ocrPdf(filePath: path, filename: name)
          : await widget.api.ocrImage(filePath: path, filename: name);
      final m = Map<String, dynamic>.from(out);
      final text =
          (m['data'] is Map ? (m['data'] as Map)['text'] : null) ??
              m['text'] ??
              (m['data'] is Map ? (m['data'] as Map)['ocr_text'] : null) ??
              m['ocr_text'] ??
              '';
      setState(() {
        _ocring = false;
        _ocrText = text.toString().trim().isNotEmpty ? text.toString() : jsonEncode(m);
      });
    } catch (e) {
      setState(() {
        _ocring = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _summarizeAndSaveLocal() async {
    final text = (_ocrText ?? '').trim();
    if (text.isEmpty) {
      setState(() => _error = 'Run OCR first.');
      return;
    }
    setState(() {
      _summarizing = true;
      _aiSummary = null;
      _error = null;
    });
    try {
      final prompt = '''
Summarize this document into an EMR note for a clinician.
Return plain text with sections:
Chief complaint, History, Medications, Allergies, Labs/Imaging, Assessment/Plan.

DOCUMENT OCR:
$text
''';
      if (!mounted) return;
      final allowed = await ConsentedAiAssist.ensureConsent(
        context,
        includesHealthRecords: true,
      );
      if (!allowed) {
        if (!mounted) return;
        setState(() => _summarizing = false);
        showAiConsentDeniedSnackBar(context);
        return;
      }
      if (!mounted) return;
      final res = await ConsentedAiAssist(widget.api).assist(
        query: prompt,
        kind: 'doctor_summary',
      );
      final summary = _primaryAiAssistText(Map<String, dynamic>.from(res));

      final now = DateTime.now();
      final id = 'local-doc-${now.millisecondsSinceEpoch}';
      final record = MedicalRecord(
        id: id,
        date: now,
        time:
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        symptoms: const [],
        status: 'Completed',
        hospitalId: '',
        hospitalName: '',
        notes: summary.isNotEmpty ? summary : text,
        recordType: 'document_ocr_summary',
      );
      await widget.api.saveOffline(db: _db, record: record);

      if (!mounted) return;
      setState(() {
        _summarizing = false;
        _aiSummary = summary.isNotEmpty ? summary : text;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Saved AI summary to local patient record.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summarizing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _sendSummaryToDoctor() async {
    final summary = (_aiSummary ?? '').trim();
    if (summary.isEmpty) {
      setState(() => _error = 'Generate AI summary first.');
      return;
    }
    final pid = _shareProviderId;
    if (pid == null || pid <= 0) {
      setState(() => _error = 'Select doctor to send summary.');
      return;
    }
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      await widget.api.createShare(
        providerId: pid,
        note: 'Document summary from patient',
        includePatientEmail: _shareIncludeEmail,
        aiSummary: summary,
      );
      if (!mounted) return;
      setState(() => _sharing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Summary sent to doctor.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sharing = false;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Direct OCR (new endpoint)',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _ocring ? null : _pickAndOcrDirect,
                icon: _ocring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(Icons.text_snippet_outlined),
                label: Text(_ocring ? 'Running…' : 'Run OCR'),
              ),
            ],
          ),
          if (_ocrText != null && _ocrText!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(_ocrText!),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _summarizing ? null : _summarizeAndSaveLocal,
                    icon: _summarizing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                        _summarizing ? 'Summarizing…' : 'AI summary → Save local'),
                  ),
                ),
              ],
            ),
            if (_aiSummary != null && _aiSummary!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(_aiSummary!),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Send summary to doctor',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: _shareProviderId,
                        decoration: const InputDecoration(labelText: 'Doctor'),
                        items: _providers
                            .where((p) => p['id'] != null)
                            .map((p) => DropdownMenuItem<int>(
                                  value: p['id'] is int ? p['id'] as int : int.tryParse('${p['id']}'),
                                  child: Text((p['full_name'] ?? p['name'] ?? 'Doctor').toString()),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _shareProviderId = v),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: _shareIncludeEmail,
                        onChanged: (v) => setState(() => _shareIncludeEmail = v),
                        title: const Text('Allow doctor to email me the summary'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _sharing ? null : _sendSummaryToDoctor,
                        icon: _sharing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(_sharing ? 'Sending…' : 'Send summary'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
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
  const _RecordsTab({required this.api, required this.apiClient, this.role});

  final MedicalRecordsApi api;
  final EmergencyApiClient apiClient;
  final String? role;

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
        if (!context.mounted) return;
        final allowed = await ConsentedAiAssist.ensureConsent(
          context,
          includesHealthRecords: true,
        );
        if (!allowed) {
          err = 'AI sharing not allowed';
          return;
        }
        if (!context.mounted) return;
        final res = await ConsentedAiAssist(widget.api).assist(
          query: prompt,
          kind: 'doctor_summary',
        );
        aiSummary =
            _primaryAiAssistText(Map<String, dynamic>.from(res));
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
        setState(() {
          _future = n;
        });
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
          final isPatient = _recordsTabIsPatient(widget.role);
          if (list.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                if (isPatient) VisitNotesFromDoctorPanel(api: widget.api),
                if (isPatient) const SizedBox(height: 16),
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
                    if (isPatient) ...[
                      VisitNotesFromDoctorPanel(api: widget.api),
                      const SizedBox(height: 10),
                    ],
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
                    _RecordTile(
                      theme: theme,
                      r: r,
                      api: widget.api,
                      db: _db,
                      onDeleted: _reload,
                    ),
                  ],
                );
              }
              return _RecordTile(
                theme: theme,
                r: r,
                api: widget.api,
                db: _db,
                onDeleted: _reload,
              );
            },
          );
        },
      ),
    );
  }

}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.theme,
    required this.r,
    required this.api,
    required this.db,
    required this.onDeleted,
  });

  final ThemeData theme;
  final MedicalRecord r;
  final MedicalRecordsApi api;
  final OfflineDb db;
  final VoidCallback onDeleted;

  bool get _isDeviceOnly =>
      r.raw['local_only'] == true ||
      r.raw['hipaa_device_only'] == true ||
      !MedicalRecordsApi.isServerNumericId(r.id);

  Future<void> _confirmDelete(BuildContext context) async {
    bool deleteFromServer = false;
    if (MedicalRecordsApi.isServerNumericId(r.id)) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete record?'),
          content: const Text(
            'Remove from this phone. Also delete the server copy if one exists?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('This phone only'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Phone + server'),
            ),
          ],
        ),
      );
      if (choice == null || !context.mounted) return;
      deleteFromServer = choice;
    }
    if (!context.mounted) return;
    try {
      await api.purgeRecord(
        db: db,
        recordId: r.id,
        deleteFromServer: deleteFromServer,
      );
      onDeleted();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record deleted')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

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
            if (_isDeviceOnly)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'This device only',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.teal.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'open') {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => MedicalRecordDetailScreen(
                    api: api,
                    recordId: r.id,
                    preview: r,
                    offlineDb: db,
                    onDeleted: onDeleted,
                  ),
                ),
              );
            } else if (v == 'delete') {
              _confirmDelete(context);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'open', child: Text('Open')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => MedicalRecordDetailScreen(
                api: api,
                recordId: r.id,
                preview: r,
                offlineDb: db,
                onDeleted: onDeleted,
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
  bool _keepOnDeviceOnly = true;
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

      if (!mounted) return;
      final allowed = await ConsentedAiAssist.ensureConsent(
        context,
        includesHealthRecords: true,
      );
      if (!allowed) {
        showAiConsentDeniedSnackBar(context);
        return;
      }
      if (!mounted) return;
      final res = await ConsentedAiAssist(widget.api).assist(
        query: prompt.toString(),
        kind: 'doctor_summary',
      );
      _notes.text = _primaryAiAssistText(Map<String, dynamic>.from(res));
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
        'local_only': _keepOnDeviceOnly,
        'hipaa_device_only': _keepOnDeviceOnly,
      },
    );

    if (_keepOnDeviceOnly) {
      await widget.api.saveOfflineLocalOnly(db: widget.db, record: record);
    } else {
      await widget.api.saveOffline(db: widget.db, record: record, uploadToServer: true);
      try {
        await SyncService(client: widget.apiClient, db: widget.db).syncAll();
      } catch (_) {}
    }
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
          SwitchListTile(
            value: _keepOnDeviceOnly,
            onChanged: (v) => setState(() => _keepOnDeviceOnly = v),
            title: const Text('Keep on this device only'),
            subtitle: const Text(
              'Recommended: chart is not uploaded to the server (HIPAA-friendly). '
              'Turn off only if you need server backup or appointment linking.',
            ),
          ),
          const Divider(),
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

/// Formats `/medical-records/ai-assist/` payload (patient or doctor structured JSON).
String _formatAiAssistResponseBody(Map<String, dynamic> res) {
  final summary = (res['summary'] ?? '').toString().trim();
  final kind = (res['kind'] ?? '').toString();
  final structured = res['structured'];
  if (structured is Map) {
    final m = Map<String, dynamic>.from(structured);
    if (m.containsKey('text') && m.length == 1) {
      final t = (m['text'] ?? '').toString().trim();
      if (t.isNotEmpty) return t;
    }
    String sectionLines(String title, String key) {
      final v = m[key];
      if (v == null) return '';
      final parts = v is List
          ? v.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList()
          : [v.toString().trim()].where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty) return '';
      final b = StringBuffer()..writeln(title);
      for (final p in parts) {
        b.writeln('• $p');
      }
      b.writeln();
      return b.toString();
    }

    final patientBits = [
      sectionLines('Summary', 'summary_bullets'),
      sectionLines('Next steps', 'next_steps'),
      sectionLines('Warnings', 'warnings'),
    ].where((s) => s.isNotEmpty).join();

    if (kind == 'patient_summary' || m.containsKey('summary_bullets')) {
      if (patientBits.isNotEmpty) return patientBits.trim();
    }

    final doctorBits = [
      sectionLines('HPI', 'hpi'),
      sectionLines('Key findings', 'key_findings'),
      sectionLines('Assessment', 'assessment'),
      sectionLines('Plan', 'plan'),
      sectionLines('Red flags', 'red_flags'),
    ].where((s) => s.isNotEmpty).join();

    if (kind == 'doctor_summary' || m.containsKey('hpi') || m.containsKey('key_findings')) {
      if (doctorBits.isNotEmpty) return doctorBits.trim();
    }
  }
  if (summary.isNotEmpty) return summary;
  return '';
}

/// Prefer formatted structured sections; fall back to raw `summary` / legacy keys.
String _primaryAiAssistText(Map<String, dynamic> res) {
  final fromStructured = _formatAiAssistResponseBody(res);
  if (fromStructured.isNotEmpty) return fromStructured;
  final s = (res['summary'] ?? res['answer'] ?? res['response'] ?? '')
      .toString()
      .trim();
  if (s.isNotEmpty) return s;
  return res.toString();
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

  Widget _buildAiResponseCard(ThemeData theme) {
    final body = _formatAiAssistResponseBody(
      Map<String, dynamic>.from(_last!),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          body.isEmpty ? 'No text returned.' : body,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }

  Future<void> _send() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!mounted) return;
      final allowed = await ConsentedAiAssist.ensureConsent(context);
      if (!allowed) {
        showAiConsentDeniedSnackBar(context);
        return;
      }
      if (!mounted) return;
      final res = await ConsentedAiAssist(widget.api).assist(
        query: q,
        kind: 'patient_summary',
      );
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
                    MedicalDisclaimerBanner.playStoreText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.deepPurple.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const AiDisclosureBanner(compact: true),
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
          _buildAiResponseCard(theme),
        ],
      ],
    );
  }
}

bool _recordsTabIsPatient(String? role) {
  final r = (role ?? '').toLowerCase().trim();
  if (r.isEmpty) return true;
  return r == 'patient' ||
      (!r.contains('doctor') &&
          !r.contains('provider') &&
          !r.contains('admin') &&
          !r.contains('staff'));
}

/// Patient view: SOAP notes sent by their doctor(s).
class VisitNotesFromDoctorPanel extends StatefulWidget {
  const VisitNotesFromDoctorPanel({super.key, required this.api, this.appointmentId});

  final MedicalRecordsApi api;
  final int? appointmentId;

  @override
  State<VisitNotesFromDoctorPanel> createState() => _VisitNotesFromDoctorPanelState();
}

class _VisitNotesFromDoctorPanelState extends State<VisitNotesFromDoctorPanel> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() {
    return widget.api.listVisitNotes(appointmentId: widget.appointmentId);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        }
        if (snap.hasError) return const SizedBox.shrink();
        final rows = snap.data ?? const [];
        if (rows.isEmpty) return const SizedBox.shrink();

        return Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.medical_information_outlined, color: Colors.green.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.appointmentId == null
                            ? 'Doctor visit notes (SOAP)'
                            : 'SOAP for this appointment',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final n in rows) VisitNoteTile(note: n),
              ],
            ),
          ),
        );
      },
    );
  }
}

class VisitNoteTile extends StatelessWidget {
  const VisitNoteTile({super.key, required this.note});
  final Map<String, dynamic> note;

  @override
  Widget build(BuildContext context) {
    final prov = note['provider'] is Map
        ? (note['provider'] as Map)['full_name']?.toString()
        : '';
    final title = prov != null && prov.isNotEmpty ? 'Dr. $prov' : 'Doctor note';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(() {
          final raw = (note['created_at'] ?? '').toString();
          return raw.length >= 10 ? raw.substring(0, 10) : 'Visit note';
        }()),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _soapLine('Subjective', note['subjective']),
                _soapLine('Objective', note['objective']),
                _soapLine('Assessment', note['assessment']),
                _soapLine('Plan', note['plan']),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _soapLine(String label, dynamic value) {
    final t = (value ?? '').toString().trim();
    if (t.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(t),
        ],
      ),
    );
  }
}
