import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';

import '../services/emergency_api_client.dart';

/// Triage: vitals + BMI + skin photo + import/export (replaces legacy OSM tools).
class OsmToolsScreen extends StatefulWidget {
  const OsmToolsScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

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
  final _notes = TextEditingController();

  String? _skinPhotoPath;

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
    _notes.dispose();
    super.dispose();
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

  Map<String, dynamic> _toJson() {
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
      'notes': _notes.text.trim(),
      'skin_photo_path': _skinPhotoPath,
    };
  }

  Future<void> _exportJson() async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_toJson());
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Triage JSON copied to clipboard')),
    );
  }

  Future<void> _exportText() async {
    final bmi = _bmi;
    final txt = StringBuffer()
      ..writeln('Triage')
      ..writeln('Height: ${_heightCm.text.trim()} cm')
      ..writeln('Weight: ${_weightKg.text.trim()} kg')
      ..writeln('BMI: ${bmi == null ? '' : bmi.toStringAsFixed(2)}')
      ..writeln('Temp: ${_tempC.text.trim()} C')
      ..writeln('BP: ${_bpSys.text.trim()}/${_bpDia.text.trim()}')
      ..writeln('Pulse: ${_pulse.text.trim()} bpm')
      ..writeln('Resp: ${_resp.text.trim()} /min')
      ..writeln('SpO2: ${_spo2.text.trim()} %')
      ..writeln('Glucose: ${_glucose.text.trim()} mg/dL')
      ..writeln('Notes: ${_notes.text.trim()}');
    await Clipboard.setData(ClipboardData(text: txt.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Triage text copied to clipboard')),
    );
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
    final bmi = _bmi;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Triage',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Vitals, BMI, and skin photo for quick assessment.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _heightCm,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Height (cm)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _weightKg,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'BP Sys'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _bpDia,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Pulse (bpm)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _resp,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'SpO2 (%)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _glucose,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Glucose (mg/dL)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notes'),
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
                onPressed: _exportJson,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Export JSON'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _exportText,
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('Export text'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Next step: save this triage into the patient medical record offline + sync.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
      ],
    );
  }
}
