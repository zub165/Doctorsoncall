import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../theme/app_theme.dart';

/// Visit-linked feedback: patients rate doctors, doctors rate patients (star ratings).
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, required this.apiClient, this.role});

  final EmergencyApiClient apiClient;
  final String? role;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackTarget {
  _FeedbackTarget({
    required this.subjectType,
    required this.label,
    required this.subtitle,
    this.providerId,
    this.patientId,
    this.appointmentId,
    required this.questions,
  });

  final String subjectType;
  final String label;
  final String subtitle;
  final int? providerId;
  final int? patientId;
  final int? appointmentId;
  final List<_RatingQuestion> questions;

  static _FeedbackTarget? fromMap(Map<String, dynamic> m) {
    final label = (m['label'] ?? '').toString();
    if (label.isEmpty) return null;
    final qs = (m['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => _RatingQuestion.fromMap(Map<String, dynamic>.from(e)))
        .whereType<_RatingQuestion>()
        .toList();
    return _FeedbackTarget(
      subjectType: (m['subject_type'] ?? 'general').toString(),
      label: label,
      subtitle: (m['subtitle'] ?? '').toString(),
      providerId: _asInt(m['provider_id']),
      patientId: _asInt(m['patient_id']),
      appointmentId: _asInt(m['appointment_id']),
      questions: qs,
    );
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}

class _RatingQuestion {
  _RatingQuestion({required this.key, required this.label, required this.required});

  final String key;
  final String label;
  final bool required;

  static _RatingQuestion? fromMap(Map<String, dynamic> m) {
    final key = (m['key'] ?? '').toString();
    if (key.isEmpty) return null;
    return _RatingQuestion(
      key: key,
      label: (m['label'] ?? key).toString(),
      required: m['required'] == true,
    );
  }
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _text = TextEditingController();
  final _ratings = <String, int>{};

  bool _busy = false;
  bool _loadingContext = true;
  String? _status;
  String? _loadError;

  String _reviewerRole = 'guest';
  String _subjectHint = '';
  bool _allowGeneral = true;
  List<_FeedbackTarget> _targets = const [];
  _FeedbackTarget? _selected;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  Future<void> _loadContext() async {
    setState(() {
      _loadingContext = true;
      _loadError = null;
    });
    try {
      final ctx = await EmrFeaturesApi(widget.apiClient).fetchFeedbackContext();
      final targets = (ctx['targets'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _FeedbackTarget.fromMap(Map<String, dynamic>.from(e)))
          .whereType<_FeedbackTarget>()
          .toList();
      if (!mounted) return;
      setState(() {
        _reviewerRole = (ctx['reviewer_role'] ?? 'guest').toString();
        _subjectHint = (ctx['subject_hint'] ?? '').toString();
        _allowGeneral = ctx['allow_general'] == true || targets.isEmpty;
        _targets = targets;
        _selected = targets.isNotEmpty ? targets.first : null;
        _ratings.clear();
        _loadingContext = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingContext = false;
        _loadError = e.response?.statusCode == 401
            ? 'Sign in to rate your doctor or patient after a visit.'
            : (e.message ?? 'Could not load feedback options.');
        _allowGeneral = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingContext = false;
        _loadError = e.toString();
        _allowGeneral = true;
      });
    }
  }

  List<_RatingQuestion> get _activeQuestions =>
      _selected?.questions ??
      (ctxFallbackQuestions(_reviewerRole));

  static List<_RatingQuestion> ctxFallbackQuestions(String role) {
    if (role == 'provider') {
      return [
        _RatingQuestion(key: 'overall_rating', label: 'Overall visit experience', required: true),
        _RatingQuestion(
          key: 'rating_communication',
          label: 'Patient communication during the visit',
          required: true,
        ),
        _RatingQuestion(
          key: 'rating_care_quality',
          label: 'Patient cooperation with the care plan',
          required: true,
        ),
      ];
    }
    return [
      _RatingQuestion(key: 'overall_rating', label: 'Overall quality of care', required: true),
      _RatingQuestion(
        key: 'rating_communication',
        label: 'Doctor listened and explained clearly',
        required: true,
      ),
      _RatingQuestion(
        key: 'rating_care_quality',
        label: 'Medical advice and treatment plan',
        required: true,
      ),
      _RatingQuestion(
        key: 'rating_recommend',
        label: 'Would you recommend this doctor?',
        required: true,
      ),
    ];
  }

  String get _aboutLabel {
    if (_selected == null) return 'General app feedback';
    return _selected!.subjectType == 'patient'
        ? 'Feedback about patient'
        : 'Feedback about doctor';
  }

  Future<void> _send({bool generalOnly = false}) async {
    final t = _text.text.trim();
    final visitMode = !generalOnly && _selected != null;

    if (visitMode) {
      for (final q in _activeQuestions.where((q) => q.required)) {
        if ((_ratings[q.key] ?? 0) < 1) {
          setState(() => _status = 'Please rate: ${q.label}');
          return;
        }
      }
    } else if (t.isEmpty) {
      setState(() => _status = 'Please write your feedback.');
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final api = EmrFeaturesApi(widget.apiClient);
      if (visitMode) {
        await api.submitVisitFeedback(
          feedback: t.isEmpty ? _defaultCommentFromStars() : t,
          subjectType: _selected!.subjectType,
          providerId: _selected!.providerId,
          patientId: _selected!.patientId,
          appointmentId: _selected!.appointmentId,
          overallRating: _ratings['overall_rating'],
          ratingCommunication: _ratings['rating_communication'],
          ratingCareQuality: _ratings['rating_care_quality'],
          ratingEase: _ratings['rating_ease'],
          ratingRecommend: _ratings['rating_recommend'],
        );
      } else {
        await api.submitVisitFeedback(feedback: t);
      }
      setState(() {
        _status = 'Thank you — feedback saved.';
        _ratings.clear();
      });
      _text.clear();
    } on DioException catch (e) {
      setState(() => _status = _formatError(e));
    } finally {
      setState(() => _busy = false);
    }
  }

  String _defaultCommentFromStars() {
    final overall = _ratings['overall_rating'] ?? 0;
    if (overall >= 4) return 'Positive visit — $overall/5 stars';
    if (overall >= 3) return 'Satisfactory visit — $overall/5 stars';
    if (overall > 0) return 'Visit needs improvement — $overall/5 stars';
    return 'Visit feedback';
  }

  String _formatError(DioException e) {
    String msg = e.message ?? 'Failed to send.';
    final data = e.response?.data;
    if (data is Map) {
      final m = data['message'] ?? data['detail'];
      if (m is String && m.trim().isNotEmpty) msg = m.trim();
      final errs = data['errors'] ?? data['error'];
      if (errs is Map && errs.isNotEmpty) {
        msg = errs.values
            .map((v) => v is List ? v.join(', ') : v.toString())
            .join(' | ');
      }
    }
    return msg;
  }

  void _applyQuickStars(int stars) {
    setState(() {
      for (final q in _activeQuestions) {
        _ratings[q.key] = stars;
      }
      if (_text.text.trim().isEmpty) {
        _text.text = stars >= 4 ? 'Great experience' : stars >= 3 ? 'Good experience' : 'Needs improvement';
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadingContext) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return RefreshIndicator(
      onRefresh: _loadContext,
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_loadError != null)
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_loadError!, style: theme.textTheme.bodySmall),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.feedback, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Visit feedback',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _subjectHint.isNotEmpty
                        ? _subjectHint
                        : 'Rate your visit with star questions used in telehealth surveys.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                  ),
                  if (_targets.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      _aboutLabel,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<_FeedbackTarget>(
                      value: _selected,
                      isExpanded: true,
                      // Closed field: one line only (see selectedItemBuilder). Menu rows: two lines.
                      itemHeight: 72,
                      selectedItemBuilder: (context) => [
                        for (final t in _targets)
                          SizedBox(
                            height: 24,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                t.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                      ],
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        isDense: true,
                      ),
                      items: [
                        for (final t in _targets)
                          DropdownMenuItem(
                            value: t,
                            child: SizedBox(
                              height: 56,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    t.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  if (t.subtitle.isNotEmpty)
                                    Text(
                                      t.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _selected = v;
                        _ratings.clear();
                      }),
                    ),
                    if (_selected != null && _selected!.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _selected!.subtitle,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Star ratings (1–5)',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ..._activeQuestions.map(
                    (q) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _StarRatingRow(
                        label: q.label,
                        required: q.required,
                        value: _ratings[q.key] ?? 0,
                        onChanged: (v) => setState(() => _ratings[q.key] = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _text,
                    decoration: InputDecoration(
                      hintText: 'Comments (optional if you rated above)…',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _busy || _selected == null ? null : () => _send(),
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send),
                      label: Text(_busy ? 'Sending…' : 'Submit visit feedback'),
                    ),
                  ),
                  if (_allowGeneral) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _send(generalOnly: true),
                        child: const Text('Send general app feedback instead'),
                      ),
                    ),
                  ],
                  if (_status != null) ...[
                    const SizedBox(height: 16),
                    _StatusBanner(message: _status!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Quick overall rating',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Sets all star questions at once (based on telehealth satisfaction surveys).',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final entry in [
                (5, Icons.star_rounded, 'Excellent'),
                (4, Icons.star_half_rounded, 'Good'),
                (3, Icons.star_outline_rounded, 'Fair'),
                (2, Icons.sentiment_dissatisfied, 'Poor'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Card(
                      child: InkWell(
                        onTap: _selected == null
                            ? null
                            : () => _applyQuickStars(entry.$1),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            children: [
                              Icon(entry.$2, color: AppColors.primary),
                              const SizedBox(height: 4),
                              Text('${entry.$1}★', style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(entry.$3, style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StarRatingRow extends StatelessWidget {
  const _StarRatingRow({
    required this.label,
    required this.required,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool required;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          required ? '$label *' : label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(5, (i) {
            final star = i + 1;
            final filled = star <= value;
            return IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => onChanged(star),
              icon: Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                color: filled ? Colors.amber.shade700 : Colors.grey.shade400,
                size: 32,
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ok = message.toLowerCase().contains('thank');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok
            ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.error, color: ok ? const Color(0xFF4CAF50) : Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: ok ? const Color(0xFF4CAF50) : Colors.red))),
        ],
      ),
    );
  }
}
