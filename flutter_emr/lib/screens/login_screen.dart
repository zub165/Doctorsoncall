import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/login_portal.dart';
import '../services/auth_api.dart';
import '../services/emergency_api_client.dart';
import '../services/token_repository.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.apiClientOverride});

  /// Optional shared [EmergencyApiClient] (e.g. from session bootstrap).
  final EmergencyApiClient? apiClientOverride;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final EmergencyApiClient _client;
  late final AuthApi _auth;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  LoginPortal _portal = LoginPortal.patient;

  IconData _portalIcon(LoginPortal p) => switch (p) {
        LoginPortal.patient => Icons.person_outline_rounded,
        LoginPortal.doctor => Icons.medical_services_outlined,
        LoginPortal.administrator => Icons.admin_panel_settings_outlined,
      };

  @override
  void initState() {
    super.initState();
    _client =
        widget.apiClientOverride ??
        EmergencyApiClient(tokenRepository: TokenRepository());
    _auth = AuthApi(_client);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    FocusScope.of(context).unfocus();
    try {
      await _auth.login(_email.text.trim(), _password.text, portal: _portal);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => AppShell(apiClient: _client)),
      );
    } on DioException catch (e) {
      final msg = e.response?.data is Map<String, dynamic>
          ? '${(e.response!.data as Map)['message'] ?? e.message}'
          : (e.message ?? 'Request failed');
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
      body: Container(
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 12,
                  shadowColor: Colors.black38,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withValues(alpha: 0.12),
                                  AppColors.primary.withValues(alpha: 0.06),
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.emergency_rounded,
                              size: 48,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Doctor On Call',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choose who is signing in, then enter your credentials',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SegmentedButton<LoginPortal>(
                            segments: LoginPortal.values
                                .map(
                                  (p) => ButtonSegment<LoginPortal>(
                                    value: p,
                                    icon: Icon(_portalIcon(p), size: 20),
                                    label: Text(
                                      p.title,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    tooltip: p.subtitle,
                                  ),
                                )
                                .toList(growable: false),
                            selected: {_portal},
                            onSelectionChanged: (selection) =>
                                setState(() => _portal = selection.first),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _portal.subtitle,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _email,
                            decoration: InputDecoration(
                              labelText: 'Email or username',
                              hintText: 'email@example.com or username',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.text,
                            autocorrect: false,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Please enter email or username';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            obscureText: true,
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Please enter your password';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const ForgotPasswordScreen(),
                                        ),
                                      );
                                    },
                              child: const Text('Forgot password?'),
                            ),
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
                                      'Sign in',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            AppShell(apiClient: _client),
                                      ),
                                    );
                                  },
                            child: const Text('Continue as guest'),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  'OR',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_portal == LoginPortal.administrator)
                            Text(
                              'Administrator accounts are created by your clinic or IT '
                              'team—they cannot be registered in the app.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                            )
                          else
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => RegisterScreen(
                                            apiClient: _client,
                                            initialPortal:
                                                _portal == LoginPortal.doctor
                                                    ? LoginPortal.doctor
                                                    : LoginPortal.patient,
                                          ),
                                        ),
                                      );
                                    },
                              child: const Text(
                                "Don't have an account? Create one",
                                style: TextStyle(fontSize: 15),
                              ),
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
      ),
    );
  }
}
