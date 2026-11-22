import 'dart:async';

class CacheSessionChanged implements Exception {
  const CacheSessionChanged();
}

class CacheReadInvalidated implements Exception {
  const CacheReadInvalidated();
}

class CacheBusy implements Exception {
  const CacheBusy();
}

class _Entry {
  const _Entry(this.value, this.bytes, this.expiresAt);
  final Object value;
  final int bytes;
  final DateTime expiresAt;
}

/// Memory only. One instance belongs to one backend client/project. Identity
/// epochs protect A -> signed-out -> A as well as switches between different IDs.
/// Callers must freshly authorize private objects before invoking read.
class AuthenticatedMemoryCache {
  AuthenticatedMemoryCache({
    required this.currentUserId,
    this.maxBytes = 12 * 1024 * 1024,
    this.maxEntries = 24,
    this.maxInFlight = 4,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final String? Function() currentUserId;
  final int maxBytes, maxEntries, maxInFlight;
  final DateTime Function() _now;
  final _entries = <String, _Entry>{};
  final _pending = <String, Future<Object>>{};
  int _epoch = 0, _bytes = 0;
  int _runningLoads = 0;
  String? _owner;
  int get sizeBytes => _bytes;
  int get entryCount => _entries.length;
  int get inFlightCount => _runningLoads;
  int get generation => _epoch;

  void bindSession(String? userId) {
    if (_owner == userId) return;
    clear();
    _owner = userId;
  }

  void clear() {
    ++_epoch;
    _entries.clear();
    _pending.clear();
    _bytes = 0;
  }

  void evict(String key) {
    final entry = _entries.remove(key);
    if (entry != null) _bytes -= entry.bytes;
    _pending.remove(key);
  }

  void evictWhere(bool Function(String) predicate) {
    for (final key in {..._entries.keys, ..._pending.keys}) {
      if (predicate(key)) evict(key);
    }
  }

  void _prune() {
    final now = _now();
    for (final key in _entries.keys.toList(growable: false)) {
      if (!now.isBefore(_entries[key]!.expiresAt)) evict(key);
    }
  }

  Future<T> read<T extends Object>({
    required String key,
    required Duration ttl,
    required int Function(T) sizeOf,
    required Future<T> Function() load,
  }) async {
    final user = currentUserId();
    bindSession(user);
    if (user == null) throw const CacheSessionChanged();
    final epoch = _epoch;
    _prune();
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached; // LRU: the least recently used item is first.
      return cached.value as T;
    }
    final pending = _pending[key];
    if (pending != null) {
      final value = await pending;
      if (epoch != _epoch || currentUserId() != user) {
        throw const CacheSessionChanged();
      }
      return value as T;
    }
    if (_runningLoads >= maxInFlight) throw const CacheBusy();
    ++_runningLoads;
    late final Future<T> work;
    work = Future<T>.sync(load).then((value) {
      if (epoch != _epoch || currentUserId() != user) {
        if (currentUserId() != _owner) bindSession(currentUserId());
        throw const CacheSessionChanged();
      }
      if (!identical(_pending[key], work)) throw const CacheReadInvalidated();
      final bytes = sizeOf(value);
      if (bytes > 0 &&
          bytes <= maxBytes &&
          maxEntries > 0 &&
          ttl > Duration.zero) {
        while (_entries.isNotEmpty &&
            (_bytes + bytes > maxBytes || _entries.length >= maxEntries)) {
          evict(_entries.keys.first);
        }
        _entries[key] = _Entry(value, bytes, _now().add(ttl));
        _bytes += bytes;
      }
      return value;
    });
    _pending[key] = work;
    try {
      final value = await work;
      if (epoch != _epoch || currentUserId() != user) {
        throw const CacheSessionChanged();
      }
      return value;
    } finally {
      --_runningLoads;
      if (identical(_pending[key], work)) _pending.remove(key);
    }
  }
}
