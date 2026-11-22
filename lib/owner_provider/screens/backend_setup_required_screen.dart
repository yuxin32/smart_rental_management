import 'package:flutter/material.dart';

/// Does not expose configuration values, keys, tokens or raw server errors.
class BackendSetupRequiredScreen extends StatelessWidget {
  const BackendSetupRequiredScreen({
    super.key,
    this.onRetry,
    this.storageUnavailable = false,
  });

  final VoidCallback? onRetry;
  final bool storageUnavailable;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined, size: 44),
                    const SizedBox(height: 20),
                    Text(
                      storageUnavailable
                          ? 'Secure sign-in storage unavailable'
                          : 'Connection not verified',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      storageUnavailable
                          ? 'This app could not safely open its sign-in storage. '
                              'Unlock your device and try again. If the problem continues, contact support. '
                              'Your account has not been deleted, and sign-in has not been opened.'
                          : 'This app could not verify its backend configuration and environment. '
                              'Sign-in and booking actions have not been opened. '
                              'Check your connection or contact the app administrator before trying again.',
                      textAlign: TextAlign.center,
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: Text(storageUnavailable
                            ? 'Try secure storage again'
                            : 'Check connection again',),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
