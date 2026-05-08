import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/auth_api.dart';
import '../services/emergency_api_client.dart';
import '../services/token_repository.dart';
import '../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  late final AuthApi _auth;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final client = EmergencyApiClient(tokenRepository: TokenRepository());
    _auth = AuthApi(client);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      await _auth.requestPasswordReset(_emailController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('If that email exists, a reset link has been sent.')),
      );
      Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Reset request failed')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Forgot Password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_reset, color: Color(0xFFD32F2F), size: 40),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Reset Your Password',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your email address and we\'ll send you a link to reset your password.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter your email';
                          if (!v.contains('@')) return 'Please enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Send Reset Link', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Remember your password?'),
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
    );
  }
}
