import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';

class ProviderApplyScreen extends StatefulWidget {
  const ProviderApplyScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<ProviderApplyScreen> createState() => _ProviderApplyScreenState();
}

class _ProviderApplyScreenState extends State<ProviderApplyScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _license = TextEditingController();
  final _qualifications = TextEditingController();
  final _bio = TextEditingController();
  String _gender = 'male';
  bool _isLoading = false;
  int? _selectedSpecialityId;
  late final Future<List<Map<String, dynamic>>> _specialitiesFuture = _loadSpecialities();

  Future<List<Map<String, dynamic>>> _loadSpecialities() async {
    final data = await EmrFeaturesApi(widget.apiClient).specialities();
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map) {
      final v = data['results'] ?? data['data'] ?? data['specialities'] ?? const [];
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    return const [];
  }

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _license.dispose();
    _qualifications.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedSpecialityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a speciality')),
      );
      return;
    }
    if (_fullName.text.trim().isEmpty || _email.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full name, email, and phone are required')),
      );
      return;
    }
    setState(() => _isLoading = true);
    EmrFeaturesApi(widget.apiClient)
        .providerApply(
          fullName: _fullName.text.trim(),
          email: _email.text.trim(),
          phoneNumber: _phone.text.trim(),
          gender: _gender,
          specialityId: _selectedSpecialityId!,
          licenseNumber: _license.text.trim(),
          qualifications: _qualifications.text.trim(),
          bio: _bio.text.trim(),
        )
        .then((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Application submitted (pending admin approval).'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        })
        .catchError((e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Submit failed: $e')),
          );
        })
        .whenComplete(() {
          if (mounted) setState(() => _isLoading = false);
        });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(Icons.medical_services, color: Colors.white, size: 48),
              const SizedBox(height: 12),
              Text(
                'Become a Provider',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Join our network of healthcare professionals',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Personal Information
        Text('Personal Information', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          controller: _fullName,
          decoration: InputDecoration(
            labelText: 'Full Name',
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _email,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.phone,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _gender,
          decoration: InputDecoration(
            labelText: 'Gender',
            prefixIcon: const Icon(Icons.wc),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: const [
            DropdownMenuItem(value: 'male', child: Text('Male')),
            DropdownMenuItem(value: 'female', child: Text('Female')),
            DropdownMenuItem(value: 'other', child: Text('Other')),
          ],
          onChanged: (v) => setState(() => _gender = v ?? 'male'),
        ),
        const SizedBox(height: 24),

        // Professional Information
        Text('Professional Information', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _specialitiesFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              );
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'No specialities found. Add specialities on backend first.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              );
            }
            final items = rows.map((s) {
              final idRaw = s['id'];
              final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
              if (id == null) return null;
              final name = (s['speciality_name'] ?? s['name'] ?? 'Speciality $id').toString();
              return DropdownMenuItem<int>(
                value: id,
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).whereType<DropdownMenuItem<int>>().toList();

            return DropdownButtonFormField<int>(
              value: _selectedSpecialityId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Speciality',
                prefixIcon: const Icon(Icons.category),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: items,
              onChanged: (v) => setState(() => _selectedSpecialityId = v),
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _license,
          decoration: InputDecoration(
            labelText: 'License Number',
            prefixIcon: const Icon(Icons.badge),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _qualifications,
          decoration: InputDecoration(
            labelText: 'Qualifications',
            prefixIcon: const Icon(Icons.school),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bio,
          decoration: InputDecoration(
            labelText: 'Bio / About',
            prefixIcon: const Icon(Icons.description),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 24),

        // Requirements
        Card(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Color(0xFF4CAF50)),
                    SizedBox(width: 8),
                    Text('Requirements', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                SizedBox(height: 8),
                Text('• Valid medical license', style: TextStyle(fontSize: 13)),
                Text('• Proof of qualifications', style: TextStyle(fontSize: 13)),
                Text('• Government-issued ID', style: TextStyle(fontSize: 13)),
                Text('• Recent professional photo', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Submit Button
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send),
                      SizedBox(width: 8),
                      Text('Submit Application', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
