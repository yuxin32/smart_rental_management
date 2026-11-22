import 'package:flutter/material.dart';

import '../services/backend/backend_config.dart';

/// Connected workspaces use the original full-height UI. Local previews and
/// unknown backends remain visibly distinguished from verified connections.
class BackendEnvironmentFrame extends StatelessWidget {
  const BackendEnvironmentFrame({
    super.key,
    required this.config,
    required this.connected,
    required this.child,
  });

  final BackendConfig? config;
  final bool connected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (connected &&
        (config?.environment == AppEnvironment.production ||
            config?.environment == AppEnvironment.staging)) {
      return child;
    }
    final label = connected
        ? 'UNVERIFIED BACKEND · Do not enter real information'
        : 'OFFLINE WORKSPACE · Changes stay on this device';
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.primaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Semantics(
                container: true,
                child: Row(
                  children: [
                    Icon(
                      Icons.science_outlined,
                      size: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
