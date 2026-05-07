import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../services/emr_features_api.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.apiClient});

  final EmergencyApiClient apiClient;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentPw = TextEditingController();
  final _newPw = TextEditingController();
  final _confirmPw = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  String? _msg;
  String? _successMsg;

  Future<void> _submit() async {
    if (_currentPw.text.isEmpty || _newPw.text.isEmpty || _confirmPw.text.isEmpty) {
      setState(() => _msg = 'Please fill in all fields');
      return;
    }
    if (_newPw.text.length < 8) {
      setState(() => _msg = 'Password must be at least 8 characters');
      return;
    }
    if (_newPw.text != _confirmPw.text) {
      setState(() => _msg = 'New passwords do not match');
      return;
    }

    setState(() {
      _busy = true;
      _msg = null;
      _successMsg = null;
    });
    try {
      await EmrFeaturesApi(widget.apiClient).changePassword(_newPw.text);
      setState(() {
        _successMsg = 'Password changed successfully!';
        _currentPw.clear();
        _newPw.clear();
        _confirmPw.clear();
      });
    } on DioException catch (e) {
      setState(() => _msg = e.response?.data?.toString() ?? e.message);
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _currentPw.dispose();
    _newPw.dispose();
    _confirmPw.dispose();
    super.dispose();
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
              const Icon(Icons.lock_reset, color: Colors.white, size: 40),
              const SizedBox(height: 8),
              Text(
                'Change Password',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Update your password to keep your account secure',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Current Password
        Text('Current Password', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _currentPw,
          obscureText: _obscureCurrent,
          decoration: InputDecoration(
            labelText: 'Current Password',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_obscureCurrent ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),

        // New Password
        Text('New Password', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _newPw,
          obscureText: _obscureNew,
          decoration: InputDecoration(
            labelText: 'New Password',
            prefixIcon: const Icon(Icons.lock_open),
            suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            helperText: 'Minimum 8 characters',
          ),
        ),
        const SizedBox(height: 16),

        // Confirm Password
        Text('Confirm Password', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmPw,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: 'Confirm New Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),

        // Requirements Card
        Card(
          color: Colors.orange.withValues(alpha: 0.1),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Password Requirements', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                SizedBox(height: 8),
                Text('• At least 8 characters', style: TextStyle(fontSize: 13)),
                Text('• Contains a number', style: TextStyle(fontSize: 13)),
                Text('• Contains uppercase & lowercase', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Error/Success Messages
        if (_msg != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_msg!, style: const TextStyle(color: Colors.red))),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_successMsg != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_successMsg!, style: const TextStyle(color: Color(0xFF4CAF50)))),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                      Icon(Icons.save),
                      SizedBox(width: 8),
                      Text('Update Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
