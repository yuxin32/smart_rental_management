import 'dart:async';
import 'package:flutter/foundation.dart';
import 'cursor_feed.dart';
import 'notification_snapshot.dart';
import 'supabase_notification_repository.dart';
import 'supabase_backend_provider.dart';
import 'paged_realtime.dart';
import 'session_snapshot_cache.dart';

typedef NotificationLoader = Future<NotificationSnapshot>
    Function(NotificationFilter filter, {PageCursor? before, String? asOf});
typedef NotificationMarker = Future<void> Function(
    {List<String>? ids, String? throughAt});

class NotificationBinding extends ChangeNotifier {
  NotificationBinding(
      {required this.load,
      required this.mark,
      required this.userId,
      required this.currentUserId,
      required Stream<String?> sessions,
      required this.changes}) {
    _session = sessions.listen((id) {
      if (id != userId) _endSession();
    }, onError: (Object e) {
      if (_valid) {
        liveError = e;
        notifyListeners();
      }
    });
  }
  factory NotificationBinding.connected(SupabaseBackendProvider backend,
      {required bool provider}) {
    // An auth change racing route construction renders Sign in again instead
    // of crashing the page. No query/channel starts for the empty identity.
    final id = backend.client.auth.currentUser?.id ?? '';
    final repo = SupabaseNotificationRepository(backend.client);
    return NotificationBinding(
        load: repo.page,
        mark: repo.mark,
        userId: id,
        currentUserId: () => backend.client.auth.currentUser?.id,
        sessions: backend.client.auth.onAuthStateChange
            .map((e) => e.session?.user.id),
        changes: () => pagedRowChanges(backend.client,
            table: 'booking',
            idColumn: 'booking_id',
            filterColumn: provider ? 'provider_id' : 'owner_id',
            filterValue: id));
  }
  final NotificationLoader load;
  final NotificationMarker mark;
  final String userId;
  final String? Function() currentUserId;
  final Stream<PageChange> Function() changes;
  StreamSubscription<String?>? _session;
  StreamSubscription<PageChange>? _live;
  Timer? _timer;
  bool _disposed = false, _active = false, _refreshAgain = false;
  int _generation = 0;
  NotificationFilter filter = NotificationFilter.all;
  NotificationSnapshot? snapshot;
  bool loading = true, loadingMore = false, busy = false, sessionEnded = false;
  Object? error, refreshError, moreError, writeError, liveError;
  bool get _valid => !_disposed && !sessionEnded && currentUserId() == userId;
  void _endSession() {
    if (_disposed || sessionEnded) return;
    sessionEnded = true;
    ++_generation;
    snapshot = null;
    loading = false;
    loadingMore = false;
    busy = false;
    _live?.cancel();
    _timer?.cancel();
    error = StateError('Session ended');
    notifyListeners();
  }

  void setActive(bool active) {
    if (!_valid) {
      _endSession();
      return;
    }
    if (active == _active) return;
    _active = active;
    ++_generation;
    _live?.cancel();
    _live = null;
    _timer?.cancel();
    loading = false;
    loadingMore = false;
    if (active) {
      _live = changes().listen((_) {
        if (!_valid || !_active) return;
        _timer?.cancel();
        _timer = Timer(const Duration(milliseconds: 200), () {
          if (loading || busy) {
            _refreshAgain = true;
          } else {
            refresh();
          }
        });
      }, onError: (Object e) {
        if (_valid && _active) {
          liveError = e;
          notifyListeners();
        }
      });
      refresh();
    }
  }

  void select(NotificationFilter value) {
    if (!_valid || busy || value == filter) return;
    filter = value;
    snapshot = null;
    ++_generation;
    loading = false;
    refresh();
  }

  Future<void> refresh() async {
    if (!_valid || !_active || busy || loading) return;
    final generation = ++_generation;
    loading = true;
    loadingMore = false;
    error = null;
    refreshError = null;
    moreError = null;
    notifyListeners();
    try {
      final value = await load(filter);
      if (!_valid || !_active || generation != _generation) return;
      snapshot = value;
      writeError = null;
    } catch (e) {
      if (!_valid || !_active || generation != _generation) return;
      if (rejectsSnapshot(e)) {
        snapshot = null;
        error = e;
      } else if (snapshot != null) {
        refreshError = e;
      } else {
        error = e;
      }
    } finally {
      if (_valid && generation == _generation) {
        loading = false;
        notifyListeners();
        _drainRefresh();
      }
    }
  }

  void _drainRefresh() {
    if (_refreshAgain && _active && !busy && !loading) {
      _refreshAgain = false;
      refresh();
    }
  }

  Future<void> loadMore() async {
    final previous = snapshot;
    if (!_valid ||
        !_active ||
        busy ||
        loading ||
        loadingMore ||
        previous?.next == null) return;
    final generation = _generation;
    loadingMore = true;
    moreError = null;
    notifyListeners();
    try {
      final value =
          await load(filter, before: previous!.next, asOf: previous.asOf);
      if (_valid && _active && generation == _generation)
        snapshot = previous.append(value);
    } catch (e) {
      if (_valid && generation == _generation) {
        moreError = e;
        if (rejectsSnapshot(e)) {
          snapshot = null;
          error = e;
        }
      }
    } finally {
      if (_valid && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<bool> read({String? id, bool all = false}) async {
    if (!_valid || !_active || busy || snapshot == null) return false;
    // A tap may arrive during silent revalidation. Invalidate that read rather
    // than opening a viewed notification without persisting its receipt.
    loading = false;
    loadingMore = false;
    busy = true;
    writeError = null;
    final generation = ++_generation;
    notifyListeners();
    var confirmed = false;
    try {
      await mark(
          ids: all ? null : [id!], throughAt: all ? snapshot!.asOf : null);
      if (!_valid || generation != _generation) return false;
      confirmed = true;
    } catch (e) {
      if (_valid && generation == _generation) {
        writeError = e;
        if (rejectsSnapshot(e)) {
          snapshot = null;
          error = e;
        }
      }
    } finally {
      // Reconcile even after timeout: the server may have committed the receipt.
      if (!_disposed) {
        busy = false;
        notifyListeners();
        if (_valid && _active) await refresh();
      }
    }
    return confirmed && _valid;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _live?.cancel();
    _session?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
