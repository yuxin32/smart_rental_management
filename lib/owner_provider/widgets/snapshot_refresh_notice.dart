import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Routine SWR refreshes stay silent. Only a failed refresh needs a notice.
class SnapshotRefreshNotice extends StatelessWidget {
  const SnapshotRefreshNotice(
      {super.key,
      required this.refreshing,
      required this.failed,
      this.onRetry});
  final bool refreshing, failed;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    if (refreshing || !failed) return const SizedBox.shrink();
    return Semantics(
        liveRegion: true,
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 4),
              Text(
                  'Could not refresh. Showing saved data; it may be out of date.',
                  style: TextStyle(
                      color: SemanticColors.of(context).textSecondary,
                      fontSize: 12)),
              if (failed && !refreshing && onRetry != null)
                TextButton(
                    onPressed: onRetry, child: const Text('Retry update')),
            ])));
  }
}
