import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../services/medical_records_api.dart';
import '../theme/app_theme.dart';
import '../widgets/medical_disclaimer_banner.dart';

/// Triage: vitals, BMI, skin photo, import/export (parity with web `OsmTriage`).
///
/// When used inside [AppShell], do **not** wrap in [Scaffold] — the shell already
/// provides the app bar (avoids duplicate "Triage" titles).
class OsmToolsScreen extends StatefulWidget {
  const OsmToolsScreen({
    super.key,
    required this.apiClient,
    this.onNavigateToShellTab,
    this.standalone = false,
    this.role,
  });

  final EmergencyApiClient apiClient;

  /// Set when embedded in main shell (enables Doctor visit / Hospitals shortcuts).
  final ValueChanged<int>? onNavigateToShellTab;

  /// When pushed as a full route (e.g. from guest hospitals), show [Scaffold] + back.
  final bool standalone;

  final String? role;

  @override
  State<OsmToolsScreen> createState() => _OsmToolsScreenState();
}

class _OsmToolsScreenState extends State<OsmToolsScreen> {
  final ImagePicker _picker = ImagePicker();

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

  bool _shareBusy = false;
  int? _shareProviderId;
  int? _shareAppointmentId;
  bool _shareIncludeEmail = false;
  List<Map<String, dynamic>> _shareProviders = const [];
  List<Map<String, dynamic>> _shareAppointments = const [];
  final _shareExtraNote = TextEditingController();

  bool get _embeddedInShell =>
      widget.onNavigateToShellTab != null && !widget.standalone;

  bool get _isPatient {
    final r = (widget.role ?? '').toLowerCase().trim();
    return r.isEmpty ||
        r == 'patient' ||
        (!r.contains('doctor') &&
            !r.contains('provider') &&
            !r.contains('admin') &&
            !r.contains('staff'));
  }

  @override
  void initState() {
    super.initState();
    if (_isPatient) _loadShareTargets();
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
    _shareExtraNote.dispose();
    super.dispose();
  }

  Future<void> _loadShareTargets() async {
    try {
      final raw = await EmrFeaturesApi(widget.apiClient).myAppointments();
      final appts = <Map<String, dynamic>>[];
      final provById = <int, Map<String, dynamic>>{};
      if (raw is Map) {
        final list = raw['appointments'] ??
            (raw['data'] is Map ? (raw['data'] as Map)['appointments'] : null);
        if (list is List) {
          for (final row in list) {
            if (row is! Map) continue;
            final m = Map<String, dynamic>.from(row);
            appts.add(m);
            final pr = m['provider'];
            if (pr is Map) {
              final id = int.tryParse('${pr['id'] ?? m['provider_id'] ?? ''}');
              if (id != null) provById[id] = Map<String, dynamic>.from(pr);
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _shareAppointments = appts;
        _shareProviders = provById.values.toList();
        if (_shareProviderId == null && _shareProviders.isNotEmpty) {
          _shareProviderId = int.tryParse('${_shareProviders.first['id']}');
        }
      });
    } catch (_) {
      // ignore — share UI still shows manual message
    }
  }

  bool _hasAnyTriageValue() {
    return _heightCm.text.trim().isNotEmpty ||
        _weightKg.text.trim().isNotEmpty ||
        _tempC.text.trim().isNotEmpty ||
        _bpSys.text.trim().isNotEmpty ||
        _triageNotes.text.trim().isNotEmpty;
  }

  Future<void> _shareTriageWithDoctor() async {
    final pid = _shareProviderId;
    if (pid == null || pid <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a doctor from your appointments')),
      );
      return;
    }
    if (!_hasAnyTriageValue()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one vital or triage note')),
      );
      return;
    }
    setState(() => _shareBusy = true);
    try {
      final vitals = _triageToJson();
      if (_skinPhotoPath != null && _skinPhotoPath!.isNotEmpty) {
        vitals['skin_photo_attached'] = true;
      }
      await MedicalRecordsApi(widget.apiClient).shareTriageWithDoctor(
        providerId: pid,
        vitals: vitals,
        patientNote: _shareExtraNote.text.trim(),
        appointmentId: _shareAppointmentId,
        includePatientEmail: _shareIncludeEmail,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Triage shared — doctor will see it in their inbox')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _shareBusy = false);
    }
  }

  Widget _buildShareTriageCard(ThemeData theme) {
    if (!_isPatient) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 16),
      color: Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Share triage with doctor',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Saves vitals on the server and notifies your doctor\'s share inbox. '
              'You must have an appointment with them.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            if (_shareProviders.isEmpty)
              Text(
                'Book an appointment first to choose a doctor.',
                style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600),
              )
            else ...[
              DropdownButtonFormField<int>(
                isExpanded: true,
                value: _shareProviderId,
                decoration: const InputDecoration(labelText: 'Doctor'),
                items: _shareProviders
                    .map((p) {
                      final id = int.tryParse('${p['id']}');
                      if (id == null) return null;
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text(
                          (p['full_name'] ?? p['name'] ?? 'Doctor').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    })
                    .whereType<DropdownMenuItem<int>>()
                    .toList(),
                onChanged: _shareBusy
                    ? null
                    : (v) => setState(() {
                          _shareProviderId = v;
                          _shareAppointmentId = null;
                        }),
              ),
              if (_shareAppointments.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  isExpanded: true,
                  value: _shareAppointmentId,
                  decoration: const InputDecoration(
                    labelText: 'Link to appointment (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('No specific visit'),
                    ),
                    ..._shareAppointments
                        .where((a) {
                          final pr = a['provider'];
                          final pid = pr is Map
                              ? int.tryParse('${pr['id'] ?? a['provider_id']}')
                              : int.tryParse('${a['provider_id']}');
                          return pid == _shareProviderId;
                        })
                        .map((a) {
                          final id = int.tryParse('${a['id']}');
                          if (id == null) return null;
                          return DropdownMenuItem<int?>(
                            value: id,
                            child: Text('${a['date']} ${a['time']}'),
                          );
                        })
                        .whereType<DropdownMenuItem<int?>>(),
                  ],
                  onChanged: _shareBusy ? null : (v) => setState(() => _shareAppointmentId = v),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _shareExtraNote,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Message to doctor (optional)',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _shareIncludeEmail,
                onChanged: _shareBusy ? null : (v) => setState(() => _shareIncludeEmail = v),
                title: const Text('Allow doctor to email me about this triage'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _shareBusy ? null : _shareTriageWithDoctor,
                icon: _shareBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_shareBusy ? 'Sharing…' : 'Share triage with doctor'),
              ),
            ],
          ],
        ),
      ),
    );
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
      ..writeln('Temp: ${_tempC.text.trim()} °C')
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

  void _applyTriageMap(Map<String, dynamic> map) {
    void setNum(TextEditingController t, dynamic v) {
      if (v == null) return;
      t.text = v.toString();
    }

    setNum(_heightCm, map['height_cm']);
    setNum(_weightKg, map['weight_kg']);
    setNum(_tempC, map['temp_c'] ?? map['temperature_c']);
    setNum(_bpSys, map['bp_sys']);
    setNum(_bpDia, map['bp_dia']);
    setNum(_pulse, map['pulse_bpm']);
    setNum(_resp, map['resp_rate'] ?? map['resp_min']);
    setNum(_spo2, map['spo2_pct'] ?? map['spo2']);
    setNum(_glucose, map['glucose_mg_dl'] ?? map['glucose_mgdl']);
    _triageNotes.text = (map['notes'] ?? '').toString();
    final p = map['skin_photo_path']?.toString();
    setState(() => _skinPhotoPath = (p != null && p.isNotEmpty) ? p : null);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    if (text == null || text.trim().isEmpty) return;
    try {
      final m = jsonDecode(text);
      if (m is! Map) throw const FormatException('not a json object');
      _applyTriageMap(Map<String, dynamic>.from(m));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported triage')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid triage JSON')),
      );
    }
  }

  Future<void> _importTriageFromFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt'],
      withData: kIsWeb,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    try {
      late final String content;
      if (f.bytes != null) {
        content = utf8.decode(f.bytes!);
      } else if (f.path != null && f.path!.isNotEmpty) {
        content = await File(f.path!).readAsString();
      } else {
        throw const FormatException('unreadable');
      }
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
        const SnackBar(content: Text('File must be triage JSON')),
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

  Widget _vitalsRow(List<Widget> fields) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: fields[i]),
        ],
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final bmi = _bmi;
    final shell = widget.onNavigateToShellTab;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const MedicalDisclaimerBanner(compact: true),
        const SizedBox(height: 12),
        Text(
          'Vitals, BMI, and skin photo for quick assessment. Not a diagnosis—see a healthcare professional.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey.shade700,
            height: 1.35,
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
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                _vitalsRow([
                  TextField(
                    controller: _heightCm,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Height (cm)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: _weightKg,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Weight (kg)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ]),
                const SizedBox(height: 10),
                _vitalsRow([
                  TextField(
                    controller: _tempC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Temperature (°C)'),
                  ),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'BMI'),
                    child: Text(
                      bmi == null ? '—' : bmi.toStringAsFixed(1),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                _vitalsRow([
                  TextField(
                    controller: _bpSys,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'BP Sys'),
                  ),
                  TextField(
                    controller: _bpDia,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'BP Dia'),
                  ),
                ]),
                const SizedBox(height: 10),
                _vitalsRow([
                  TextField(
                    controller: _pulse,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Pulse (bpm)'),
                  ),
                  TextField(
                    controller: _resp,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Resp (/min)'),
                  ),
                ]),
                const SizedBox(height: 10),
                _vitalsRow([
                  TextField(
                    controller: _spo2,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'SpO2 (%)'),
                  ),
                  TextField(
                    controller: _glucose,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Glucose (mg/dL)'),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _triageNotes,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Triage notes',
                    alignLabelWithHint: true,
                  ),
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
                if (_skinPhotoPath != null && _skinPhotoPath!.isNotEmpty && !kIsWeb) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_skinPhotoPath!),
                      height: 180,
                      width: double.infinity,
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
                ] else if (_skinPhotoPath != null && _skinPhotoPath!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Photo selected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                _buildShareTriageCard(theme),
                const SizedBox(height: 14),
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _importTriageJson,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Import JSON'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _importTriageFromFile,
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('Import file'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Next: save triage into a medical record (Medical records tab) or open Doctor visit for video, WhatsApp, and appointment linking.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (shell != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => shell(7),
            icon: const Icon(Icons.video_call_outlined),
            label: const Text('Open Doctor visit'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => shell(1),
            icon: const Icon(Icons.local_hospital_outlined),
            label: const Text('Hospitals & nearby'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => shell(17),
            icon: const Icon(Icons.folder_shared_outlined),
            label: const Text('Medical records & sync'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);

    if (_embeddedInShell) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Triage'),
        automaticallyImplyLeading: widget.standalone || Navigator.of(context).canPop(),
      ),
      body: body,
    );
  }
}
