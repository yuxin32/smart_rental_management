import 'dart:async';
import 'package:flutter/foundation.dart';
import 'provider_profile_snapshot.dart';
import 'supabase_backend_provider.dart';
import 'session_snapshot_cache.dart';
import 'dart:convert';

class ProviderProfileBinding extends ChangeNotifier {
  ProviderProfileBinding(
      {required this.load,
      required this.userId,
      required this.currentUserId,
      this.cache,
      this.allowCached = false,
      required Stream<String?> sessionChanges}) {
    if (allowCached)
      snapshot = cache?.peek<ProviderProfileSnapshot>('profile:self:v1')?.value;
    _session = sessionChanges.listen((id) {
      if (id != userId) _endSession();
    });
  }
  factory ProviderProfileBinding.connected(SupabaseBackendProvider backend,
          {bool allowCached = true}) =>
      ProviderProfileBinding(
          cache: backend.snapshots,
          allowCached: allowCached,
          load: backend.provider.myProfile,
          userId: backend.client.auth.currentUser!.id,
          currentUserId: () => backend.client.auth.currentUser?.id,
          sessionChanges: backend.client.auth.onAuthStateChange
              .map((e) => e.session?.user.id));
  final Future<ProviderProfileSnapshot> Function() load;
  final String userId;
  final String? Function() currentUserId;
  final SessionSnapshotCache? cache;
  final bool allowCached;
  StreamSubscription<String?>? _session;
  ProviderProfileSnapshot? snapshot;
  Object? error;
  Object? refreshError;
  bool get refreshing => loading && snapshot != null;
  bool loading = true, sessionEnded = false, _active = false, _disposed = false;
  int _generation = 0;
  bool get canEdit => !_disposed && !sessionEnded && currentUserId() == userId;
  void _endSession() {
    if (_disposed || sessionEnded) return;
    sessionEnded = true;
    cache?.bindSession(currentUserId());
    ++_generation;
    snapshot = null;
    loading = false;
    error = StateError('Session changed');
    notifyListeners();
  }

  void setActive(bool active, {bool refreshOnResume = true}) {
    if (!canEdit) {
      if (!_disposed) _endSession();
      return;
    }
    if (_active == active) return;
    _active = active;
    ++_generation;
    if (active && (refreshOnResume || snapshot == null)) refresh();
  }

  Future<void> refresh() async {
    if (!_active || !canEdit) return;
    final generation = ++_generation;
    final lease = cache?.lease();
    loading = true;
    error = null;
    refreshError = null;
    if (!allowCached) snapshot = null;
    notifyListeners();
    try {
      final value = await load();
      if (!canEdit) {
        if (!_disposed) _endSession();
        return;
      }
      if (!_active || generation != _generation) return;
      if (lease != null && !cache!.valid(lease)) {
        throw StateError(
            'Data changed during refresh. Retry to verify the latest profile.');
      }
      snapshot = value;
      if (lease != null)
        cache!.put('profile:self:v1', value,
            lease: lease,
            bytes: utf8.encode(jsonEncode(value.row)).length + 512);
    } catch (e) {
      if (!_disposed && generation == _generation) {
        if (allowCached && snapshot != null && !rejectsSnapshot(e)) {
          refreshError = e;
        } else {
          snapshot = null;
          error = e;
          if (rejectsSnapshot(e)) cache?.clear();
        }
      }
    } finally {
      if (canEdit && _active && generation == _generation) {
        loading = false;
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
