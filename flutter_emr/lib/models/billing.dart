import 'package:flutter/material.dart';

import '../utils/api_envelope.dart';

/// `billing/status` → `visit_allowance`.
class VisitAllowance {
  const VisitAllowance({
    required this.hasSubscription,
    this.planName,
    this.visitsIncluded,
    this.visitsUsedThisMonth = 0,
    this.visitsRemaining,
    this.coveredVisitAvailable = false,
  });

  final bool hasSubscription;
  final String? planName;
  final int? visitsIncluded;
  final int visitsUsedThisMonth;
  final int? visitsRemaining;
  final bool coveredVisitAvailable;

  bool get isUnlimited => visitsIncluded == null && hasSubscription;

  static VisitAllowance? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    int? included;
    final inc = m['visits_included'];
    if (inc is int) {
      included = inc;
    } else if (inc != null) {
      included = int.tryParse(inc.toString());
    }
    int? remaining;
    final rem = m['visits_remaining'];
    if (rem is int) {
      remaining = rem;
    } else if (rem != null) {
      remaining = int.tryParse(rem.toString());
    }
    return VisitAllowance(
      hasSubscription: m['has_subscription'] == true,
      planName: m['plan_name']?.toString(),
      visitsIncluded: included,
      visitsUsedThisMonth: (m['visits_used_this_month'] as num?)?.toInt() ?? 0,
      visitsRemaining: remaining,
      coveredVisitAvailable: m['covered_visit_available'] == true,
    );
  }

  String get summaryLine {
    if (!hasSubscription) {
      return 'No active plan — extra visits may be billed by your doctor.';
    }
    if (isUnlimited) {
      return '${planName ?? 'Plan'}: unlimited visits this month '
          '($visitsUsedThisMonth used).';
    }
    final rem = visitsRemaining ?? 0;
    final inc = visitsIncluded ?? 0;
    return '${planName ?? 'Plan'}: $rem of $inc visits left this month '
        '($visitsUsedThisMonth used).';
  }
}

/// `POST appointments/` → `billing_hint`.
class BillingHint {
  const BillingHint({
    required this.coveredVisitAvailable,
    required this.extraVisitNote,
    this.visitAllowance,
    this.visitAllowanceAfter,
    this.providerOffersFreeConsultation = false,
    this.suggestedConsultationFee,
  });

  final bool coveredVisitAvailable;
  final String extraVisitNote;
  final VisitAllowance? visitAllowance;
  final VisitAllowance? visitAllowanceAfter;
  final bool providerOffersFreeConsultation;
  final double? suggestedConsultationFee;

  static BillingHint? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    return BillingHint(
      coveredVisitAvailable: m['covered_visit_available'] == true ||
          (VisitAllowance.fromJson(m['visit_allowance'])?.coveredVisitAvailable ??
              false),
      extraVisitNote: (m['extra_visit_note'] ?? '').toString(),
      visitAllowance: VisitAllowance.fromJson(m['visit_allowance']),
      visitAllowanceAfter: VisitAllowance.fromJson(m['visit_allowance_after']),
      providerOffersFreeConsultation:
          m['provider_offers_free_consultation'] == true,
      suggestedConsultationFee: _toDouble(m['suggested_consultation_fee']),
    );
  }
}

class AppointmentBookResult {
  const AppointmentBookResult({
    this.appointmentId,
    this.billingHint,
    this.message,
  });

  final int? appointmentId;
  final BillingHint? billingHint;
  final String? message;

  static AppointmentBookResult fromResponse(dynamic raw) {
    if (raw is! Map) return const AppointmentBookResult();
    final root = Map<String, dynamic>.from(raw);
    Map<String, dynamic> inner = root;
    if (ApiEnvelope.isSuccess(root)) {
      inner = ApiEnvelope.dataMap(root) ?? root;
    } else if (root['data'] is Map) {
      inner = Map<String, dynamic>.from(root['data'] as Map);
    }

    int? id;
    final appt = inner['appointment'];
    if (appt is Map) {
      final aid = appt['id'];
      if (aid is int) {
        id = aid;
      } else {
        id = int.tryParse(aid?.toString() ?? '');
      }
    }

    return AppointmentBookResult(
      appointmentId: id,
      billingHint: BillingHint.fromJson(inner['billing_hint']),
      message: root['message']?.toString(),
    );
  }
}

class BillingStatusSnapshot {
  const BillingStatusSnapshot({
    this.activeSubscription,
    this.visitAllowance,
  });

  final Map<String, dynamic>? activeSubscription;
  final VisitAllowance? visitAllowance;

  static BillingStatusSnapshot fromResponse(dynamic raw) {
    if (raw is! Map) return const BillingStatusSnapshot();
    final root = Map<String, dynamic>.from(raw);
    final inner = ApiEnvelope.dataMap(root) ?? root;
    Map<String, dynamic>? active;
    final a = inner['active'];
    if (a is Map) active = Map<String, dynamic>.from(a);
    return BillingStatusSnapshot(
      activeSubscription: active,
      visitAllowance: VisitAllowance.fromJson(inner['visit_allowance']),
    );
  }
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Shown after booking and on plan tab.
class BillingHintCard extends StatelessWidget {
  const BillingHintCard({
    super.key,
    required this.hint,
    this.visitAllowance,
    this.compact = false,
  });

  final BillingHint? hint;
  final VisitAllowance? visitAllowance;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final allowance = visitAllowance ?? hint?.visitAllowance;
    final covered = hint?.coveredVisitAvailable ??
        allowance?.coveredVisitAvailable ??
        false;
    final note = hint?.extraVisitNote ??
        (covered
            ? 'Included in your plan (App Store / Google Play subscription) — no Stripe charge.'
            : 'Extra visit: pay your doctor\'s invoice in My bills (Stripe card). '
                'Monthly plans are not purchased with Stripe.');

    final bg = covered ? Colors.green.shade50 : Colors.orange.shade50;
    final fg = covered ? Colors.green.shade900 : Colors.orange.shade900;
    final icon = covered ? Icons.verified_outlined : Icons.payments_outlined;

    return Card(
      color: bg,
      margin: EdgeInsets.only(bottom: compact ? 8 : 12),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    note,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            if (allowance != null && allowance.hasSubscription) ...[
              const SizedBox(height: 8),
              Text(
                allowance.summaryLine,
                style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
              ),
            ],
            if (hint?.providerOffersFreeConsultation == true) ...[
              const SizedBox(height: 6),
              Text(
                'This doctor offers free initial consultations.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
            if (hint?.suggestedConsultationFee != null &&
                hint!.suggestedConsultationFee! > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Typical fee: \$${hint!.suggestedConsultationFee!.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class VisitAllowanceCard extends StatelessWidget {
  const VisitAllowanceCard({super.key, required this.allowance});

  final VisitAllowance allowance;

  @override
  Widget build(BuildContext context) {
    if (!allowance.hasSubscription) return const SizedBox.shrink();
    return Card(
      color: Colors.blue.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.event_available, color: Colors.blue.shade800),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Visits this month',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.blue.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    allowance.summaryLine,
                    style: TextStyle(
                      color: Colors.grey.shade900,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
