import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/login_portal.dart';
import '../services/auth_api.dart';
import '../services/emergency_api_client.dart';
import '../services/offline_db.dart';
import '../services/token_repository.dart';
import '../theme/app_theme.dart';
import '../services/user_api.dart';
import 'app_shell.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.apiClientOverride, this.offlineDb});

  /// Optional shared [EmergencyApiClient] (e.g. from session bootstrap).
  final EmergencyApiClient? apiClientOverride;
  final OfflineDb? offlineDb;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final EmergencyApiClient _client;
  late final AuthApi _auth;
  late final OfflineDb _db;
  late final bool _ownDb;

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
    _db = widget.offlineDb ?? OfflineDb();
    _ownDb = widget.offlineDb == null;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    if (_ownDb) {
      _db.close();
    }
    super.dispose();
  }

  String _messageFromDio(DioException e) {
    final code = e.response?.statusCode;
    final data = e.response?.data;
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final msg = (m['message'] ?? m['detail'] ?? m['non_field_errors'])?.toString().trim();
      if (msg != null && msg.isNotEmpty) return msg;
      final errs = m['errors'];
      if (errs is Map && errs.isNotEmpty) return errs.values.first.toString();
    }
    if (code == 401) return 'Invalid email or password.';
    if (code == 403) {
      return 'This account cannot use this sign-in lane (e.g. doctor not approved yet).';
    }
    return 'Sign-in failed (${code ?? 'network'}).';
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    FocusScope.of(context).unfocus();
    try {
      await _auth.login(_email.text.trim(), _password.text, portal: _portal);
      final me = await UserApi(_client).fetchDoctorOnCallMe();
      final role = (me['role'] ?? '').toString();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AppShell(apiClient: _client, offlineDb: _db, role: role),
        ),
      );
    } on DioException catch (e) {
      final msg = _messageFromDio(e);
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
                            'Choose who is signing in, then enter your credentials.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _LoginPortalPicker(
                            selected: _portal,
                            onChanged: (p) => setState(() => _portal = p),
                            portalIcon: _portalIcon,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _portal.subtitle,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                              fontStyle: FontStyle.italic,
                              height: 1.35,
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
                          SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _loading
                                  ? null
                                  : () {
                                      Navigator.of(context).pushReplacement(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              AppShell(apiClient: _client, offlineDb: _db),
                                        ),
                                      );
                                    },
                              child: const Text(
                                'Continue as guest',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
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
                          const SizedBox(height: 20),
                          if (_portal == LoginPortal.administrator)
                            Text(
                              'Administrator accounts are created by your clinic or IT '
                              'team—they cannot be registered in the app.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade800,
                                fontSize: 13,
                                height: 1.45,
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
                                            offlineDb: _db,
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

/// Role selector: equal-width tiles so labels never break mid-word; uses brand reds.
class _LoginPortalPicker extends StatelessWidget {
  const _LoginPortalPicker({
    required this.selected,
    required this.onChanged,
    required this.portalIcon,
  });

  final LoginPortal selected;
  final ValueChanged<LoginPortal> onChanged;
  final IconData Function(LoginPortal p) portalIcon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (var i = 0; i < LoginPortal.values.length; i++) ...[
              Expanded(
                child: _LoginPortalTile(
                  portal: LoginPortal.values[i],
                  selected: selected == LoginPortal.values[i],
                  icon: portalIcon(LoginPortal.values[i]),
                  onTap: () => onChanged(LoginPortal.values[i]),
                ),
              ),
              if (i < LoginPortal.values.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoginPortalTile extends StatelessWidget {
  const _LoginPortalTile({
    required this.portal,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final LoginPortal portal;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Tooltip(
      message: '${portal.title} — ${portal.subtitle}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: selected
                  ? primary.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? primary : Colors.grey.shade300,
                width: selected ? 1.75 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? primary : Colors.grey.shade700,
                ),
                const SizedBox(height: 8),
                Text(
                  portal.compactTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? primary : Colors.grey.shade800,
                    letterSpacing: -0.2,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(height: 4),
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
