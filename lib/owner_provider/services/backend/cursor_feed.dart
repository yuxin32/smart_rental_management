import 'dart:async';

import 'package:flutter/foundation.dart';
import 'session_snapshot_cache.dart';

class PageCursor {
  const PageCursor(this.timestamp, this.id);
  final String timestamp;
  final String id;
}

class CursorPage<T> {
  const CursorPage({required this.items, this.next});
  final List<T> items;
  final PageCursor? next;
  bool get hasMore => next != null;

  static CursorPage<T> decode<T>(
    dynamic response,
    T Function(Map<String, dynamic>) decode,
  ) {
    final data = Map<String, dynamic>.from(response as Map);
    final raw = data['next_cursor'];
    if (data['has_more'] == true && raw is! Map) {
      throw const FormatException('Missing page cursor.');
    }
    return CursorPage<T>(
      items: List<Map<String, dynamic>>.from(data['items'] as List)
          .map(decode)
          .toList(growable: false),
      next: data['has_more'] == true
          ? PageCursor(raw['timestamp'] as String, raw['id'] as String)
          : null,
    );
  }
}

enum PageChangeKind { insert, update, remove, reset }

class PageChange {
  const PageChange(this.kind, [this.id]);
  final PageChangeKind kind;
  final String? id;
}

/// Bounded requests, keyset boundaries and ID de-duplication. Realtime reads
/// only the changed visible row (or an inserted row), never the whole history.
class CursorFeed<T> extends ChangeNotifier {
  CursorFeed({
    required this.loadPage,
    required this.idOf,
    required this.compare,
    this.readOne,
    this.recheckUnloadedUpdates = false,
    Stream<PageChange>? changes,
    Stream<PageChange> Function()? watchChanges,
    Stream<String?>? sessionChanges,
    this.ownerUserId,
    this.currentUserId,
    bool active = true,
    this.onServerChange,
    this.preserveOnRefresh = false,
    this.onSnapshotRejected,
    CursorPage<T>? initialPage,
  }) : _watchChanges =
            watchChanges ?? (changes == null ? null : () => changes) {
    if (initialPage != null) {
      _rows.addEntries(
          initialPage.items.map((item) => MapEntry(idOf(item), item)));
      _next = initialPage.next;
      hasSnapshot = true;
    }
    _sessionSubscription = sessionChanges?.listen(
      (userId) {
        if (userId != ownerUserId) invalidateSession();
      },
      onError: (Object failure) {
        if (_disposed || sessionEnded) return;
        liveError = failure;
        notifyListeners();
      },
    );
    setActive(active);
  }
  final Future<CursorPage<T>> Function(PageCursor?) loadPage;
  final String Function(T) idOf;
  final Comparator<T> compare;
  final Future<T?> Function(String)? readOne;

  /// Range-filtered views must recheck updates that can move a formerly
  /// out-of-range row into the visible interval (e.g. rescheduled bookings).
  final bool recheckUnloadedUpdates;
  final VoidCallback? onServerChange;
  final bool preserveOnRefresh;
  final VoidCallback? onSnapshotRejected;
  void _rejectSaved(Object failure) {
    if (!preserveOnRefresh || !rejectsSnapshot(failure)) return;
    onSnapshotRejected?.call();
    _rows.clear();
    _next = null;
    hasSnapshot = false;
    refreshError = null;
    error = failure;
  }

  bool hasSnapshot = false;
  Object? refreshError;
  bool get refreshing => preserveOnRefresh && loading && hasSnapshot;
  final Stream<PageChange> Function()? _watchChanges;
  final String? ownerUserId;
  final String? Function()? currentUserId;
  final Map<String, T> _rows = {};
  final Map<String, int> _rowVersions = {};
  final Set<String> _removed = {};
  final List<PageChange> _queued = [];
  StreamSubscription<PageChange>? _subscription;
  StreamSubscription<String?>? _sessionSubscription;
  Future<void> _watchTransition = Future.value();
  int _watchGeneration = 0;
  bool _active = false;
  bool sessionEnded = false;
  bool get active => _active && !sessionEnded && !_disposed;
  PageCursor? _next;
  bool _disposed = false;
  bool _resetAfterLoad = false;
  int _generation = 0;
  bool loading = true;
  bool loadingMore = false;
  Object? error;
  Object? moreError;
  Object? liveError;
  bool get hasMore => _next != null;
  List<T> get items => _rows.values.toList()..sort(compare);

  bool _authorized() {
    if (sessionEnded || _disposed) return false;
    if (currentUserId != null && currentUserId!() != ownerUserId) {
      invalidateSession();
      return false;
    }
    return true;
  }

  /// Stop, rather than pause, the underlying channel; pause would buffer events
  /// while continuing to consume a server connection. Resumption reads anew.
  void setActive(bool value) {
    if (!_authorized() || _active == value) return;
    _active = value;
    ++_generation;
    _resetAfterLoad = false;
    _queued.clear();
    loading = false;
    loadingMore = false;
    _syncWatch();
    if (value) {
      refresh();
    } else {
      notifyListeners();
    }
  }

  void _syncWatch() {
    final generation = ++_watchGeneration;
    _watchTransition = _watchTransition.then((_) async {
      final previous = _subscription;
      _subscription = null;
      await previous?.cancel();
      if (generation != _watchGeneration || !active || !_authorized()) return;
      _subscription = _watchChanges?.call().listen(
        (change) {
          if (generation == _watchGeneration && active && _authorized()) {
            _changed(change);
          }
        },
        onError: (Object failure) {
          if (generation != _watchGeneration || !active || !_authorized()) {
            return;
          }
          liveError = failure;
          _rejectSaved(failure);
          notifyListeners();
        },
        onDone: () {
          if (generation != _watchGeneration || !active || !_authorized()) {
            return;
          }
          liveError = StateError(
            'Live updates ended. Reconnect to check current records.',
          );
          notifyListeners();
        },
      );
    }).catchError((Object failure) {
      if (generation != _watchGeneration || !active || _disposed) return;
      liveError = failure;
      _rejectSaved(failure);
      notifyListeners();
    });
  }

  void retryLive() {
    if (!active || !_authorized()) return;
    _syncWatch();
    refresh();
  }

  void invalidateSession() {
    if (_disposed || sessionEnded) return;
    sessionEnded = true;
    _active = false;
    ++_generation;
    _next = null;
    _rows.clear();
    hasSnapshot = false;
    refreshError = null;
    _rowVersions.clear();
    _queued.clear();
    _removed.clear();
    _resetAfterLoad = false;
    loading = false;
    loadingMore = false;
    _syncWatch();
    unawaited(_sessionSubscription?.cancel() ?? Future<void>.value());
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!active || !_authorized()) return;
    final generation = ++_generation;
    loading = true;
    loadingMore = false;
    error = null;
    refreshError = null;
    moreError = null;
    liveError = null;
    _queued.clear();
    _rowVersions.clear();
    _removed.clear();
    notifyListeners();
    try {
      final page = await loadPage(null);
      if (!active || !_authorized() || generation != _generation) return;
      _rows
        ..clear()
        ..addEntries(page.items.map((item) => MapEntry(idOf(item), item)));
      _next = page.next;
      hasSnapshot = true;
    } catch (failure) {
      if (!active || !_authorized() || generation != _generation) return;
      if (preserveOnRefresh && hasSnapshot && !rejectsSnapshot(failure)) {
        refreshError = failure;
      } else {
        _rejectSaved(failure);
        if (preserveOnRefresh) {
          _rows.clear();
          _next = null;
          hasSnapshot = false;
        }
        error = failure;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
        final queued = List<PageChange>.of(_queued);
        _queued.clear();
        for (final change in queued) {
          _changed(change);
        }
        if (_resetAfterLoad) {
          _resetAfterLoad = false;
          refresh();
        }
      }
    }
  }

  Future<void> loadMore() async {
    if (!active || !_authorized() || loading || loadingMore || _next == null) {
      return;
    }
    final cursor = _next!;
    final generation = _generation;
    loadingMore = true;
    moreError = null;
    notifyListeners();
    try {
      final page = await loadPage(cursor);
      if (!active || !_authorized() || generation != _generation) return;
      if (page.next?.id == cursor.id &&
          page.next?.timestamp == cursor.timestamp) {
        throw const FormatException('Page cursor did not advance.');
      }
      for (final row in page.items) {
        final id = idOf(row);
        // A realtime read may already contain a newer version of this row.
        if (!_removed.contains(id)) _rows.putIfAbsent(id, () => row);
      }
      _next = page.next;
    } catch (failure) {
      if (!_disposed && generation == _generation) {
        _rejectSaved(failure);
        moreError = failure;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  void _changed(PageChange change) {
    if (!active || !_authorized()) return;
    onServerChange?.call();
    if (change.kind == PageChangeKind.reset) {
      if (loading) {
        _resetAfterLoad = true;
      } else {
        refresh();
      }
      return;
    }
    if (loading) {
      _queued.add(change);
      return;
    }
    final id = change.id;
    if (id == null) return;
    if (change.kind == PageChangeKind.update &&
        !_rows.containsKey(id) &&
        !recheckUnloadedUpdates) return;
    final version = (_rowVersions[id] ?? 0) + 1;
    _rowVersions[id] = version;
    if (change.kind == PageChangeKind.remove) {
      _removed.add(id);
      _rows.remove(id);
      notifyListeners();
      return;
    }
    if (readOne != null) _readChanged(id, version, _generation);
  }

  Future<void> _readChanged(String id, int version, int generation) async {
    try {
      final row = await readOne!(id);
      if (!active ||
          !_authorized() ||
          generation != _generation ||
          _rowVersions[id] != version) {
        return;
      }
      if (row == null) {
        _removed.add(id);
        _rows.remove(id);
      } else {
        _removed.remove(id);
        _rows[id] = row;
      }
      notifyListeners();
    } catch (failure) {
      if (!_disposed &&
          generation == _generation &&
          _rowVersions[id] == version) {
        liveError = failure;
        _rejectSaved(failure);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    ++_generation;
    _syncWatch();
    unawaited(_sessionSubscription?.cancel() ?? Future<void>.value());
    _rows.clear();
    _queued.clear();
    _rowVersions.clear();
    _removed.clear();
    super.dispose();
  }
}
