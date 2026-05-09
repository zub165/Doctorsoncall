import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/emergency_api_client.dart';
import '../services/medical_records_api.dart';
import '../services/offline_db.dart';
import '../theme/app_theme.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  static List<_Msg> _welcomeMessages() => [
        _Msg.bot(
          "Hi! I'm your AI medical assistant.\n\n"
          "I can help with basic symptoms and next steps, but I'm not a doctor.\n"
          "If you have severe symptoms (trouble breathing, chest pain, fainting, "
          "severe bleeding, stroke signs), call emergency services immediately.",
        ),
      ];

  final _input = TextEditingController();
  final List<_Msg> _msgs = _welcomeMessages();

  bool _sending = false;
  late final OfflineDb _db = OfflineDb();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateFromDb());
  }

  /// Reload chat from Drift so returning to this tab is instant after first use.
  Future<void> _hydrateFromDb() async {
    try {
      final rows = await _db.aiAssistantMessagesOrdered();
      if (!mounted || rows.isEmpty) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(
            rows.map(
              (r) => r.isUser ? _Msg.user(r.body) : _Msg.bot(r.body),
            ),
          );
      });
    } catch (_) {
      // offline DB unavailable — keep default welcome
    }
  }

  Future<void> _persistBubble({required bool isUser, required String body}) async {
    try {
      await _db.appendAiAssistantMessage(isUser: isUser, body: body);
    } catch (_) {}
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'This removes the conversation from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _db.clearAiAssistantMessages();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _msgs
        ..clear()
        ..addAll(_welcomeMessages());
      _sending = false;
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Immediate safety copy for high‑acuity keywords (no network wait).
  String? _instantTriageReply(String t) {
    final q = t.toLowerCase();

    if (q.contains('chest pain') || q.contains('tightness')) {
      return _urgent(
        'Chest pain can be serious.',
        'If it is severe, with shortness of breath, sweating, nausea, or radiating to arm/jaw, seek emergency care now.',
      );
    }
    if (q.contains('breath') ||
        q.contains('shortness') ||
        q.contains('breathing')) {
      return _urgent(
        'Breathing difficulty needs urgent attention.',
        'If you are struggling to breathe, lips are blue, or symptoms are worsening quickly, seek emergency care now.',
      );
    }
    if (q.contains('bleed') || q.contains('blood')) {
      return _urgent(
        'Bleeding',
        "Apply firm pressure with clean cloth. If bleeding is heavy, doesn't stop, or you feel faint, seek emergency care now.",
      );
    }
    if (q.contains('stroke') ||
        q.contains('facial droop') ||
        q.contains('slurred speech') ||
        q.contains('one-sided weakness')) {
      return _urgent(
        'Possible stroke symptoms',
        'Sudden weakness, face droop, speech trouble, or severe headache needs emergency evaluation now.',
      );
    }
    return null;
  }

  /// Optional second message after instant triage — backend may take several seconds.
  Future<void> _enrichFromBackend(String originalQuery) async {
    try {
      final queryForApi = _expandAssistantQuery(originalQuery);
      final res = await MedicalRecordsApi(widget.apiClient).aiAssist(
        query: queryForApi,
        kind: 'patient_summary',
      );
      final reply = _replyFromAiAssistData(Map<String, dynamic>.from(res));
      if (reply.isEmpty || !mounted) return;
      final block = 'Additional guidance\n\n$reply';
      setState(() {
        _msgs.add(_Msg.bot(block));
      });
      await _persistBubble(isUser: false, body: block);
    } catch (_) {
      // Offline / timeout — instant message already shown
    }
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    setState(() {
      _sending = true;
      _msgs.add(_Msg.user(t));
    });
    _input.clear();
    await _persistBubble(isUser: true, body: t);

    final instant = _instantTriageReply(t);
    if (instant != null) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg.bot(instant));
        _sending = false;
      });
      await _persistBubble(isUser: false, body: instant);
      unawaited(_enrichFromBackend(t));
      return;
    }

    // First, try the backend AI (medical-records/ai-assist). If unavailable,
    // fall back to safe, rule-based guidance.
    final queryForApi = _expandAssistantQuery(t);
    String reply;
    try {
      final res = await MedicalRecordsApi(widget.apiClient).aiAssist(
        query: queryForApi,
        kind: 'patient_summary',
      );
      reply = _replyFromAiAssistData(Map<String, dynamic>.from(res));
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
    await _persistBubble(isUser: false, body: reply);
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
          'Seek urgent care if it\'s "worst headache," sudden onset, with weakness/numbness, confusion, fever + neck stiffness, or head injury.',
        ],
      );
    }
    if (q.contains('nausea') || q.contains('vomit')) {
      return _basic(
        'Nausea/vomiting',
        [
          'Sip small amounts of water or oral rehydration solution.',
          'Try small bland foods when tolerated.',
          "Seek care if you can't keep fluids down, have severe abdominal pain, blood in vomit/stool, or signs of dehydration.",
        ],
      );
    }
    if (q.contains('bleed') || q.contains('blood')) {
      return _urgent(
        'Bleeding',
        "Apply firm pressure with clean cloth. If bleeding is heavy, doesn't stop, or you feel faint, seek emergency care now.",
      );
    }
    if (q.contains('fatigue') || q.contains('tired')) {
      return _basic(
        'Fatigue',
        [
          'Rest, fluids, and consistent sleep often help short-term tiredness.',
          'See a clinician if fatigue lasts more than a couple of weeks, is severe, or comes with fever, weight change, shortness of breath, chest pain, unusual bleeding, or depression.',
        ],
      );
    }
    if (q.contains('dental') || q.contains('tooth')) {
      return _basic(
        'Dental pain',
        [
          'Rinse gently with warm water; avoid very hot/cold on the painful tooth if sensitive.',
          'Dental infections can spread — seek a dentist promptly for persistent or worsening tooth/jaw pain, swelling, fever, or trouble swallowing.',
        ],
      );
    }
    if (q.contains('injury')) {
      return _basic(
        'Injury',
        [
          'Rest, ice, compression, and elevation help many minor sprains/strains.',
          'Seek urgent care for deformity, numbness, inability to bear weight/use the limb, head injury with confusion, or worsening pain/swelling.',
        ],
      );
    }
    if (q.contains('medication')) {
      return _basic(
        'Medication questions',
        [
          'Do not change doses or stop prescriptions without your prescriber’s advice.',
          'For side effects or interactions, contact your pharmacist or clinician with the exact drug names and doses.',
        ],
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
              IconButton(
                tooltip: 'Clear chat',
                onPressed: _sending ? null : _clearChat,
                icon: const Icon(Icons.delete_outline),
                color: AppColors.primary,
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
                  onPick: (tx) => _send(tx),
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
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sending ? null : _send,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Send a message',
                      prefixIcon: Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Send',
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      fixedSize: const Size(48, 48),
                    ),
                    onPressed: _sending ? null : () => _send(_input.text),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
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

  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _listening = false;
  String _lastPartial = '';

  @override
  void dispose() {
    _stt.stop();
    _dictation.dispose();
    _subjective.dispose();
    _objective.dispose();
    _assessment.dispose();
    _plan.dispose();
    super.dispose();
  }

  Future<void> _toggleDictation() async {
    if (_listening) {
      await _stt.stop();
      if (!mounted) return;
      setState(() {
        _listening = false;
        _lastPartial = '';
      });
      return;
    }

    final ok = await _stt.initialize(
      onError: (_) {
        if (!mounted) return;
        setState(() => _listening = false);
      },
      onStatus: (s) {
        // Some platforms report "done"/"notListening" after a pause.
        if (!mounted) return;
        if (s == 'done' || s == 'notListening') {
          setState(() {
            _listening = false;
            _lastPartial = '';
          });
        }
      },
    );
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dictation unavailable on this device.')),
      );
      return;
    }

    setState(() => _listening = true);
    _stt.listen(
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (r) {
        final words = r.recognizedWords.trim();
        if (words.isEmpty) return;

        // Avoid re-appending the same partial over and over.
        if (!r.finalResult) {
          _lastPartial = words;
          return;
        }

        final current = _dictation.text.trimRight();
        final sep = current.isEmpty ? '' : '\n';
        _dictation.text = '$current$sep$words';
        _dictation.selection = TextSelection.collapsed(offset: _dictation.text.length);
        _lastPartial = '';
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _aiAssist() async {
    final text = _dictation.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final res = await MedicalRecordsApi(widget.apiClient).aiAssist(
        query: text,
        kind: 'soap',
      );
      final soapMap = res['soap'];
      if (soapMap is Map) {
        _fillSoapFromMap(Map<String, dynamic>.from(soapMap));
      } else {
        final structured = res['structured'];
        if (structured is Map &&
            (structured.containsKey('subjective') ||
                structured.containsKey('soap_format'))) {
          _fillSoapFromMap(Map<String, dynamic>.from(structured));
        } else {
          final raw = (res['summary'] ?? '').toString();
          final parsed = _parseSoap(raw);
          if (parsed != null) {
            _subjective.text = parsed['subjective'] ?? '';
            _objective.text = parsed['objective'] ?? '';
            _assessment.text = parsed['assessment'] ?? '';
            _plan.text = parsed['plan'] ?? '';
          } else {
            final fallback = _splitByHeadings(raw);
            if (fallback.isNotEmpty) {
              _subjective.text = fallback['subjective'] ?? '';
              _objective.text = fallback['objective'] ?? '';
              _assessment.text = fallback['assessment'] ?? '';
              _plan.text = fallback['plan'] ?? '';
            } else {
              _subjective.text = raw;
            }
          }
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOAP filled')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI assist failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillSoapFromMap(Map<String, dynamic> m) {
    _subjective.text = _coerceSoapSection(m['subjective']);
    _objective.text = _coerceSoapSection(m['objective']);
    _assessment.text = _coerceSoapSection(m['assessment']);
    _plan.text = _coerceSoapSection(m['plan']);
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
      out[name] = section
          .replaceFirst(RegExp('^$name\\s*[:\\-]*', caseSensitive: false), '')
          .trim();
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
        Stack(
          children: [
            TextField(
              controller: _dictation,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Dictation / free text',
                hintText: 'Paste, type, or dictate the visit notes here…',
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: IconButton(
                tooltip: _listening ? 'Stop dictation' : 'Start dictation',
                onPressed: _busy ? null : _toggleDictation,
                icon: Icon(
                  _listening ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: _listening ? Colors.red : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        if (_listening || _lastPartial.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(_listening ? Icons.hearing_rounded : Icons.hearing_disabled_rounded,
                  size: 16, color: _listening ? Colors.red : Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _listening
                      ? (_lastPartial.isEmpty ? 'Listening…' : _lastPartial)
                      : _lastPartial,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ],
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

String _coerceSoapSection(dynamic v) {
  if (v == null) return '';
  if (v is List) {
    return v
        .map((e) => e.toString())
        .where((s) => s.trim().isNotEmpty)
        .join('\n');
  }
  return v.toString().trim();
}

String _formatDoctorStructured(Map<String, dynamic> m) {
  final sb = StringBuffer();
  void section(String title, String key) {
    final v = m[key];
    if (v == null) return;
    final parts = v is List
        ? v.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList()
        : [v.toString().trim()].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return;
    sb.writeln(title);
    for (final p in parts) {
      sb.writeln('• $p');
    }
    sb.writeln();
  }

  section('HPI', 'hpi');
  section('Key findings', 'key_findings');
  section('Assessment', 'assessment');
  section('Plan', 'plan');
  section('Red flags', 'red_flags');
  return sb.toString().trim();
}

String _formatPatientStructured(Map<String, dynamic> m) {
  final sb = StringBuffer();
  void section(String title, String key) {
    final v = m[key];
    if (v == null) return;
    final parts = v is List
        ? v.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList()
        : [v.toString().trim()].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return;
    sb.writeln(title);
    for (final p in parts) {
      sb.writeln('• $p');
    }
    sb.writeln();
  }

  section('Summary', 'summary_bullets');
  section('Next steps', 'next_steps');
  section('Warnings', 'warnings');
  return sb.toString().trim();
}

/// Quick chips send short labels; the backend prompt works better with context.
String _expandAssistantQuery(String raw) {
  const m = <String, String>{
    'Headache':
        'Patient reports headache. Give brief self-care, red flags for urgent care, and one or two clarifying questions (onset, severity, neurological symptoms).',
    'Chest pain':
        'Patient reports chest pain. Explain when to call emergency services; give only general education, no diagnosis.',
    'Fever':
        'Patient reports fever. Give home care basics and when to seek urgent or emergency care.',
    'Nausea':
        'Patient reports nausea. Offer hydration and diet tips and warning signs to seek care.',
    'Breathing issues':
        'Patient reports breathing difficulty. Emphasize emergency signs; brief calm guidance otherwise.',
    'Dental pain':
        'Patient reports dental/tooth pain. Advise dental follow-up and infection warning signs.',
    'Bleeding':
        'Patient reports bleeding. First aid basics and when emergency care is needed.',
    'Injury':
        'Patient reports an injury. Safe general care and red flags for urgent evaluation.',
    'Fatigue':
        'Patient reports fatigue or tiredness. Offer common benign patterns, warning symptoms, and sensible next steps without diagnosing.',
    'Medication help':
        'Patient needs help with medications (side effects, dosing questions). Advise speaking with prescriber/pharmacist; no specific dosing changes.',
  };
  final key = raw.trim();
  return m[key] ?? key;
}

String _replyFromAiAssistData(Map<String, dynamic> res) {
  final summary = (res['summary'] ?? '').toString().trim();
  final kind = (res['kind'] ?? '').toString();
  final structured = res['structured'];
  if (structured is Map) {
    final m = Map<String, dynamic>.from(structured);
    if (m.containsKey('text') && m.length == 1) {
      final t = (m['text'] ?? '').toString().trim();
      return t.isNotEmpty ? t : summary;
    }
    if (kind == 'patient_summary' || m.containsKey('summary_bullets')) {
      final out = _formatPatientStructured(m);
      if (out.isNotEmpty) return out;
    }
    if (kind == 'doctor_summary' ||
        m.containsKey('hpi') ||
        m.containsKey('key_findings')) {
      final out = _formatDoctorStructured(m);
      if (out.isNotEmpty) return out;
    }
  }
  if (summary.isNotEmpty) return summary;
  return '';
}
