import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cursor_feed.dart';

int _pageChannelSequence = 0;
final _clientGates = Expando<_RealtimeGate>();

class _RealtimeGate {
  Future<void> _tail = Future.value();
  Future<void> run(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.catchError((Object _) {});
    return result;
  }
}

/// Notifications only: no unbounded initial table SELECT. A subscribed/rejoined
/// channel resets the bounded page so a connection gap cannot silently skip data.
Stream<PageChange> pagedRowChanges(
  SupabaseClient client, {
  required String table,
  required String idColumn,
  required String filterColumn,
  required String filterValue,
}) {
  late StreamController<PageChange> controller;
  RealtimeChannel? channel;
  var cancelled = false;
  final gate = _clientGates[client] ??= _RealtimeGate();
  controller = StreamController<PageChange>(
    onListen: () {
      unawaited(
        gate.run(() async {
          if (cancelled) return;
          channel = client
              .channel('page-$table-${++_pageChannelSequence}')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: table,
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: filterColumn,
                  value: filterValue,
                ),
                callback: (payload) {
                  if (cancelled || controller.isClosed) return;
                  final deleted =
                      payload.eventType == PostgresChangeEvent.delete;
                  final id = (deleted
                      ? payload.oldRecord
                      : payload.newRecord)[idColumn] as String?;
                  if (id == null) return;
                  controller.add(
                    PageChange(
                      deleted
                          ? PageChangeKind.remove
                          : payload.eventType == PostgresChangeEvent.insert
                              ? PageChangeKind.insert
                              : PageChangeKind.update,
                      id,
                    ),
                  );
                },
              )
              .subscribe((status, error) {
            if (cancelled || controller.isClosed) return;
            if (status == RealtimeSubscribeStatus.subscribed) {
              controller.add(const PageChange(PageChangeKind.reset));
            } else if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut ||
                status == RealtimeSubscribeStatus.closed) {
              controller.addError(
                StateError(
                  'Live updates unavailable. Refresh to check current data.',
                ),
              );
            }
          });
        }).catchError((Object failure, StackTrace stack) {
          if (!cancelled && !controller.isClosed) {
            controller.addError(failure, stack);
          }
        }),
      );
    },
    onCancel: () async {
      cancelled = true;
      await gate.run(() async {
        final active = channel;
        if (active == null) return;
        // Installed SDK removeChannel starts last-socket disconnect unawaited.
        // Unsubscribe removes the channel registry entry; then await disconnect
        // explicitly under the same client-wide gate used by new subscriptions.
        await active.unsubscribe();
        if (client.getChannels().isEmpty) await client.realtime.disconnect();
      });
    },
  );
  return controller.stream;
}

/// A bounded snapshot plus targeted rechecks, with explicit channel removal on
/// cancellation. Newer reads supersede older ones; no historical table stream.
Stream<T> boundedLiveValue<T>({
  required Future<T> Function() read,
  required Stream<PageChange> Function() changes,
}) {
  late StreamController<T> controller;
  StreamSubscription<PageChange>? subscription;
  var cancelled = false;
  var generation = 0;
  Future<void> refresh() async {
    final current = ++generation;
    try {
      final value = await read();
      if (!cancelled && current == generation) controller.add(value);
    } catch (error, stack) {
      if (!cancelled && current == generation) {
        controller.addError(error, stack);
      }
    }
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = changes().listen(
        (_) => refresh(),
        onError: (Object error, StackTrace stack) {
          if (!cancelled) controller.addError(error, stack);
        },
      );
      refresh();
    },
    onCancel: () async {
      cancelled = true;
      ++generation;
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
