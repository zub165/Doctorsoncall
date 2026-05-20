import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
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

import '../config/api_config.dart';
import '../models/medical_record.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../services/medical_records_api.dart';
import '../services/offline_db.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

/// Contact for WhatsApp — from an appointment or profile (patient ↔ doctor).
class _VisitContact {
  const _VisitContact({
    required this.displayName,
    required this.phone,
    required this.appointmentLabel,
    required this.roleLabel,
    this.appointmentId,
  });

  final String displayName;
  final String phone;
  final String appointmentLabel;
  final String roleLabel;
  final int? appointmentId;
}

/// Doctor visit: local record preview, triage, WhatsApp or browser meet, file tools,
/// and linking a **server** medical record to an appointment (`PATCH …/appointments/<id>/`).
///
/// - Shows latest local medical record (offline-first).
/// - Can run best-effort sync before starting the visit.
class DoctorVisitScreen extends StatefulWidget {
  const DoctorVisitScreen({
    super.key,
    required this.apiClient,
    required this.offlineDb,
    this.role,
    this.onNavigateToShellTab,
  });

  final EmergencyApiClient apiClient;
  final OfflineDb offlineDb;
  final String? role;

  /// Switch main shell tab (e.g. open **Medical records** after attach).
  final ValueChanged<int>? onNavigateToShellTab;

  @override
  State<DoctorVisitScreen> createState() => _DoctorVisitScreenState();
}

class _DoctorVisitScreenState extends State<DoctorVisitScreen> {
  OfflineDb get _db => widget.offlineDb;
  late final MedicalRecordsApi _recordsApi = MedicalRecordsApi(widget.apiClient);
  MedicalRecord? _latest;
  bool _syncing = false;
  bool _purging = false;
  bool _loadingContacts = false;
  List<_VisitContact> _visitContacts = const [];
  _VisitContact? _selectedContact;
  final ImagePicker _picker = ImagePicker();

  bool get _isDoctorRole {
    final r = (widget.role ?? '').toLowerCase();
    return r == 'doctor' || r == 'provider' || r == 'physician';
  }

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
    _loadVisitContacts();
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

  void _clearTriageForm() {
    for (final c in [
      _heightCm,
      _weightKg,
      _tempC,
      _bpSys,
      _bpDia,
      _pulse,
      _resp,
      _spo2,
      _glucose,
      _triageNotes,
    ]) {
      c.clear();
    }
    setState(() => _skinPhotoPath = null);
  }

  Future<void> _saveVisitToPhone() async {
    final triage = _triageToJson();
    final hasTriage = triage.values.any((v) {
      if (v == null) return false;
      final s = v.toString().trim();
      return s.isNotEmpty && s != 'null';
    });
    if (!hasTriage && _latest == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter vitals or triage notes first')),
      );
      return;
    }
    final id = _latest?.id ?? 'local-${DateTime.now().millisecondsSinceEpoch}';
    final record = MedicalRecord(
      id: id,
      date: DateTime.now(),
      time: TimeOfDay.now().format(context),
      symptoms: _latest?.symptoms ?? const [],
      status: 'Visit',
      hospitalId: _latest?.hospitalId ?? '',
      hospitalName: _latest?.hospitalName.isNotEmpty == true
          ? _latest!.hospitalName
          : 'Visit (this device only)',
      notes: _triageNotes.text.trim(),
      presentingComplaints: _latest?.presentingComplaints ?? '',
      pastMedicalHistory: _latest?.pastMedicalHistory ?? '',
      socialHistory: _latest?.socialHistory ?? '',
      surgicalHistory: _latest?.surgicalHistory ?? '',
      medications: _latest?.medications ?? const [],
      allergies: _latest?.allergies ?? const [],
      labs: _latest?.labs ?? const [],
      imaging: _latest?.imaging ?? const [],
      raw: {
        'source': 'doctor_visit',
        'local_only': true,
        'hipaa_device_only': true,
        'triage': triage,
      },
    );
    await _recordsApi.saveOfflineLocalOnly(db: _db, record: record);
    await _loadLatest();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Visit saved on this device only — not uploaded to the server'),
      ),
    );
  }

  Future<void> _endVisitAndDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End visit & delete?'),
        content: Text(
          _isDoctorRole
              ? 'Removes vitals and any visit chart from this phone. '
                  'Doctors should not keep PHI on the device after the visit.'
              : 'Removes this visit from your phone. Charts saved with '
                  '"Save on this phone" stay off the server unless you uploaded them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    var deleteServerToo = false;
    final serverPk = MedicalRecordsApi.serverRecordPk(_latest);
    final apptPk = MedicalRecordsApi.linkedAppointmentPk(_latest);
    final hasServer = serverPk != null;

    if (hasServer) {
      deleteServerToo = await showDialog<bool>(
            context: context,
            builder: (ctx) {
              var alsoServer = false;
              return StatefulBuilder(
                builder: (ctx2, setModal) {
                  return AlertDialog(
                    title: const Text('Server copy found'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'This visit has a record on the EMR server (upload or link). '
                          'You can remove it from the server as well, or keep device-only deletion.',
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: alsoServer,
                          onChanged: (v) => setModal(() => alsoServer = v ?? false),
                          title: const Text('Also delete server copy'),
                          subtitle: Text(
                            _isDoctorRole
                                ? 'Recommended: leave unchecked (device only).'
                                : 'Only check if the patient wants the server copy removed.',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx2, false),
                        child: Text(_isDoctorRole ? 'Device only' : 'This phone only'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx2, alsoServer),
                        child: Text(alsoServer ? 'Delete phone + server' : 'Done'),
                      ),
                    ],
                  );
                },
              );
            },
          ) ??
          false;
    }

    setState(() => _purging = true);
    try {
      final id = _latest?.id;
      if (id != null && id.isNotEmpty) {
        await _recordsApi.purgeRecord(
          db: _db,
          recordId: id,
          deleteFromServer: deleteServerToo,
          serverRecordId: serverPk,
        );
        if (deleteServerToo && apptPk != null) {
          try {
            await EmrFeaturesApi(widget.apiClient).clearAppointmentMedicalRecord(apptPk);
          } catch (_) {
            // best-effort unlink
          }
        }
      }
      _clearTriageForm();
      setState(() => _latest = null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleteServerToo && hasServer
                ? 'Visit removed from this device and server'
                : 'Visit removed from this device only',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }

  Future<void> _confirmLinkServerChart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload to server?'),
        content: const Text(
          'Linking puts a chart on the EMR server and ties it to an appointment. '
          'Skip this to keep the visit on the patient\'s phone only (recommended unless '
          'the patient explicitly wants a server copy).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue to link'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _showAttachRecordToAppointment();
    }
  }

  Future<void> _persistLinkOnLocalRecord({
    required int appointmentId,
    required int serverRecordId,
  }) async {
    final r = _latest;
    if (r == null) return;
    final raw = Map<String, dynamic>.from(r.raw)
      ..['linked_appointment_id'] = appointmentId
      ..['server_medical_record_id'] = serverRecordId
      ..['local_only'] = false;
    final updated = MedicalRecord(
      id: r.id,
      date: r.date,
      time: r.time,
      symptoms: r.symptoms,
      status: r.status,
      hospitalId: r.hospitalId,
      hospitalName: r.hospitalName,
      notes: r.notes,
      presentingComplaints: r.presentingComplaints,
      pastMedicalHistory: r.pastMedicalHistory,
      socialHistory: r.socialHistory,
      surgicalHistory: r.surgicalHistory,
      medications: r.medications,
      allergies: r.allergies,
      labs: r.labs,
      imaging: r.imaging,
      raw: raw,
    );
    await _recordsApi.saveOfflineLocalOnly(db: _db, record: updated);
    await _loadLatest();
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await SyncService(client: widget.apiClient, db: _db).syncAll();
      await _loadLatest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync checked (visit data stays on device unless you upload)')),
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

  static String? _pickWhatsAppPhone(Map<String, dynamic>? person) {
    if (person == null) return null;
    final wa = (person['whatsapp_number'] ?? '').toString().trim();
    if (wa.isNotEmpty) return wa;
    final ph = (person['phone_number'] ?? '').toString().trim();
    if (ph.isNotEmpty) return ph;
    return null;
  }

  static bool _appointmentIsUpcoming(Map<String, dynamic> ap) {
    final d = ap['date']?.toString() ?? '';
    if (d.length < 10) return true;
    final dt = DateTime.tryParse(d.substring(0, 10));
    if (dt == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !dt.isBefore(today);
  }

  static String _contactAppointmentLabel(Map<String, dynamic> ap) {
    final d = ap['date'] ?? '';
    final t = ap['time'] ?? '';
    return '$d $t'.trim();
  }

  List<_VisitContact> _contactsFromAppointments(List<Map<String, dynamic>> apList) {
    final sorted = List<Map<String, dynamic>>.from(apList)
      ..sort((a, b) {
        final ua = _appointmentIsUpcoming(a);
        final ub = _appointmentIsUpcoming(b);
        if (ua != ub) return ua ? -1 : 1;
        return _contactAppointmentLabel(b).compareTo(_contactAppointmentLabel(a));
      });

    final out = <_VisitContact>[];
    final seenPhones = <String>{};

    for (final ap in sorted) {
      final apId = _appointmentPk(ap);
      final apLabel = _contactAppointmentLabel(ap);
      final patient = ap['patient'] is Map
          ? Map<String, dynamic>.from(ap['patient'] as Map)
          : null;
      final provider = ap['provider'] is Map
          ? Map<String, dynamic>.from(ap['provider'] as Map)
          : null;

      if (_isDoctorRole && patient != null) {
        final phone = _pickWhatsAppPhone(patient);
        if (phone == null || !seenPhones.add(phone)) continue;
        out.add(
          _VisitContact(
            appointmentId: apId,
            displayName: (patient['name'] ?? 'Patient').toString(),
            phone: phone,
            appointmentLabel: apLabel,
            roleLabel: 'Patient',
          ),
        );
      } else if (!_isDoctorRole && provider != null) {
        final phone = _pickWhatsAppPhone(provider);
        if (phone == null || !seenPhones.add(phone)) continue;
        out.add(
          _VisitContact(
            appointmentId: apId,
            displayName: (provider['full_name'] ?? provider['name'] ?? 'Doctor').toString(),
            phone: phone,
            appointmentLabel: apLabel,
            roleLabel: 'Doctor',
          ),
        );
      }
    }
    return out;
  }

  Future<void> _loadVisitContacts() async {
    setState(() => _loadingContacts = true);
    try {
      final data = await _fetchAppointmentsForAttach();
      var contacts = _contactsFromAppointments(_unwrapAppointmentList(data));

      // Patients without appointments: no reliable counterparty from profile alone.

      if (!mounted) return;
      setState(() {
        _visitContacts = contacts;
        _selectedContact = contacts.isNotEmpty ? contacts.first : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _visitContacts = const [];
        _selectedContact = null;
      });
    } finally {
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  String _defaultWhatsAppMessage(String kind) {
    final c = _selectedContact;
    final who = c?.displayName ?? 'there';
    final when = c?.appointmentLabel;
    if (when != null && when.isNotEmpty && when != 'Profile') {
      return 'Hi $who, this is regarding our appointment on $when. Can we do a $kind call?';
    }
    return 'Hi $who, can we do a $kind call now?';
  }

  Future<void> _whatsAppCall({required String kind}) async {
    final prefill = _selectedContact?.phone ?? '';
    final phoneC = TextEditingController(text: prefill);
    final messageC = TextEditingController(text: _defaultWhatsAppMessage(kind));
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('WhatsApp $kind'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedContact != null) ...[
              Text(
                '${_selectedContact!.roleLabel}: ${_selectedContact!.displayName}',
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (_selectedContact!.appointmentLabel.isNotEmpty)
                Text(
                  'Appointment: ${_selectedContact!.appointmentLabel}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
            ],
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

  static List<Map<String, dynamic>> _unwrapAppointmentList(dynamic data) {
    final raw = data is Map
        ? ((data['appointments'] ??
                (data['data'] is Map ? (data['data']['appointments'] ?? const []) : const [])) ??
            const [])
        : const [];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static int? _appointmentPk(Map<String, dynamic> m) {
    final id = m['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '');
  }

  static String _appointmentLabel(Map<String, dynamic> m) {
    final d = m['date'] ?? '';
    final t = m['time'] ?? '';
    final p = m['provider'] is Map ? (m['provider'] as Map)['full_name'] : '';
    return '$d $t ${p ?? ''}'.trim();
  }

  Future<dynamic> _fetchAppointmentsForAttach() async {
    final api = EmrFeaturesApi(widget.apiClient);
    try {
      final mine = await api.myAppointments();
      if (_unwrapAppointmentList(mine).isNotEmpty) return mine;
    } catch (_) {}
    try {
      return await api.allAppointments();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        return await api.myAppointments();
      }
      rethrow;
    }
  }

  Future<void> _openBrowserMeet() async {
    final roomC = TextEditingController(
      text: 'docsoncall-${DateTime.now().millisecondsSinceEpoch}',
    );
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Browser meet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Opens in your browser (Jitsi by default). Share the room name with the other party.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: roomC,
              decoration: const InputDecoration(
                labelText: 'Room name',
                hintText: 'letters-numbers-dashes',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open')),
        ],
      ),
    );
    final room = roomC.text.trim();
    _disposeAfterRoute(roomC.dispose);
    if (go != true || room.isEmpty) return;
    var base = ApiConfig.videoMeetHost.trim();
    if (!base.endsWith('/')) base = '$base/';
    final safe = room.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final uri = Uri.parse('$base$safe');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open browser')),
      );
    }
  }

  Future<void> _showAttachRecordToAppointment() async {
    var loadingOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final apData = await _fetchAppointmentsForAttach();
      final apList = _unwrapAppointmentList(apData);
      final records = await MedicalRecordsApi(widget.apiClient).listRecords();
      if (!mounted) return;
      Navigator.of(context).pop();
      loadingOpen = false;
      if (apList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No appointments found — book one first.')),
        );
        return;
      }
      final serverRecords = records.where((r) => int.tryParse(r.id) != null).toList();
      if (serverRecords.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No server medical records with numeric IDs. Create or sync records under Medical records first.',
            ),
          ),
        );
        return;
      }

      Map<String, dynamic>? firstApRow;
      for (final m in apList) {
        if (_appointmentPk(m) != null) {
          firstApRow = m;
          break;
        }
      }
      if (firstApRow == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointments list had no valid IDs.')),
        );
        return;
      }

      int? selAp = _appointmentPk(firstApRow);
      int? selRec = int.tryParse(serverRecords.first.id);

      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx2, setL) {
            return AlertDialog(
              title: const Text('Link chart to appointment'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selAp,
                      decoration: const InputDecoration(labelText: 'Appointment'),
                      items: [
                        for (final m in apList)
                          if (_appointmentPk(m) != null)
                            DropdownMenuItem(
                              value: _appointmentPk(m),
                              child: Text(
                                _appointmentLabel(m),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: (v) => setL(() => selAp = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: selRec,
                      decoration: const InputDecoration(labelText: 'Server medical record'),
                      items: [
                        for (final r in serverRecords)
                          DropdownMenuItem(
                            value: int.parse(r.id),
                            child: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setL(() => selRec = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(
                  onPressed: selAp != null && selRec != null
                      ? () => Navigator.pop(ctx, true)
                      : null,
                  child: const Text('Save link'),
                ),
              ],
            );
          },
        ),
      );
      if (saved != true || selAp == null || selRec == null) return;
      await EmrFeaturesApi(widget.apiClient).patchAppointmentMedicalRecord(
        appointmentId: selAp!,
        medicalRecordId: selRec!,
      );
      await _persistLinkOnLocalRecord(
        appointmentId: selAp!,
        serverRecordId: selRec!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Linked on server. Use End visit & delete → server option to remove later.',
          ),
        ),
      );
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context).pop();
        loadingOpen = false;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not link: $e')),
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
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.phonelink_lock_outlined, color: Colors.blue.shade800),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Privacy-first visit',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.blue.shade900,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _workflowStep(
                    '1',
                    'During visit',
                    'Enter vitals below, then tap Save on this phone (not uploaded).',
                  ),
                  _workflowStep(
                    '2',
                    'After visit',
                    'Tap End visit & delete → This phone only'
                    '${_isDoctorRole ? ' (recommended for doctors)' : ''}.',
                  ),
                  _workflowStep(
                    '3',
                    'Server copy',
                    'Only if the patient wants it: optional upload under Advanced below.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
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
                  const SizedBox(height: 8),
                  if (_loadingContacts)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  else if (_visitContacts.isEmpty)
                    Text(
                      _isDoctorRole
                          ? 'No patient WhatsApp/phone on upcoming appointments. '
                              'Add whatsapp_number on the patient profile, or enter manually.'
                          : 'No doctor WhatsApp/phone on your appointments. Enter manually.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                    )
                  else ...[
                    DropdownButtonFormField<int>(
                      value: _selectedContact == null
                          ? 0
                          : _visitContacts.indexOf(_selectedContact!).clamp(0, _visitContacts.length - 1),
                      decoration: InputDecoration(
                        labelText: _isDoctorRole ? 'Patient for this visit' : 'Doctor for this visit',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: [
                        for (var i = 0; i < _visitContacts.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              '${_visitContacts[i].displayName} · ${_visitContacts[i].appointmentLabel}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null || v < 0 || v >= _visitContacts.length) return;
                        setState(() => _selectedContact = _visitContacts[v]);
                      },
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _loadVisitContacts,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Refresh contacts'),
                      ),
                    ),
                  ],
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
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openBrowserMeet,
                      icon: const Icon(Icons.video_camera_front_outlined),
                      label: const Text('Meet in browser (Jitsi)'),
                    ),
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
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _purging ? null : _saveVisitToPhone,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save on this phone'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _purging ? null : _endVisitAndDelete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade800,
                            side: BorderSide(color: Colors.red.shade300),
                          ),
                          icon: _purging
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.delete_forever_outlined),
                          label: const Text('End visit & delete'),
                        ),
                      ),
                    ],
                  ),
                  if (_latest != null && MedicalRecordsApi.hasServerCopy(_latest)) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Server copy detected — End visit offers an optional second step to delete it.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.orange.shade800,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Advanced: upload to server (optional)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            subtitle: const Text(
              'Skip unless the patient explicitly wants a server copy',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _confirmLinkServerChart,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Link server chart to appointment'),
              ),
              const SizedBox(height: 8),
              Text(
                'Requires an existing server medical record. Does not upload vitals from this screen.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 8),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              widget.onNavigateToShellTab?.call(17);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Opened Medical records tab.')),
              );
            },
            icon: const Icon(Icons.folder_shared_outlined),
            label: const Text('Open Medical records'),
          ),
          const SizedBox(height: 10),
          Text(
            'WhatsApp opens the phone app; number is pre-filled from the appointment or profile. '
            'Browser meet uses VIDEO_MEET_HOST (default Jitsi). '
            'Link chart is optional — skip it to keep PHI on the patient phone only.',
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

  Widget _workflowStep(String n, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.blue.shade100,
            child: Text(
              n,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall,
                children: [
                  TextSpan(
                    text: '$title — ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      ),
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

