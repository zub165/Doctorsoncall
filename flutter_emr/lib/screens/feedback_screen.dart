import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';

/// Laravel **`POST /api/feedback`** · Django **`POST /api/feedback/submit/`** — body `{ "feedback": "..." }`.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _status;

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await EmrFeaturesApi(widget.apiClient).submitFeedback(t);
      setState(() => _status = 'Sent.');
      _text.clear();
    } on DioException catch (e) {
      String msg = e.message ?? 'Failed to send.';
      final data = e.response?.data;
      if (data is Map) {
        final m = data['message'] ?? data['detail'];
        if (m is String && m.trim().isNotEmpty) msg = m.trim();
        final errs = data['errors'] ?? data['error'] ?? data['feedback'];
        if (errs is Map && errs.isNotEmpty) {
          msg = errs.values.map((v) => v is List ? v.join(', ') : v.toString()).join(' | ');
        } else if (errs is List && errs.isNotEmpty) {
          msg = errs.join(', ');
        } else if (errs is String && errs.trim().isNotEmpty) {
          msg = errs.trim();
        }
      }
      setState(() => _status = msg);
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                        color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.feedback, color: Color(0xFFD32F2F)),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Send Feedback',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'We value your opinion. Share your thoughts, suggestions, or report any issues.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _text,
                  decoration: InputDecoration(
                    hintText: 'Write your feedback here...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _send,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    label: Text(_busy ? 'Sending...' : 'Submit Feedback'),
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _status == 'Sent.'
                          ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _status == 'Sent.' ? Icons.check_circle : Icons.error,
                          color: _status == 'Sent.' ? const Color(0xFF4CAF50) : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(_status!, style: TextStyle(color: _status == 'Sent.' ? const Color(0xFF4CAF50) : Colors.red)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Quick Feedback', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildQuickButton(Icons.thumb_up, 'Great')),
            const SizedBox(width: 12),
            Expanded(child: _buildQuickButton(Icons.sentiment_satisfied, 'Good')),
            const SizedBox(width: 12),
            Expanded(child: _buildQuickButton(Icons.sentiment_dissatisfied, 'Poor')),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickButton(IconData icon, String label) {
    return Card(
      child: InkWell(
        onTap: () {
          _text.text = label;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label selected')));
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFFD32F2F)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
