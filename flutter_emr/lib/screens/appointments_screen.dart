import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../services/medical_records_api.dart';
import 'medical_records_hub_screen.dart' show VisitNoteTile, VisitNotesFromDoctorPanel;
import '../theme/app_theme.dart';
import '../widgets/api_access_placeholder.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({
    super.key,
    required this.apiClient,
    this.onNavigateToTab,
    this.focusDate,
    this.role,
  });

  final EmergencyApiClient apiClient;
  final ValueChanged<int>? onNavigateToTab;
  final ValueNotifier<DateTime>? focusDate;
  final String? role;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late final EmrFeaturesApi _api;
  Future<dynamic>? _appointmentsFuture;
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  VoidCallback? _focusListener;

  /// Only patients use in-app booking; staff use the list for assigned bookings.
  bool get _isPatientUser {
    final role = (widget.role ?? '').toLowerCase().trim();
    final isAdmin =
        role == 'admin' || role == 'administrator' || role == 'staff';
    final isDoctor =
        role == 'doctor' || role == 'provider' || role == 'physician';
    return !isAdmin && !isDoctor;
  }

  @override
  void initState() {
    super.initState();
    _api = EmrFeaturesApi(widget.apiClient);
    if (widget.focusDate != null) {
      _focusListener = () {
        final v = widget.focusDate!.value;
        if (!mounted) return;
        setState(() => _selectedDate = v);
        _loadAppointments();
      };
      widget.focusDate!.addListener(_focusListener!);
      _selectedDate = widget.focusDate!.value;
    }
    _loadAppointments();
  }

  @override
  void dispose() {
    if (widget.focusDate != null && _focusListener != null) {
      widget.focusDate!.removeListener(_focusListener!);
    }
    super.dispose();
  }

  void _loadAppointments() {
    setState(() {
      _appointmentsFuture = _fetchAppointmentsWithFallback();
    });
  }

  Future<dynamic> _fetchAppointmentsWithFallback() async {
    final role = (widget.role ?? '').toLowerCase().trim();
    final isAdmin = role == 'admin' || role == 'administrator' || role == 'staff';
    final isDoctor = role == 'doctor' || role == 'provider' || role == 'physician';

    // Staff/admin: all bookings; doctors/patients: mine (patient + provider rows on server).
    try {
      if (isAdmin) {
        return await _api.allAppointments();
      }
      if (isDoctor) {
        try {
          return await _api.allAppointments();
        } on DioException catch (e) {
          if (e.response?.statusCode == 403) {
            return await _api.myAppointments();
          }
          rethrow;
        }
      }
      return await _api.myAppointments();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if ((isAdmin || isDoctor) &&
          (code == 401 || code == 403 || code == 500 || code == 502 || code == 503)) {
        try {
          return await _api.myAppointments();
        } catch (_) {
          rethrow;
        }
      }
      rethrow;
    }
  }

  static String _dateKey(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }

  static List<Map<String, dynamic>> _normalizeAppointments(dynamic data) {
    final raw = data is Map
        ? ((data['appointments'] ??
                (data['data'] is Map ? (data['data']['appointments'] ?? const []) : const [])) ??
            const [])
        : const [];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
      ..sort((a, b) {
        final da = _dateKey(a['date']);
        final db = _dateKey(b['date']);
        final c = da.compareTo(db);
        if (c != 0) return c;
        return (a['time'] ?? '').toString().compareTo((b['time'] ?? '').toString());
      });
  }

  static bool _isReasonableDateKey(String key) {
    if (key.length != 10) return false;
    final y = int.tryParse(key.substring(0, 4));
    if (y == null || y < 2020 || y > 2032) return false;
    return true;
  }

  Set<String> _datesWithBookings(List<Map<String, dynamic>> appointments) {
    return appointments
        .map((a) => _dateKey(a['date']))
        .where(_isReasonableDateKey)
        .toSet();
  }

  static DateTime? _parseDateKey(String key) {
    if (!_isReasonableDateKey(key)) return null;
    final p = key.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static String _formatFriendlyDate(DateTime d) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _toDateKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  List<String> _upcomingDateKeys(List<Map<String, dynamic>> appointments) {
    final today = _toDateKey(DateTime.now());
    return _datesWithBookings(appointments)
        .where((k) => k.compareTo(today) >= 0)
        .toList()
      ..sort();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => _loadAppointments(),
      child: FutureBuilder<dynamic>(
        future: _appointmentsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          if (snap.hasError) {
            final e = snap.error;
            final u = ApiAccessPlaceholder.isUnauthorized(e);
            final f = ApiAccessPlaceholder.isForbidden(e);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                ApiAccessPlaceholder(
                  title: u
                      ? 'Sign in for appointments'
                      : f
                          ? 'Appointments unavailable'
                      : 'Could not load appointments',
                  message: ApiAccessPlaceholder.shortMessage(e),
                  requireSignIn: u,
                  icon: Icons.event_busy_rounded,
                  onRetry: _loadAppointments,
                ),
              ],
            );
          }

          final appointments = _normalizeAppointments(snap.data);
          final role = (widget.role ?? '').toLowerCase().trim();
          final showPatient = role == 'admin' ||
              role == 'administrator' ||
              role == 'staff' ||
              role == 'doctor' ||
              role == 'provider' ||
              role == 'physician';

          final y = _selectedDate.year.toString().padLeft(4, '0');
          final m = _selectedDate.month.toString().padLeft(2, '0');
          final d = _selectedDate.day.toString().padLeft(2, '0');
          final selectedKey = '$y-$m-$d';

          final dayAppointments =
              appointments.where((a) => _dateKey(a['date']) == selectedKey).toList();

          final bookingDates = _datesWithBookings(appointments);
          final upcomingKeys = _upcomingDateKeys(appointments);
          final nextKeys = upcomingKeys
              .where((k) => k != selectedKey)
              .take(4)
              .toList();

          final upcomingList = appointments.where((a) {
            final k = _dateKey(a['date']);
            return _isReasonableDateKey(k) && k.compareTo(_toDateKey(DateTime.now())) >= 0;
          }).toList();

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryHeader(
                totalCount: appointments.length,
                selectedDate: _selectedDate,
                dayCount: dayAppointments.length,
                onRefresh: _loadAppointments,
                onToday: () {
                  final now = DateTime.now();
                  setState(() {
                    _selectedDate = now;
                    _focusedMonth = DateTime(now.year, now.month);
                  });
                },
                onBook: _isPatientUser ? () => widget.onNavigateToTab?.call(8) : null,
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                  child: _AppointmentMonthCalendar(
                    focusedMonth: _focusedMonth,
                    selectedDate: _selectedDate,
                    bookingDateKeys: bookingDates,
                    onMonthChanged: (m) => setState(() => _focusedMonth = m),
                    onDateSelected: (d) => setState(() => _selectedDate = d),
                  ),
                ),
              ),
              if (nextKeys.isNotEmpty && dayAppointments.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Jump to next booking',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final key in nextKeys)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: const Icon(Icons.event, size: 18, color: AppColors.primary),
                            label: Text(_formatFriendlyDate(_parseDateKey(key)!)),
                            onPressed: () {
                              final d = _parseDateKey(key);
                              if (d == null) return;
                              setState(() {
                                _selectedDate = d;
                                _focusedMonth = DateTime(d.year, d.month);
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dayAppointments.isEmpty
                              ? 'No visits this day'
                              : '${dayAppointments.length} visit${dayAppointments.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          _formatFriendlyDate(_selectedDate),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (_isPatientUser)
                    FilledButton.icon(
                      onPressed: () => widget.onNavigateToTab?.call(8),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Book'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (appointments.isEmpty)
                _buildEmptyState()
              else if (dayAppointments.isNotEmpty)
                ...dayAppointments.map(
                  (a) => _buildAppointmentCard(a, showPatient: showPatient),
                )
              else ...[
                if (upcomingList.isNotEmpty) ...[
                  Text(
                    'Upcoming visits',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...upcomingList.take(8).map(
                        (a) => _buildAppointmentCard(a, showPatient: showPatient),
                      ),
                ] else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Select a highlighted date on the calendar.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    // IMPORTANT: This widget is placed inside another scroll view.
    // It must not be scrollable (no nested ListView).
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).size.height * 0.08,
        bottom: 24,
      ),
      child: Column(
        children: [
          const Icon(Icons.event_note, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No Appointments Yet',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your appointments will appear here',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_isPatientUser)
            ElevatedButton.icon(
              onPressed: () => widget.onNavigateToTab?.call(8),
              icon: const Icon(Icons.add),
              label: const Text('Book Appointment'),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'No bookings yet. Patients book from the menu; staff see assigned visits here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openAppointmentThread(Map<String, dynamic> appt) async {
    final apptId = int.tryParse('${appt['id'] ?? ''}');
    final embedded = appt['visit_notes'];
    final hasEmbedded = embedded is List && embedded.isNotEmpty;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Visit thread',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${appt['date']} · ${appt['time']}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                if (hasEmbedded)
                  ...embedded.whereType<Map>().map(
                        (n) => VisitNoteTile(
                          note: Map<String, dynamic>.from(n),
                        ),
                      )
                else if (apptId != null)
                  VisitNotesFromDoctorPanel(
                    api: MedicalRecordsApi(widget.apiClient),
                    appointmentId: apptId,
                  )
                else
                  Text(
                    'No visit notes for this appointment yet.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAppointmentCard(
    Map<String, dynamic> appt, {
    required bool showPatient,
  }) {
    final date = appt['date'] ?? 'TBD';
    final time = appt['time'] ?? 'TBD';
    final approved = appt['approved'] ?? 'pending';
    final providerName = appt['provider']?['full_name'] ?? 'Unknown Provider';
    final patientName = appt['patient']?['name'] ??
        appt['patient']?['full_name'] ??
        'Unknown Patient';
    final medium = appt['medium'] ?? 'video';

    Color statusColor;
    String statusText;
    switch (approved.toString().toLowerCase()) {
      case 'approved':
      case 'yes':
        statusColor = Colors.green;
        statusText = 'Confirmed';
        break;
      case 'rejected':
      case 'no':
        statusColor = Colors.red;
        statusText = 'Rejected';
        break;
      default:
        statusColor = Colors.orange;
        statusText = 'Pending';
    }

    IconData mediumIcon;
    switch (medium.toString().toLowerCase()) {
      case 'video':
        mediumIcon = Icons.videocam;
        break;
      case 'audio':
        mediumIcon = Icons.phone;
        break;
      case 'chat':
        mediumIcon = Icons.chat;
        break;
      default:
        mediumIcon = Icons.local_hospital;
    }

    final visitNotes = appt['visit_notes'];
    final hasSoap = visitNotes is List && visitNotes.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openAppointmentThread(appt),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                    child: const Icon(Icons.event, color: Color(0xFFD32F2F)),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        showPatient ? patientName : providerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (showPatient) ...[
                        const SizedBox(height: 2),
                        Text(
                          'With $providerName',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(mediumIcon, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            medium.toString().toUpperCase(),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(date, style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 20),
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(time),
                ],
              ),
              if (hasSoap) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.description_outlined, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Doctor SOAP note available — tap to view',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'Tap for visit thread',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.totalCount,
    required this.selectedDate,
    required this.dayCount,
    required this.onRefresh,
    required this.onToday,
    this.onBook,
  });

  final int totalCount;
  final DateTime selectedDate;
  final int dayCount;
  final VoidCallback onRefresh;
  final VoidCallback onToday;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_available_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalCount total · $dayCount on selected day',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  _AppointmentsScreenState._formatFriendlyDate(selectedDate),
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Dots on the calendar = days with visits',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                tooltip: 'Today',
                onPressed: onToday,
                icon: const Icon(Icons.today_outlined),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (onBook != null)
                IconButton(
                  tooltip: 'Book visit',
                  onPressed: onBook,
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppColors.primary,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Month grid with dots on days that have appointments.
class _AppointmentMonthCalendar extends StatelessWidget {
  const _AppointmentMonthCalendar({
    required this.focusedMonth,
    required this.selectedDate,
    required this.bookingDateKeys,
    required this.onMonthChanged,
    required this.onDateSelected,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final Set<String> bookingDateKeys;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDateSelected;

  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final year = focusedMonth.year;
    final month = focusedMonth.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final firstWeekday = DateTime(year, month, 1).weekday % 7;
    final todayKey = _AppointmentsScreenState._toDateKey(DateTime.now());
    final selectedKey = _AppointmentsScreenState._toDateKey(selectedDate);

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                final prev = DateTime(year, month - 1);
                onMonthChanged(prev);
              },
            ),
            Expanded(
              child: Text(
                '${_months[month - 1]} $year',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                final next = DateTime(year, month + 1);
                onMonthChanged(next);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: _weekdays
              .map(
                (w) => Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: firstWeekday + daysInMonth,
          itemBuilder: (context, index) {
            if (index < firstWeekday) return const SizedBox.shrink();
            final day = index - firstWeekday + 1;
            final date = DateTime(year, month, day);
            final key = _AppointmentsScreenState._toDateKey(date);
            final hasBooking = bookingDateKeys.contains(key);
            final isSelected = key == selectedKey;
            final isToday = key == todayKey;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onDateSelected(date),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : isToday
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : null,
                    borderRadius: BorderRadius.circular(10),
                    border: isToday && !isSelected
                        ? Border.all(color: AppColors.primary.withValues(alpha: 0.5))
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasBooking
                              ? (isSelected ? Colors.white : AppColors.primary)
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: AppColors.primary, label: 'Has visit'),
            const SizedBox(width: 16),
            _LegendDot(
              color: AppColors.primary.withValues(alpha: 0.15),
              label: 'Today',
              outlined: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.outlined = false,
  });

  final Color color;
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: outlined ? Colors.transparent : color,
            border: outlined ? Border.all(color: AppColors.primary) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }
}
