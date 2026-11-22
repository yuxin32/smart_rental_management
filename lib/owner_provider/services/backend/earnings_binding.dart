import 'dart:async';
import 'package:flutter/foundation.dart';
import 'cursor_feed.dart';
import 'earnings_snapshot.dart';
import 'paged_realtime.dart';
import 'supabase_backend_provider.dart';
import 'supabase_earnings_repository.dart';
import 'session_snapshot_cache.dart';
import 'dart:convert';

typedef EarningsLoader = Future<EarningsSnapshot>
    Function(EarningsPeriod period, {PageCursor? before, String? asOf});

/// Owns reporting reads, never app fixture stores; stale/session reads discarded.
class EarningsBinding extends ChangeNotifier {
  EarningsBinding(
      {required this.load,
      required this.userId,
      required this.currentUserId,
      this.cache,
      required Stream<String?> sessionChanges,
      required this.changes}) {
    snapshot = cache?.peek<EarningsSnapshot>(_key)?.value;
    _session = sessionChanges.listen((id) {
      if (id != userId) _endSession();
    });
  }
  factory EarningsBinding.connected(SupabaseBackendProvider backend) {
    final actor = backend.client.auth.currentUser?.id;
    if (actor == null) throw StateError('Sign in required.');
    final repository = SupabaseEarningsRepository(backend.client);
    return EarningsBinding(
        cache: backend.snapshots,
        load: repository.read,
        userId: actor,
        currentUserId: () => backend.client.auth.currentUser?.id,
        sessionChanges: backend.client.auth.onAuthStateChange
            .map((e) => e.session?.user.id),
        changes: () => pagedRowChanges(backend.client,
            table: 'booking',
            idColumn: 'booking_id',
            filterColumn: 'provider_id',
            filterValue: actor));
  }
  final EarningsLoader load;
  final SessionSnapshotCache? cache;
  String get _key {
    final day = DateTime.now().toUtc().add(const Duration(hours: 8));
    return 'earnings:${period.name}:${day.year}-${day.month}-${day.day}';
  }

  final String userId;
  final String? Function() currentUserId;
  final Stream<PageChange> Function() changes;
  StreamSubscription<String?>? _session;
  StreamSubscription<PageChange>? _live;
  Timer? _debounce;
  EarningsPeriod period = EarningsPeriod.thisMonth;
  EarningsSnapshot? snapshot;
  Object? error, moreError, liveError, refreshError;
  bool get refreshing => loading && snapshot != null;
  bool loading = true, loadingMore = false, sessionEnded = false;
  bool _active = false, _disposed = false;
  int _generation = 0;
  bool get _valid => !_disposed && !sessionEnded && currentUserId() == userId;
  void _endSession() {
    if (_disposed || sessionEnded) return;
    sessionEnded = true;
    cache?.bindSession(currentUserId());
    ++_generation;
    snapshot = null;
    loading = false;
    loadingMore = false;
    error = StateError('Session ended.');
    moreError = null;
    liveError = null;
    _debounce?.cancel();
    _live?.cancel();
    _live = null;
    notifyListeners();
  }

  void setActive(bool active) {
    if (!_valid) {
      if (!_disposed) _endSession();
      return;
    }
    if (_active == active) return;
    _active = active;
    ++_generation;
    if (!active) {
      _debounce?.cancel();
      _live?.cancel();
      _live = null;
      loadingMore = false;
      return;
    }
    _live = changes().listen((change) {
      if (change.kind == PageChangeKind.reset) liveError = null;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), refresh);
    }, onError: (Object e) {
      if (!_valid || !_active) return;
      liveError = e;
      if (rejectsSnapshot(e)) {
        snapshot = null;
        error = e;
        cache?.clear();
      }
      notifyListeners();
    });
    refresh();
  }

  void select(EarningsPeriod value) {
    if (value == period || !_valid) return;
    period = value;
    snapshot = cache?.peek<EarningsSnapshot>(_key)?.value;
    refresh();
  }

  Future<void> refresh() async {
    if (!_valid || !_active) return;
    final generation = ++_generation;
    final key = _key;
    final lease = cache?.lease();
    loading = true;
    loadingMore = false;
    if (cache == null || snapshot?.period != period) snapshot = null;
    error = null;
    moreError = null;
    refreshError = null;
    notifyListeners();
    try {
      final value = await load(period);
      if (!_valid || !_active || generation != _generation) return;
      if (lease != null && !cache!.valid(lease)) {
        throw StateError(
            'Data changed during refresh. Retry to verify current figures.');
      }
      snapshot = value;
      if (lease != null) {
        final strings = value.records
            .map((r) => [r.bookingId, r.property, r.serviceLabel])
            .toList();
        cache!.put(key, value,
            lease: lease,
            bytes: utf8.encode(jsonEncode(strings)).length +
                1024 +
                value.records.length * 256 +
                value.buckets.length * 192);
      }
    } catch (e) {
      if (!_valid || generation != _generation) return;
      if (cache != null && snapshot != null && !rejectsSnapshot(e)) {
        refreshError = e;
      } else {
        snapshot = null;
        error = e;
        if (rejectsSnapshot(e)) cache?.clear();
      }
    } finally {
      if (_valid && _active && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    final previous = snapshot;
    if (!_valid || !_active || loading || loadingMore || previous?.next == null)
      return;
    final generation = _generation;
    loadingMore = true;
    moreError = null;
    notifyListeners();
    try {
      final page =
          await load(period, before: previous!.next, asOf: previous.asOf);
      if (!_valid || !_active || generation != _generation) return;
      snapshot = previous.append(page);
    } catch (e) {
      if (!_valid || generation != _generation) return;
      moreError = e;
      if (rejectsSnapshot(e)) {
        snapshot = null;
        error = e;
        cache?.clear();
      }
    } finally {
      if (_valid && _active && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  void retryLive() {
    if (!_valid || !_active) return;
    liveError = null;
    setActive(false);
    setActive(true);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _debounce?.cancel();
    _live?.cancel();
    _session?.cancel();
    super.dispose();
  }
}
