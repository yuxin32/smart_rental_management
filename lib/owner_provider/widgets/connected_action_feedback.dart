import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum ConnectedActionState { working, success, error }

class ConnectedActionNotice {
  const ConnectedActionNotice(this.state, this.title, this.message);

  final ConnectedActionState state;
  final String title;
  final String message;
}

/// Keeps write progress and its outcome visible even when a form is scrolled.
/// The notice itself can scroll on short screens and above an open keyboard.
class ConnectedActionFeedbackFrame extends StatelessWidget {
  const ConnectedActionFeedbackFrame({
    super.key,
    required this.child,
    this.notice,
    this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final Widget child;
  final ConnectedActionNotice? notice;
  final VoidCallback? onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final value = notice;
    final colors = SemanticColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final error = value?.state == ConnectedActionState.error;
    final working = value?.state == ConnectedActionState.working;
    final foreground = error ? scheme.onErrorContainer : colors.textPrimary;
    return LayoutBuilder(builder: (context, constraints) {
      return Column(children: [
        if (value != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.4),
            child: SingleChildScrollView(
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:
                        error ? scheme.errorContainer : colors.primarySurface,
                    borderRadius: BorderRadius.circular(AppRadius.l),
                    border: Border.all(
                      color: error ? scheme.error : colors.primaryBorder,
                    ),
                  ),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (working)
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: scheme.primary,
                            ),
                          )
                        else
                          Icon(
                              error
                                  ? Icons.info_outline
                                  : Icons.check_circle_outline,
                              color: foreground,
                              size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(value.title,
                                style: TextStyle(
                                    color: foreground,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(value.message,
                                style:
                                    TextStyle(color: foreground, fontSize: 13)),
                            if (actionLabel != null && onAction != null)
                              TextButton(
                                  onPressed: onAction,
                                  child: Text(actionLabel!)),
                          ],
                        )),
                        if (!working && onDismiss != null)
                          IconButton(
                            tooltip: 'Dismiss message',
                            onPressed: onDismiss,
                            color: foreground,
                            icon: const Icon(Icons.close, size: 20),
                          ),
                      ]),
                ),
              ),
            ),
          ),
        Expanded(key: const ValueKey('action-feedback-content'), child: child),
      ]);
    });
  }
}
