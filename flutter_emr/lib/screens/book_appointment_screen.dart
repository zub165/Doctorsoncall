import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';
import '../widgets/api_access_placeholder.dart';
import 'patient_billing_screen.dart';

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({
    super.key,
    required this.apiClient,
    this.focusDate,
    this.onBooked,
  });

  final EmergencyApiClient apiClient;
  final ValueNotifier<DateTime>? focusDate;
  final VoidCallback? onBooked;

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  int? _selectedProviderId;
  String? _selectedProviderLabel;
  late Future<List<Map<String, dynamic>>> _providersFuture;
  final _providerSearch = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _providersFuture = _loadProviders();
  }

  Future<List<Map<String, dynamic>>> _loadProviders() async {
    final data = await EmrFeaturesApi(widget.apiClient).providers();
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map) {
      final v = data['results'] ?? data['data'] ?? data['providers'] ?? const [];
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    return const [];
  }

  String _formatYmd(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime d) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '$hour12:$m $period';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFD32F2F),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFD32F2F),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submit() async {
    final pid = _selectedProviderId;
    if (pid == null) {
      setState(() => _msg = 'Please select a provider');
      return;
    }
    if (_selectedDate == null) {
      setState(() => _msg = 'Please pick a date');
      return;
    }
    if (_selectedTime == null) {
      setState(() => _msg = 'Please pick a time');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final dateStr = _formatYmd(_selectedDate!);
      final timeStr = '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';
      final booked = await EmrFeaturesApi(widget.apiClient).bookAppointment(
        providerId: pid,
        date: dateStr,
        time: timeStr,
      );
      setState(() => _msg = 'Appointment scheduled successfully!');
      if (_selectedDate != null) {
        widget.focusDate?.value = _selectedDate!;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booked: ${_selectedProviderLabel ?? 'Provider #$pid'}'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
      await _showBookingBillingDialog(
        context,
        hint: booked.billingHint,
        providerLabel: _selectedProviderLabel ?? 'Provider #$pid',
        dateLabel: _formatDate(_selectedDate!),
        timeLabel: _formatTime(_selectedTime!),
      );
      widget.onBooked?.call();
      setState(() {
        _selectedProviderId = null;
        _selectedProviderLabel = null;
        _selectedDate = null;
        _selectedTime = null;
      });
    } on DioException catch (e) {
      setState(() => _msg = ApiAccessPlaceholder.shortMessage(e));
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _providerSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedProviderName = _selectedProviderLabel ?? (_selectedProviderId == null ? null : 'Provider #${_selectedProviderId!}');
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_available_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Book appointment',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pick provider, date & time to confirm.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Provider Selection
        Text(
          'Schedule appointment',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _providersFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator());
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.error, color: Colors.red),
                    title: const Text('Failed to load providers'),
                    subtitle: Text(snap.error.toString()),
                  ),
                ),
              );
            }
            final providers = snap.data ?? const [];
            if (providers.isEmpty) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.info, color: Colors.orange),
                  title: const Text('No providers available'),
                  subtitle: const Text('Add providers on the backend first'),
                ),
              );
            }
            final q = _providerSearch.text.trim().toLowerCase();
            final filtered = q.isEmpty
                ? providers
                : providers.where((p) {
                    final name = (p['full_name'] ?? p['name'] ?? '').toString().toLowerCase();
                    return name.contains(q);
                  }).toList();
            final items = filtered.map((p) {
              final idRaw = p['id'];
              final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
              if (id == null) return null;
              final name = (p['full_name'] ?? p['name'] ?? 'Provider $id').toString();
              final spec = (p['speciality_id'] ?? '').toString();
              final status = (p['status'] ?? '').toString();
              final label = name + (spec.isNotEmpty ? ' · $spec' : '') + (status.isNotEmpty ? ' · $status' : '');
              return DropdownMenuItem<int>(value: id, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis));
            }).whereType<DropdownMenuItem<int>>().toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _providerSearch,
                  decoration: InputDecoration(
                    hintText: 'Search provider',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: _selectedProviderId,
                  items: items,
                  onChanged: _busy ? null : (v) {
                    setState(() {
                      _selectedProviderId = v;
                      final m = providers.firstWhere((p) => p['id']?.toString() == v?.toString(), orElse: () => const {});
                      _selectedProviderLabel = (m['full_name'] ?? m['name'] ?? '').toString();
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Provider',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            );
          },
        ),
        if (selectedProviderName != null) ...[
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFD32F2F), child: Icon(Icons.person, color: Colors.white)),
              title: Text(
                selectedProviderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Provider ID: $_selectedProviderId'),
            ),
          ),
        ],
        const SizedBox(height: 18),

        // Date Selection
        Text('Date', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        InkWell(
          onTap: _busy ? null : _pickDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _selectedDate != null ? const Color(0xFFD32F2F).withValues(alpha: 0.1) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _selectedDate != null ? const Color(0xFFD32F2F) : Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.calendar_today, color: Color(0xFFD32F2F)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedDate != null ? 'Selected Date' : 'Tap to choose date', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(_selectedDate != null ? _formatDate(_selectedDate!) : 'Select a date', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Time Selection
        Text('Time', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        InkWell(
          onTap: _busy ? null : _pickTime,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _selectedTime != null ? const Color(0xFFD32F2F).withValues(alpha: 0.1) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _selectedTime != null ? const Color(0xFFD32F2F) : Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.access_time, color: Color(0xFFD32F2F)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedTime != null ? 'Selected Time' : 'Tap to choose time', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(_selectedTime != null ? _formatTime(_selectedTime!) : 'Select a time', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
        
        // Quick Time Slots
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildTimeSlot('9:00 AM'),
            _buildTimeSlot('10:00 AM'),
            _buildTimeSlot('11:00 AM'),
            _buildTimeSlot('2:00 PM'),
            _buildTimeSlot('3:00 PM'),
            _buildTimeSlot('4:00 PM'),
          ],
        ),
        
        const SizedBox(height: 18),
        if (selectedProviderName != null && _selectedDate != null && _selectedTime != null) ...[
          Card(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32)),
              title: const Text('Review', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                '$selectedProviderName\n${_formatDate(_selectedDate!)} · ${_formatTime(_selectedTime!)}',
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 12),
        ],
        
        // Submit Button
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _busy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline),
                      SizedBox(width: 8),
                      Text('Confirm booking', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
          ),
        ),
        
        if (_msg != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _msg!.contains('success') ? const Color(0xFF4CAF50).withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(_msg!.contains('success') ? Icons.check_circle : Icons.error, color: _msg!.contains('success') ? const Color(0xFF4CAF50) : Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_msg!)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showBookingBillingDialog(
    BuildContext context, {
    required BillingHint? hint,
    required String providerLabel,
    required String dateLabel,
    required String timeLabel,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF4CAF50)),
            SizedBox(width: 8),
            Text('Appointment booked'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$providerLabel\n$dateLabel · $timeLabel',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (hint != null)
                BillingHintCard(hint: hint)
              else
                const Text(
                  'Your visit is scheduled. Billing details were not returned by the server.',
                ),
            ],
          ),
        ),
        actions: [
          if (hint != null && !hint.coveredVisitAvailable)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PatientBillingScreen(apiClient: widget.apiClient),
                  ),
                );
              },
              child: const Text('My bills'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlot(String time) {
    final isSelected = _selectedTime != null && _formatTime(_selectedTime!) == time;
    return ActionChip(
      label: Text(time),
      backgroundColor: isSelected ? const Color(0xFFD32F2F) : Colors.grey.shade100,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      onPressed: _busy ? null : () {
        final parts = time.replaceAll(' AM', '').replaceAll(' PM', '').split(':');
        int hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        if (time.contains('PM') && hour != 12) hour += 12;
        if (time.contains('AM') && hour == 12) hour = 0;
        setState(() => _selectedTime = TimeOfDay(hour: hour, minute: minute));
      },
    );
  }
}
