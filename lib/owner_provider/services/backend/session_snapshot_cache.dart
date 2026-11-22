import 'package:supabase_flutter/supabase_flutter.dart';

class SnapshotLease {
  const SnapshotLease(this.userId, this.generation);
  final String? userId;
  final int generation;
}

class SavedSnapshot<T> {
  const SavedSnapshot(this.value, this.savedAt, this.bytes);
  final T value;
  final DateTime savedAt;
  final int bytes;
}

/// Bounded MEMORY-ONLY view snapshots, not authorization or write inputs.
/// A backend/project owns one store. Writes invalidate leases so pre-write reads
/// cannot repopulate old state; auth epochs also protect A -> logout -> A.
class SessionSnapshotCache {
  SessionSnapshotCache(
      {required this.currentUserId,
      this.maxEntries = 16,
      this.maxBytes = 2 * 1024 * 1024,
      this.maxAge = const Duration(minutes: 5),
      DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final String? Function() currentUserId;
  final int maxEntries, maxBytes;
  final Duration maxAge;
  final DateTime Function() _now;
  final _entries = <String, SavedSnapshot<Object>>{};
  String? _owner;
  int _generation = 0, _bytes = 0, _writes = 0;
  int get entryCount => _entries.length;
  int get sizeBytes => _bytes;
  void bindSession(String? id) {
    if (id == _owner) return;
    clear();
    _owner = id;
  }

  void clear() {
    ++_generation;
    _entries.clear();
    _bytes = 0;
  }

  SnapshotLease lease() {
    bindSession(currentUserId());
    return SnapshotLease(_owner, _generation);
  }

  bool valid(SnapshotLease lease) =>
      _writes == 0 &&
      lease.userId != null &&
      currentUserId() == lease.userId &&
      _owner == lease.userId &&
      _generation == lease.generation;
  SavedSnapshot<T>? peek<T extends Object>(String key) {
    bindSession(currentUserId());
    if (_owner == null) return null;
    final entry = _entries.remove(key);
    if (entry == null) return null;
    final age = _now().difference(entry.savedAt);
    if (age.isNegative || age >= maxAge) {
      _bytes -= entry.bytes;
      return null;
    }
    _entries[key] = entry;
    return SavedSnapshot(entry.value as T, entry.savedAt, entry.bytes);
  }

  void put<T extends Object>(String key, T value,
      {required SnapshotLease lease, required int bytes}) {
    if (!valid(lease) || bytes <= 0 || bytes > maxBytes || maxEntries <= 0)
      return;
    final previous = _entries.remove(key);
    if (previous != null) _bytes -= previous.bytes;
    while (_entries.isNotEmpty &&
        (_entries.length >= maxEntries || _bytes + bytes > maxBytes)) {
      final old = _entries.remove(_entries.keys.first)!;
      _bytes -= old.bytes;
    }
    _entries[key] = SavedSnapshot<Object>(value, _now(), bytes);
    _bytes += bytes;
  }

  /// Invalidate before AND after a write, including an uncertain transport error.
  Future<T> write<T>(Future<T> Function() action) async {
    ++_writes;
    clear();
    try {
      return await action();
    } finally {
      --_writes;
      clear();
    }
  }
}

bool rejectsSnapshot(Object error) =>
    error is FormatException ||
    error is TypeError ||
    error is AuthException ||
    error is PostgrestException &&
        const {'42501', '28000', '28P01', 'PGRST301', 'PGRST302', 'PGRST303'}
            .contains(error.code);
