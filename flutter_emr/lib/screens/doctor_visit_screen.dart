import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/medical_record.dart';
import '../services/emergency_api_client.dart';
import '../services/offline_db.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

/// Doctor Visit screen (Audio/Video placeholders + attachments/import/export placeholders).
///
/// - Shows latest local medical record (offline-first).
/// - Can run best-effort sync before starting the visit.
class DoctorVisitScreen extends StatefulWidget {
  const DoctorVisitScreen({
    super.key,
    required this.apiClient,
    required this.offlineDb,
    this.onNavigateToShellTab,
  });

  final EmergencyApiClient apiClient;
  final OfflineDb offlineDb;

  /// Switch main shell tab (e.g. open **Medical records** after attach).
  final ValueChanged<int>? onNavigateToShellTab;

  @override
  State<DoctorVisitScreen> createState() => _DoctorVisitScreenState();
}

class _DoctorVisitScreenState extends State<DoctorVisitScreen> {
  OfflineDb get _db => widget.offlineDb;
  MedicalRecord? _latest;
  bool _syncing = false;
  final ImagePicker _picker = ImagePicker();

  // Triage (quick vitals)
  final _heightCm = TextEditingController();
  final _weightKg = TextEditingController();
  final _tempC = TextEditingController();
  final _bpSys = TextEditingController();
  final _bpDia = TextEditingController();
  final _pulse = TextEditingController();
  final _resp = TextEditingController();
  final _spo2 = TextEditingController();
  final _glucose = TextEditingController();
  final _triageNotes = TextEditingController();
  String? _skinPhotoPath;

  @override
  void initState() {
    super.initState();
    _loadLatest();
  }

  @override
  void dispose() {
    _heightCm.dispose();
    _weightKg.dispose();
    _tempC.dispose();
    _bpSys.dispose();
    _bpDia.dispose();
    _pulse.dispose();
    _resp.dispose();
    _spo2.dispose();
    _glucose.dispose();
    _triageNotes.dispose();
    super.dispose();
  }

  Future<void> _loadLatest() async {
    final rows = await (_db.select(_db.localMedicalRecords)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(1))
        .get();
    if (rows.isEmpty) {
      setState(() => _latest = null);
      return;
    }
    try {
      final m = jsonDecode(rows.first.json);
      if (m is Map) {
        setState(() => _latest = MedicalRecord.fromJson(Map<String, dynamic>.from(m)));
      } else {
        setState(() => _latest = null);
      }
    } catch (_) {
      setState(() => _latest = null);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await SyncService(client: widget.apiClient, db: _db).syncAll();
      await _loadLatest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Synced')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync failed (offline?)')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Dispose dialog-owned controllers after the route has finished popping (avoids
  /// `InheritedWidget` / `_dependents` assertions during teardown).
  void _disposeAfterRoute(void Function() disposeFn) {
    WidgetsBinding.instance.addPostFrameCallback((_) => disposeFn());
  }

  Rect _shareSheetOrigin() {
    final sz = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(0, 0, sz.width, sz.height);
  }

  Future<void> _shareTriageText() async {
    await SharePlus.instance.share(
      ShareParams(
        text: _triageToText(),
        subject: 'Triage',
        sharePositionOrigin: _shareSheetOrigin(),
      ),
    );
  }

  Future<void> _exportTriagePdfShare() async {
    try {
      final doc = pw.Document();
      final body = _triageToText();
      doc.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Text('Triage', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Paragraph(text: body),
          ],
        ),
      );
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/triage_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(path);
      await file.writeAsBytes(await doc.save());
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: 'Triage export',
          sharePositionOrigin: _shareSheetOrigin(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e')),
      );
    }
  }

  Future<void> _pickUploadFiles() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null || r.files.isEmpty) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Selected ${r.files.length} file(s). Cloud attach for visits is not wired yet.',
        ),
      ),
    );
  }

  Future<void> _importTriageFromFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt'],
      withData: kIsWeb,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    late final String content;
    try {
      if (f.bytes != null) {
        content = utf8.decode(f.bytes!);
      } else if (f.path != null && f.path!.isNotEmpty) {
        content = await File(f.path!).readAsString();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read that file')),
        );
        return;
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that file')),
      );
      return;
    }
    try {
      final m = jsonDecode(content);
      if (m is! Map) throw const FormatException('not a json object');
      _applyTriageMap(Map<String, dynamic>.from(m));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported triage from file')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File must be triage JSON (same as Export JSON)')),
      );
    }
  }

  Future<void> _whatsAppCall({required String kind}) async {
    final phoneC = TextEditingController();
    final messageC = TextEditingController(text: 'Hi, can we do a $kind call now?');
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('WhatsApp $kind'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneC,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (international)',
                hintText: '+14155551234',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: messageC,
              decoration: const InputDecoration(labelText: 'Message'),
              minLines: 2,
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(phoneC.text),
            child: const Text('Open WhatsApp'),
          ),
        ],
      ),
    );
    final msg = messageC.text;
    _disposeAfterRoute(() {
      phoneC.dispose();
      messageC.dispose();
    });

    final clean = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '').trim();
    if (clean.isEmpty) return;

    // WhatsApp deep-link. `whatsapp://` works when app installed; https fallback works otherwise.
    final encoded = Uri.encodeComponent(msg);
    final native = Uri.parse('whatsapp://send?phone=$clean&text=$encoded');
    final web = Uri.parse('https://wa.me/$clean?text=$encoded');

    final opened = await launchUrl(native, mode: LaunchMode.externalApplication);
    if (!opened) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  double? _parseNum(TextEditingController c) {
    final s = c.text.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  double? get _bmi {
    final hCm = _parseNum(_heightCm);
    final wKg = _parseNum(_weightKg);
    if (hCm == null || wKg == null || hCm <= 0) return null;
    final hM = hCm / 100.0;
    return wKg / (hM * hM);
  }

  Map<String, dynamic> _triageToJson() {
    final bmi = _bmi;
    return {
      'type': 'triage-v1',
      'captured_at': DateTime.now().toIso8601String(),
      'height_cm': _parseNum(_heightCm),
      'weight_kg': _parseNum(_weightKg),
      'bmi': bmi == null ? null : double.parse(bmi.toStringAsFixed(2)),
      'temp_c': _parseNum(_tempC),
      'bp_sys': _parseNum(_bpSys),
      'bp_dia': _parseNum(_bpDia),
      'pulse_bpm': _parseNum(_pulse),
      'resp_rate': _parseNum(_resp),
      'spo2_pct': _parseNum(_spo2),
      'glucose_mg_dl': _parseNum(_glucose),
      'notes': _triageNotes.text.trim(),
      'skin_photo_path': _skinPhotoPath,
    };
  }

  String _triageToText() {
    final bmi = _bmi;
    final buf = StringBuffer()
      ..writeln('Triage')
      ..writeln('Height: ${_heightCm.text.trim()} cm')
      ..writeln('Weight: ${_weightKg.text.trim()} kg')
      ..writeln('BMI: ${bmi == null ? '' : bmi.toStringAsFixed(2)}')
      ..writeln('Temp: ${_tempC.text.trim()} C')
      ..writeln('BP: ${_bpSys.text.trim()}/${_bpDia.text.trim()}')
      ..writeln('Pulse: ${_pulse.text.trim()} bpm')
      ..writeln('Resp: ${_resp.text.trim()} /min')
      ..writeln('SpO2: ${_spo2.text.trim()} %')
      ..writeln('Glucose: ${_glucose.text.trim()} mg/dL');
    final n = _triageNotes.text.trim();
    if (n.isNotEmpty) {
      buf..writeln('Notes:')..writeln(n);
    }
    if (_skinPhotoPath != null && _skinPhotoPath!.isNotEmpty) {
      buf.writeln('Skin photo: attached');
    }
    return buf.toString();
  }

  Future<void> _exportTriageJson() async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_triageToJson());
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Triage JSON copied to clipboard')),
    );
  }

  Future<void> _exportTriageText() async {
    await Clipboard.setData(ClipboardData(text: _triageToText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Triage text copied to clipboard')),
    );
  }

  void _applyTriageMap(Map<String, dynamic> map) {
    void setNum(TextEditingController t, dynamic v) {
      if (v == null) return;
      t.text = v.toString();
    }

    setNum(_heightCm, map['height_cm']);
    setNum(_weightKg, map['weight_kg']);
    setNum(_tempC, map['temp_c']);
    setNum(_bpSys, map['bp_sys']);
    setNum(_bpDia, map['bp_dia']);
    setNum(_pulse, map['pulse_bpm']);
    setNum(_resp, map['resp_rate']);
    setNum(_spo2, map['spo2_pct']);
    setNum(_glucose, map['glucose_mg_dl']);
    _triageNotes.text = (map['notes'] ?? '').toString();
    final p = map['skin_photo_path']?.toString();
    setState(() => _skinPhotoPath = (p != null && p.isNotEmpty) ? p : null);
  }

  Future<void> _importTriageJson() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import triage (JSON)'),
        content: TextField(
          controller: c,
          maxLines: 10,
          decoration: const InputDecoration(hintText: 'Paste triage JSON here'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('Import')),
        ],
      ),
    );
    _disposeAfterRoute(c.dispose);
    if (text == null || text.trim().isEmpty) return;
    try {
      final m = jsonDecode(text);
      if (m is! Map) throw const FormatException('not a json object');
      _applyTriageMap(Map<String, dynamic>.from(m));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported triage')),
      );
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid triage JSON')),
      );
    }
  }

  Future<void> _pickSkinPhoto({required bool fromCamera}) async {
    try {
      final x = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 70,
      );
      if (x == null) return;
      setState(() => _skinPhotoPath = x.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not access camera/photos')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _latest;
    final bmi = _bmi;
    // Title lives on [AppShell] AppBar only — avoid nested AppBars (duplicate "Doctor visit").
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              tooltip: 'Sync offline data',
            ),
          ),
        ),
        Expanded(
          child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(Icons.medical_information_outlined, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Latest local medical record',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          r == null
                              ? 'No local record found yet. Create one from Medical records.'
                              : '${r.hospitalName} · ${r.date.toIso8601String()}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _loadLatest,
                    child: const Text('Refresh'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (r != null) ...[
            _kv('Presenting', r.presentingComplaints),
            _kv('PMH', r.pastMedicalHistory),
            _kv('Social', r.socialHistory),
            _kv('Surgical', r.surgicalHistory),
            _kv('Symptoms', r.symptoms.map((s) => s.name).join(', ')),
            _kv('Allergies', r.allergies.join(', ')),
            _kv('Meds', r.medications.map((m) => m['name'] ?? '').where((e) => e.isNotEmpty).join(', ')),
            _kv('Labs', r.labs.map((m) => m['name'] ?? '').where((e) => e.isNotEmpty).join(', ')),
            _kv('Imaging', r.imaging.map((m) => m['name'] ?? '').where((e) => e.isNotEmpty).join(', ')),
            _kv('AI/Notes', r.notes),
            const SizedBox(height: 10),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Visit tools',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _whatsAppCall(kind: 'video'),
                          icon: const Icon(Icons.videocam_outlined),
                          label: const Text('Video'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _whatsAppCall(kind: 'audio'),
                          icon: const Icon(Icons.call_outlined),
                          label: const Text('Audio'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickUploadFiles,
                          icon: const Icon(Icons.attach_file_rounded),
                          label: const Text('Upload'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _importTriageFromFile,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Import'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exportTriagePdfShare,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Export PDF'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _shareTriageText,
                          icon: const Icon(Icons.text_snippet_outlined),
                          label: const Text('Export text'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Triage (Vitals + BMI + Skin photo)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _heightCm,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                          decoration: const InputDecoration(labelText: 'Height (cm)'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _weightKg,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                          decoration: const InputDecoration(labelText: 'Weight (kg)'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tempC,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                          decoration: const InputDecoration(labelText: 'Temperature (°C)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'BMI'),
                          child: Text(
                            bmi == null ? '—' : bmi.toStringAsFixed(2),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _bpSys,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                          decoration: const InputDecoration(labelText: 'BP Sys'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _bpDia,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                          decoration: const InputDecoration(labelText: 'BP Dia'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pulse,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                          decoration: const InputDecoration(labelText: 'Pulse (bpm)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _resp,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                          decoration: const InputDecoration(labelText: 'Resp (/min)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _spo2,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                          decoration: const InputDecoration(labelText: 'SpO2 (%)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _glucose,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                          decoration: const InputDecoration(labelText: 'Glucose (mg/dL)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _triageNotes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Triage notes'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickSkinPhoto(fromCamera: true),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickSkinPhoto(fromCamera: false),
                          icon: const Icon(Icons.photo_outlined),
                          label: const Text('Gallery'),
                        ),
                      ),
                    ],
                  ),
                  if (_skinPhotoPath != null && _skinPhotoPath!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(_skinPhotoPath!),
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _skinPhotoPath = null),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Remove photo'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _exportTriageJson,
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Export JSON'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _exportTriageText,
                          icon: const Icon(Icons.copy_all_rounded),
                          label: const Text('Export text'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _importTriageJson,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Import JSON'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: r == null
                ? null
                : () {
                    widget.onNavigateToShellTab?.call(17);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Medical records — sync when online to update the server copy.',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Attach record to online visit'),
          ),
          const SizedBox(height: 10),
          Text(
            'Video/Audio open WhatsApp. Triage JSON/text/PDF use the triage section below. Cloud visit attach is still pending.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                ),
          ),
        ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(v),
        ],
      ),
    );
  }
}

