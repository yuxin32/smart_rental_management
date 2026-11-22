import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum ConnectedViewState { loading, empty, error }

/// Consistent non-success state for server-backed Owner/Provider screens.
/// The message explains what the user can do; technical exceptions stay in
/// diagnostics rather than being printed into the interface.
class ConnectedStatePanel extends StatelessWidget {
  const ConnectedStatePanel({
    super.key,
    required this.state,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final ConnectedViewState state;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context);
    final icon = switch (state) {
      ConnectedViewState.loading => null,
      ConnectedViewState.empty => Icons.inbox_outlined,
      ConnectedViewState.error => Icons.wifi_off_outlined,
    };
    return Semantics(
      liveRegion: state != ConnectedViewState.empty,
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state == ConnectedViewState.loading)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    else
                      Icon(icon,
                          size: 29,
                          color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(title,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 5),
                    Text(message,
                        style: TextStyle(
                          color: colors.textSecondary,
                          height: 1.4,
                        )),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: onAction,
                        icon: Icon(state == ConnectedViewState.error
                            ? Icons.refresh
                            : Icons.arrow_forward),
                        label: Text(actionLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
