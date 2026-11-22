import 'package:flutter/material.dart';
import '../services/backend/cursor_feed.dart';
import 'connected_state_panel.dart';

class ConnectedPagedList<T> extends StatelessWidget {
  const ConnectedPagedList({
    super.key,
    required this.feed,
    required this.itemBuilder,
    required this.emptyTitle,
    required this.emptyMessage,
    this.errorTitle = 'Could not load records',
    this.moreLabel = 'Load older records',
    this.embedded = false,
    this.reverse = false,
    this.showCount = true,
    this.emptyActionLabel,
    this.onEmptyAction,
  });
  final CursorFeed<T> feed;
  final Widget Function(T) itemBuilder;
  final String emptyTitle, emptyMessage, errorTitle, moreLabel;
  final bool embedded, reverse, showCount;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: feed,
        builder: (context, _) {
          if (feed.sessionEnded) {
            return const ConnectedStatePanel(
              state: ConnectedViewState.error,
              title: 'Session ended',
              message: 'Sign in again to view your records.',
            );
          }
          if (feed.loading) {
            return const ConnectedStatePanel(
              state: ConnectedViewState.loading,
              title: 'Loading records',
              message: 'Getting the latest records.',
            );
          }
          if (feed.error != null) {
            return ConnectedStatePanel(
              state: ConnectedViewState.error,
              title: errorTitle,
              message:
                  'Check your connection and try again. Your saved information has not been removed.',
              actionLabel: 'Retry',
              onAction: feed.refresh,
            );
          }
          final rows = feed.items;
          if (rows.isEmpty && feed.liveError == null) {
            return ConnectedStatePanel(
              state: ConnectedViewState.empty,
              title: emptyTitle,
              message: emptyMessage,
              actionLabel: emptyActionLabel,
              onAction: onEmptyAction,
            );
          }
          final footer = Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                if (feed.moreError != null)
                  const Text(
                    'Could not show older items. The items already shown are still available.',
                  ),
                if (feed.hasMore)
                  OutlinedButton.icon(
                    onPressed: feed.loadingMore ? null : feed.loadMore,
                    icon: feed.loadingMore
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more),
                    label: Text(
                      feed.loadingMore
                          ? 'Loading…'
                          : feed.moreError != null
                              ? 'Retry loading older records'
                              : moreLabel,
                    ),
                  )
                else
                  const Text(
                    'You’re all caught up',
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          );
          final header = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showCount)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${rows.length} shown · Newest first',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (feed.liveError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      const Text('Live updates interrupted.'),
                      TextButton(
                        onPressed: feed.retryLive,
                        child: const Text('Reconnect'),
                      ),
                    ],
                  ),
                ),
            ],
          );
          Widget row(int index) => KeyedSubtree(
                key: ValueKey(feed.idOf(rows[index])),
                child: itemBuilder(rows[index]),
              );
          if (embedded) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                for (var index = 0; index < rows.length; index++) row(index),
                footer,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: header,
              ),
              Expanded(
                child: ListView.builder(
                  reverse: reverse,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: rows.length + 1,
                  itemBuilder: (_, index) =>
                      index == rows.length ? footer : row(index),
                ),
              ),
            ],
          );
        },
      );
}
