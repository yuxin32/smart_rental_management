import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'cursor_feed.dart';
import 'notification_snapshot.dart';
import 'session_snapshot_cache.dart';

typedef OwnedWorkspaceLoader = Future<Map<String, dynamic>> Function(
    {PageCursor? before, String? asOf});

/// Same-account SWR, bounded keyset pages and auth/lifecycle race protection.
class OwnedWorkspaceBinding extends ChangeNotifier {
  OwnedWorkspaceBinding(
      {required this.load,
      required this.userId,
      required this.currentUserId,
      required Stream<String?> sessions,
      this.cache,
      this.cacheKey,
      this.idField = 'booking_id'}) {
    if (cacheKey != null)
      snapshot = cache?.peek<Map<String, dynamic>>(cacheKey!)?.value;
    _session = sessions.listen((id) {
      if (id != userId) _end();
    }, onError: (Object e) {
      if (!_disposed) {
        refreshError = e;
        notifyListeners();
      }
    });
  }
  final OwnedWorkspaceLoader load;
  final String userId, idField;
  final String? Function() currentUserId;
  final SessionSnapshotCache? cache;
  final String? cacheKey;
  StreamSubscription<String?>? _session;
  Map<String, dynamic>? snapshot;
  bool loading = true,
      loadingMore = false,
      sessionEnded = false,
      _active = false,
      _disposed = false;
  Object? error, refreshError, moreError;
  int _generation = 0;
  bool get valid =>
      !_disposed &&
      !sessionEnded &&
      userId.isNotEmpty &&
      currentUserId() == userId;
  List<Map<String, dynamic>> get items =>
      List<Map<String, dynamic>>.from(snapshot?['items'] ?? const []);
  PageCursor? get next {
    final row = snapshot?['next_cursor'] as Map?;
    return row == null
        ? null
        : PageCursor(row['timestamp'] as String, row['id'] as String);
  }

  void _end() {
    if (_disposed || sessionEnded) return;
    sessionEnded = true;
    ++_generation;
    snapshot = null;
    loading = false;
    loadingMore = false;
    cache?.bindSession(currentUserId());
    notifyListeners();
  }

  void setActive(bool value) {
    if (!valid) {
      _end();
      return;
    }
    if (_active == value) return;
    _active = value;
    ++_generation;
    loading = false;
    loadingMore = false;
    if (value) refresh();
  }

  void _validate(Map<String, dynamic> row) {
    if (row['actor_id'] != userId) throw const FormatException('Wrong account');
    if (row.containsKey('items')) {
      final items = List<Map<String, dynamic>>.from(row['items'] as List);
      if (items.length > 20 ||
          items.map((e) => e[idField]).toSet().length != items.length ||
          items.any((e) => e[idField] is! String))
        throw const FormatException('Invalid page');
      final cursor = row['next_cursor'] as Map?;
      if (cursor != null) {
        BookingNotification.time(cursor['timestamp'] as String);
        if (items.isEmpty || cursor['id'] != items.last[idField])
          throw const FormatException('Invalid cursor');
      }
    }
  }

  Future<void> refresh() async {
    if (!valid) {
      _end();
      return;
    }
    if (!_active) return;
    final generation = ++_generation, lease = cache?.lease();
    loading = true;
    loadingMore = false;
    error = null;
    refreshError = null;
    moreError = null;
    notifyListeners();
    try {
      final row = await load();
      _validate(row);
      if (!valid) {
        _end();
        return;
      }
      if (!_active || generation != _generation) return;
      if (lease != null && !cache!.valid(lease))
        throw StateError('Data changed; retry');
      snapshot = row;
      if (cacheKey != null && lease != null)
        cache!.put(cacheKey!, row,
            lease: lease, bytes: utf8.encode(jsonEncode(row)).length + 512);
    } catch (e) {
      if (valid && generation == _generation) {
        if (snapshot != null && !rejectsSnapshot(e)) {
          refreshError = e;
        } else {
          snapshot = null;
          error = e;
          if (rejectsSnapshot(e)) cache?.clear();
        }
      }
    } finally {
      if (valid && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (!valid || !_active || loading || loadingMore || next == null) return;
    final previous = snapshot!, cursor = next!, generation = _generation;
    loadingMore = true;
    moreError = null;
    notifyListeners();
    try {
      final row =
          await load(before: cursor, asOf: previous['as_of'] as String?);
      _validate(row);
      if (!valid) {
        _end();
        return;
      }
      if (!_active || generation != _generation) return;
      final old = List<Map<String, dynamic>>.from(previous['items'] as List);
      final added = List<Map<String, dynamic>>.from(row['items'] as List);
      if (row['as_of'] != previous['as_of'] ||
          added.any((e) => old.any((p) => p[idField] == e[idField])) ||
          (row['next_cursor'] != null &&
              (row['next_cursor'] as Map)['id'] == cursor.id))
        throw const FormatException('Page changed; refresh');
      snapshot = {
        ...row,
        'items': [...old, ...added]
      };
    } catch (e) {
      if (valid && generation == _generation) {
        moreError = e;
        if (rejectsSnapshot(e)) {
          snapshot = null;
          error = e;
        }
      }
    } finally {
      if (valid && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _session?.cancel();
    super.dispose();
  }
}
