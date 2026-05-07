import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/emergency_api_client.dart';
import '../services/medical_records_api.dart';
import '../theme/app_theme.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _input = TextEditingController();
  final List<_Msg> _msgs = [
    _Msg.bot(
      "Hi! I'm your AI medical assistant.\n\n"
      "I can help with basic symptoms and next steps, but I’m not a doctor.\n"
      "If you have severe symptoms (trouble breathing, chest pain, fainting, "
      "severe bleeding, stroke signs), call emergency services immediately.",
    ),
  ];

  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    setState(() {
      _sending = true;
      _msgs.add(_Msg.user(t));
    });
    _input.clear();

    // First, try the backend AI (medical-records/ai-assist). If unavailable,
    // fall back to safe, rule-based guidance.
    String reply;
    try {
      final res = await MedicalRecordsApi(widget.apiClient).aiAssist(query: t);
      reply = (res['answer'] ?? res['response'] ?? res['text'] ?? '').toString().trim();
      if (reply.isEmpty) {
        reply = _fallback(t);
      }
    } catch (_) {
      reply = _fallback(t);
    }

    if (!mounted) return;
    setState(() {
      _msgs.add(_Msg.bot(reply));
      _sending = false;
    });
  }

  String _fallback(String t) {
    final q = t.toLowerCase();

    if (q.contains('chest pain') || q.contains('tightness')) {
      return _urgent(
        'Chest pain can be serious.',
        'If it is severe, with shortness of breath, sweating, nausea, or radiating to arm/jaw, seek emergency care now.',
      );
    }
    if (q.contains('breath') || q.contains('shortness')) {
      return _urgent(
        'Breathing difficulty needs urgent attention.',
        'If you are struggling to breathe, lips are blue, or symptoms are worsening quickly, seek emergency care now.',
      );
    }
    if (q.contains('fever')) {
      return _basic(
        'Fever self-care',
        [
          'Drink fluids and rest.',
          'Consider acetaminophen/paracetamol if safe for you.',
          'If fever lasts > 3 days, is very high, or you have severe symptoms, contact a clinician.',
        ],
      );
    }
    if (q.contains('headache') || q.contains('migraine')) {
      return _basic(
        'Headache tips',
        [
          'Hydrate, rest in a dark room, and avoid screens if sensitive.',
          'Consider a simple pain reliever if safe for you.',
          'Seek urgent care if it’s “worst headache,” sudden onset, with weakness/numbness, confusion, fever + neck stiffness, or head injury.',
        ],
      );
    }
    if (q.contains('nausea') || q.contains('vomit')) {
      return _basic(
        'Nausea/vomiting',
        [
          'Sip small amounts of water or oral rehydration solution.',
          'Try small bland foods when tolerated.',
          'Seek care if you can’t keep fluids down, have severe abdominal pain, blood in vomit/stool, or signs of dehydration.',
        ],
      );
    }
    if (q.contains('bleed') || q.contains('blood')) {
      return _urgent(
        'Bleeding',
        'Apply firm pressure with clean cloth. If bleeding is heavy, doesn’t stop, or you feel faint, seek emergency care now.',
      );
    }

    return _basic(
      'Next steps',
      [
        'Tell me: your age, symptoms, when it started, and any medical conditions/medications.',
        'If symptoms are severe or worsening quickly, seek urgent/emergency care.',
      ],
    );
  }

  String _basic(String title, List<String> bullets) {
    return [
      title,
      '',
      for (final b in bullets) '• $b',
      '',
      'This is general information, not a diagnosis.',
    ].join('\n');
  }

  String _urgent(String title, String body) {
    return [
      title,
      '',
      body,
      '',
      'If you feel unsafe right now, call emergency services.',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppColors.primary.withValues(alpha: 0.08),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.health_and_safety_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Not for emergencies. If severe symptoms, call local emergency services.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade800,
                      ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            itemCount: _msgs.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _QuickChips(
                  onPick: (t) => _send(t),
                );
              }
              final m = _msgs[i - 1];
              return Align(
                alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(
                    color: m.isUser ? AppColors.primary : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    m.text,
                    style: TextStyle(
                      color: m.isUser ? Colors.white : Colors.black87,
                      height: 1.3,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sending ? null : _send,
                    decoration: const InputDecoration(
                      hintText: 'Send a message',
                      prefixIcon: Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: _sending ? null : () => _send(_input.text),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickChips extends StatelessWidget {
  const _QuickChips({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    const chips = [
      'Headache',
      'Chest pain',
      'Fever',
      'Nausea',
      'Breathing issues',
      'Dental pain',
      'Bleeding',
      'Injury',
      'Fatigue',
      'Medication help',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in chips)
            ActionChip(
              label: Text(c),
              onPressed: () => onPick(c),
              backgroundColor: Colors.grey.shade100,
              side: BorderSide(color: Colors.grey.shade200),
            ),
        ],
      ),
    );
  }
}

class _Msg {
  const _Msg({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  factory _Msg.user(String t) => _Msg(text: t, isUser: true);
  factory _Msg.bot(String t) => _Msg(text: t, isUser: false);
}

class DoctorSoapNoteScreen extends StatefulWidget {
  const DoctorSoapNoteScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<DoctorSoapNoteScreen> createState() => _DoctorSoapNoteScreenState();
}

class _DoctorSoapNoteScreenState extends State<DoctorSoapNoteScreen> {
  final _dictation = TextEditingController();
  final _subjective = TextEditingController();
  final _objective = TextEditingController();
  final _assessment = TextEditingController();
  final _plan = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _dictation.dispose();
    _subjective.dispose();
    _objective.dispose();
    _assessment.dispose();
    _plan.dispose();
    super.dispose();
  }

  Future<void> _aiAssist() async {
    final text = _dictation.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final prompt = '''
Convert the following clinician dictation into a SOAP note.
Return STRICT JSON with keys: subjective, objective, assessment, plan.
No markdown, no extra keys.

DICTATION:
$text
''';
      final res = await MedicalRecordsApi(widget.apiClient).aiAssist(query: prompt);
      final raw = (res['answer'] ?? res['response'] ?? res['text'] ?? res).toString();
      final parsed = _parseSoap(raw);
      if (parsed != null) {
        _subjective.text = parsed['subjective'] ?? '';
        _objective.text = parsed['objective'] ?? '';
        _assessment.text = parsed['assessment'] ?? '';
        _plan.text = parsed['plan'] ?? '';
      } else {
        // fallback: simple headings split
        final fallback = _splitByHeadings(text);
        _subjective.text = fallback['subjective'] ?? _subjective.text;
        _objective.text = fallback['objective'] ?? _objective.text;
        _assessment.text = fallback['assessment'] ?? _assessment.text;
        _plan.text = fallback['plan'] ?? _plan.text;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOAP filled')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI assist failed (offline?)')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, String>? _parseSoap(String raw) {
    try {
      final s = raw.trim();
      final start = s.indexOf('{');
      final end = s.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final jsonStr = s.substring(start, end + 1);
      final m = jsonDecode(jsonStr);
      if (m is! Map) return null;
      final map = Map<String, dynamic>.from(m);
      return {
        'subjective': (map['subjective'] ?? '').toString(),
        'objective': (map['objective'] ?? '').toString(),
        'assessment': (map['assessment'] ?? '').toString(),
        'plan': (map['plan'] ?? '').toString(),
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _splitByHeadings(String text) {
    final lower = text.toLowerCase();
    int idx(String k) => lower.indexOf(k);
    final s = idx('subjective');
    final o = idx('objective');
    final a = idx('assessment');
    final p = idx('plan');
    final points = <int, String>{
      if (s >= 0) s: 'subjective',
      if (o >= 0) o: 'objective',
      if (a >= 0) a: 'assessment',
      if (p >= 0) p: 'plan',
    };
    if (points.isEmpty) return {};
    final keys = points.keys.toList()..sort();
    final out = <String, String>{};
    for (var i = 0; i < keys.length; i++) {
      final start = keys[i];
      final end = i + 1 < keys.length ? keys[i + 1] : text.length;
      final section = text.substring(start, end).trim();
      final name = points[start]!;
      out[name] = section.replaceFirst(RegExp('^$name\\s*[:\\-]*', caseSensitive: false), '').trim();
    }
    return out;
  }

  String _composeSoap() {
    return [
      'SOAP Note',
      '',
      'S: ${_subjective.text.trim()}',
      '',
      'O: ${_objective.text.trim()}',
      '',
      'A: ${_assessment.text.trim()}',
      '',
      'P: ${_plan.text.trim()}',
    ].join('\n');
  }

  Future<void> _copySoap() async {
    await Clipboard.setData(ClipboardData(text: _composeSoap()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('SOAP copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Doctor note (SOAP)',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Dictate or paste notes, then use AI Assist to structure into SOAP.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dictation,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Dictation / free text',
            hintText: 'Paste or type the visit notes here…',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _aiAssist,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: const Text('AI Assist SOAP'),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _copySoap,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _soapField('Subjective (S)', _subjective),
        const SizedBox(height: 10),
        _soapField('Objective (O)', _objective),
        const SizedBox(height: 10),
        _soapField('Assessment (A)', _assessment),
        const SizedBox(height: 10),
        _soapField('Plan (P)', _plan),
      ],
    );
  }

  Widget _soapField(String label, TextEditingController c) {
    return TextField(
      controller: c,
      minLines: 3,
      maxLines: 8,
      decoration: InputDecoration(labelText: label),
    );
  }
}

