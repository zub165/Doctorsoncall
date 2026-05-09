import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../theme/app_theme.dart';

/// Friendly handling for API failures — especially **401** (sign in required).
class ApiAccessPlaceholder extends StatelessWidget {
  const ApiAccessPlaceholder({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.cloud_off_outlined,
    this.onRetry,
    this.showSignInAction = true,
    this.requireSignIn = false,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.secondaryActionIcon,
  });

  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final bool showSignInAction;
  final bool requireSignIn;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final IconData? secondaryActionIcon;

  static bool isUnauthorized(Object? error) =>
      error is DioException &&
      (error.response?.statusCode == 401);

  static bool isForbidden(Object? error) =>
      error is DioException && (error.response?.statusCode == 403);

  static String shortMessage(Object? error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      final data = error.response?.data;
      String? serverMessage;
      if (data is Map) {
        // Common shapes across our backends
        serverMessage = (data['message'] ?? data['error'] ?? data['detail'])?.toString();
      } else if (data is String) {
        serverMessage = data;
      }

      if (code == 401) {
        return 'Sign in to access this section.';
      }
      if (code == 403) {
        return 'You do not have permission for this action.';
      }
      if (code == 404) {
        return 'This resource was not found.';
      }
      return serverMessage ?? error.message ?? 'Request failed';
    }
    return error?.toString() ?? 'Something went wrong';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              requireSignIn ? Icons.lock_outline_rounded : icon,
              size: 56,
              color: requireSignIn ? AppColors.primary : Colors.grey.shade500,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
            if (showSignInAction && requireSignIn) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.login_rounded),
                label: const Text('Sign in'),
              ),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onSecondaryAction,
                icon: Icon(secondaryActionIcon ?? Icons.explore_outlined),
                label: Text(secondaryActionLabel!),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
