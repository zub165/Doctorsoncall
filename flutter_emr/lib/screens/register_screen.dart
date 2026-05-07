import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/login_portal.dart';
import '../services/auth_api.dart';
import '../services/emergency_api_client.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.apiClient,
    this.initialPortal = LoginPortal.patient,
  });

  final EmergencyApiClient apiClient;
  final LoginPortal initialPortal;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late final AuthApi _auth;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  late LoginPortal _registrationPortal;
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    _auth = AuthApi(widget.apiClient);
    _registrationPortal = widget.initialPortal == LoginPortal.administrator
        ? LoginPortal.patient
        : widget.initialPortal;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the Terms & Conditions')),
      );
      return;
    }
    setState(() => _loading = true);
    FocusScope.of(context).unfocus();

    try {
      final name = _name.text.trim();
      await _auth.register(
        username: name.isEmpty ? null : name,
        email: _email.text.trim(),
        password: _password.text,
        registrationPortal: _registrationPortal,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => AppShell(apiClient: widget.apiClient),
        ),
        (route) => false,
      );
    } on DioException catch (e) {
      final dynamic data = e.response?.data;
      String msg = e.message ?? 'Request failed';
      if (data is Map && data['errors'] is Map) {
        msg = '${data['errors']}';
      } else if (data is Map && data['message'] != null) {
        msg = '${data['message']}';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Create Account'),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primaryDark,
              AppColors.primary,
              AppColors.accent,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 12,
                shadowColor: Colors.black38,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.12,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.person_add_rounded,
                                color: AppColors.primary,
                                size: 32,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Join Doctor On Call',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Create your account to get started',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SegmentedButton<LoginPortal>(
                          segments: const [
                            ButtonSegment<LoginPortal>(
                              value: LoginPortal.patient,
                              label: Text('Patient'),
                            ),
                            ButtonSegment<LoginPortal>(
                              value: LoginPortal.doctor,
                              label: Text('Doctor'),
                            ),
                          ],
                          selected: {_registrationPortal},
                          onSelectionChanged: (s) => setState(
                            () => _registrationPortal = s.first,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _registrationPortal == LoginPortal.doctor
                              ? 'Doctor sign-in requires a provider profile linked by your '
                                  'clinic after you register.'
                              : 'Use this if you’re booking visits or viewing your records.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _name,
                          decoration: InputDecoration(
                            labelText: 'Username (optional)',
                            hintText: 'Leave blank to auto-generate; no spaces',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (v) {
                            if (v != null && v.isNotEmpty && v.contains(' ')) {
                              return 'Username cannot contain spaces';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _email,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter your email'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          decoration: InputDecoration(
                            labelText: 'Password (min 8 chars)',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          obscureText: true,
                          validator: (v) {
                            if (v == null || v.length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirm,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          obscureText: true,
                          validator: (v) {
                            if (v != _password.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: _acceptedTerms,
                          onChanged: (v) => setState(
                            () => _acceptedTerms = v ?? false,
                          ),
                          title: const Text(
                            'I agree to the Terms & Conditions',
                            style: TextStyle(fontSize: 13),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Create Account',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Already have an account?'),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Sign In'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
