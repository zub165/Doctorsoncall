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

  Set<String> _datesWithBookings(List<Map<String, dynamic>> appointments) {
    return appointments.map((a) => _dateKey(a['date'])).where((k) => k.length == 10).toSet();
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

          final otherDates = _datesWithBookings(appointments)
              .where((k) => k != selectedKey)
              .toList()
            ..sort();

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: AppColors.primary.withValues(alpha: 0.06),
                child: ListTile(
                  leading: const Icon(Icons.event_available_rounded, color: AppColors.primary),
                  title: Text(
                    '${appointments.length} appointment${appointments.length == 1 ? '' : 's'} from database',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    dayAppointments.isEmpty
                        ? 'None on $selectedKey · pick another date below'
                        : '${dayAppointments.length} on selected day',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _loadAppointments,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CalendarDatePicker(
                    initialDate: _selectedDate,
                    firstDate: DateTime(DateTime.now().year - 1),
                    lastDate: DateTime(DateTime.now().year + 3),
                    onDateChanged: (v) => setState(() => _selectedDate = v),
                  ),
                ),
              ),
              if (otherDates.isNotEmpty && dayAppointments.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Dates with bookings',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final dateKey in otherDates.take(8))
                      ActionChip(
                        label: Text(dateKey),
                        onPressed: () {
                          final parts = dateKey.split('-');
                          if (parts.length == 3) {
                            setState(() {
                              _selectedDate = DateTime(
                                int.parse(parts[0]),
                                int.parse(parts[1]),
                                int.parse(parts[2]),
                              );
                            });
                          }
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bookings on $selectedKey',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (_isPatientUser)
                    TextButton.icon(
                      onPressed: () => widget.onNavigateToTab?.call(8),
                      icon: const Icon(Icons.add),
                      label: const Text('Book'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (appointments.isEmpty)
                _buildEmptyState()
              else ...[
                if (dayAppointments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No appointments on this day. Showing all upcoming below.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                    ),
                  ),
                if (dayAppointments.isNotEmpty)
                  ...dayAppointments.map(
                    (a) => _buildAppointmentCard(a, showPatient: showPatient),
                  )
                else ...[
                  const SizedBox(height: 8),
                  Text(
                    'All upcoming',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...appointments.take(25).map(
                        (a) => _buildAppointmentCard(a, showPatient: showPatient),
                      ),
                ],
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
