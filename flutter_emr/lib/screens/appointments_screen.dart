import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
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

    // Preferred endpoint based on role.
    try {
      return await ((isAdmin || isDoctor) ? _api.allAppointments() : _api.myAppointments());
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // If role routing is wrong or backend permissions differ, fall back.
      if ((code == 401 || code == 403) && (isAdmin || isDoctor)) {
        return await _api.myAppointments();
      }
      rethrow;
    }
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

          final data = snap.data;
          final raw = data is Map
              ? ((data['appointments'] ??
                      (data['data'] is Map ? (data['data']['appointments'] ?? const []) : const [])) ??
                  const [])
              : const [];
          final List<dynamic> appointments = raw is List ? raw : const [];

          // Calendar + filtered list by selected day.
          final y = _selectedDate.year.toString().padLeft(4, '0');
          final m = _selectedDate.month.toString().padLeft(2, '0');
          final d = _selectedDate.day.toString().padLeft(2, '0');
          final selectedKey = '$y-$m-$d';

          final dayAppointments = appointments.where((a) {
            if (a is Map) {
              final date = a['date']?.toString() ?? '';
              return date.startsWith(selectedKey);
            }
            return false;
          }).toList();

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CalendarDatePicker(
                    initialDate: _selectedDate,
                    firstDate: DateTime(DateTime.now().year - 1),
                    lastDate: DateTime(DateTime.now().year + 2),
                    onDateChanged: (v) => setState(() => _selectedDate = v),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Bookings on $selectedKey',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
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
              else if (dayAppointments.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Center(
                    child: Text(
                      'No appointments on this day.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                    ),
                  ),
                )
              else
                ...dayAppointments.map((a) {
                  if (a is Map) {
                    final role = (widget.role ?? '').toLowerCase().trim();
                    final isAdmin = role == 'admin' ||
                        role == 'administrator' ||
                        role == 'staff';
                    final isDoctor = role == 'doctor' ||
                        role == 'provider' ||
                        role == 'physician';
                    return _buildAppointmentCard(
                      Map<String, dynamic>.from(a),
                      showPatient: isAdmin || isDoctor,
                    );
                  }
                  return const SizedBox.shrink();
                }),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
          ],
        ),
      ),
    );
  }
}
