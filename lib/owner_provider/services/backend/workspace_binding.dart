import '../../presentation/workspace_text.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'session_snapshot_cache.dart';

import '../../models/demo_data.dart';
import 'cursor_feed.dart';
import 'supabase_backend_provider.dart';
import 'supabase_owner_repository.dart';

/// Data-only bridge into the existing presentation widgets. Never writes to
/// BookingStore/ProviderStore or loads a demo fixture on failure.
class WorkspaceBinding extends ChangeNotifier {
  WorkspaceBinding({
    required this.feed,
    required this.provider,
    this.cache,
    this.backend,
    required Future<dynamic> Function() loadOverview,
  }) : _loadOverview = loadOverview {
    final saved = cache?.peek<_WorkspaceOverview>(_key)?.value;
    if (saved != null) {
      _setOverview(saved.value);
      _hasOverview = true;
    }
    feed.addListener(_changed);
  }

  factory WorkspaceBinding.connected(SupabaseBackendProvider backend,
      {required bool provider}) {
    late WorkspaceBinding binding;
    binding = WorkspaceBinding(
      cache: backend.snapshots,
      backend: backend,
      provider: provider,
      feed: backend.bookings.openFeed(
        provider: provider,
        active: false,
        onServerChange: () => binding._refreshOverview(),
      ),
      loadOverview: () =>
          provider ? backend.provider.profile() : backend.owner.dashboard(),
    );
    return binding;
  }

  final CursorFeed<Map<String, dynamic>> feed;
  final bool provider;
  final SupabaseBackendProvider? backend;
  final SessionSnapshotCache? cache;
  String get _key => 'overview:$provider';
  bool _hasOverview = false;
  Object? _overviewRefreshError;
  void _setOverview(dynamic value) {
    if (provider) {
      providerProfile = value == null
          ? null
          : Map<String, dynamic>.unmodifiable(value as Map);
    } else {
      ownerSummary = value as OwnerDashboardSnapshot;
    }
  }

  final Future<dynamic> Function() _loadOverview;
  OwnerDashboardSnapshot? ownerSummary;
  Map<String, dynamic>? providerProfile;
  Object? _overviewError;
  bool _overviewLoading = true;
  bool _active = false;
  bool _disposed = false;
  int _generation = 0;

  bool get loading =>
      (feed.loading && !(cache != null && feed.hasSnapshot)) ||
      (_overviewLoading && !(cache != null && _hasOverview));
  bool get refreshing => !loading && (feed.loading || _overviewLoading);
  Object? get refreshError => feed.refreshError ?? _overviewRefreshError;
  Object? get error => feed.error ?? _overviewError ?? _projectionError;
  Object? get moreError => feed.moreError;
  Object? get liveError => feed.liveError;
  bool get hasMore => feed.hasMore;
  bool get loadingMore => feed.loadingMore;
  Object? get _projectionError {
    try {
      bookings;
      return null;
    } catch (error) {
      return error;
    }
  }

  /// Legacy class name retained only to reuse existing visual components.
  /// Identity/status/interval come exclusively from a server card. No invented
  /// rates, proof paths, provider statistics or display-name ownership checks.
  List<DemoBooking> get bookings => feed.items.map(projectBooking).toList();

  static DemoBooking projectBooking(Map<String, dynamic> row) {
    final status = switch (row['current_status']) {
      'Pending' => BookingStatus.pending,
      'Accepted' => BookingStatus.accepted,
      'In Progress' => BookingStatus.inProgress,
      'Completed' => BookingStatus.completed,
      'Declined' => BookingStatus.declined,
      'Cancelled' => BookingStatus.cancelled,
      _ => throw const FormatException('Unknown server booking status.'),
    };
    DateTime malaysiaWallTime(String field) {
      final value = row[field] as String;
      if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
        throw const FormatException('Server interval requires an offset.');
      }
      return DateTime.parse(value).toUtc().add(const Duration(hours: 8));
    }

    final start = malaysiaWallTime('requested_start_at');
    final end = malaysiaWallTime('requested_end_at');
    if (!end.isAfter(start)) {
      throw const FormatException('Invalid server interval.');
    }
    return DemoBooking(
      id: row['booking_id'] as String,
      property: [row['unit_name'], row['building_name']]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .map(workspaceText)
          .join(', '),
      serviceType: row['service_name'] as String,
      providerName: null,
      scheduledStart: start,
      scheduledEnd: end,
      status: status,
      specialInstructions: row['instructions'] is String
          ? workspaceText(row['instructions'] as String)
          : null,
    );
  }

  void _changed() {
    if (_disposed) return;
    if (feed.sessionEnded) {
      ++_generation;
      ownerSummary = null;
      providerProfile = null;
      _overviewLoading = false;
      _overviewError = StateError('Session ended. Sign in again.');
    }
    notifyListeners();
  }

  Future<void> _refreshOverview() async {
    if (_disposed || !_active || feed.sessionEnded) return;
    final generation = ++_generation;
    final lease = cache?.lease();
    _overviewLoading = true;
    _overviewError = null;
    _overviewRefreshError = null;
    notifyListeners();
    try {
      final value = await _loadOverview();
      if (_disposed ||
          !_active ||
          feed.sessionEnded ||
          generation != _generation) return;
      if (lease != null && !cache!.valid(lease)) {
        throw StateError(
            'Data changed during refresh. Retry to verify the workspace.');
      }
      _setOverview(value);
      _hasOverview = true;
      if (lease != null)
        cache!.put(
            _key, _WorkspaceOverview(provider ? providerProfile : ownerSummary),
            lease: lease,
            bytes: value is Map
                ? utf8.encode(jsonEncode(value)).length + 256
                : 256);
    } catch (error) {
      if (_disposed || generation != _generation) return;
      if (cache != null && _hasOverview && !rejectsSnapshot(error)) {
        _overviewRefreshError = error;
      } else {
        ownerSummary = null;
        providerProfile = null;
        _hasOverview = false;
        _overviewError = error;
        if (rejectsSnapshot(error)) cache?.clear();
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _overviewLoading = false;
        notifyListeners();
      }
    }
  }

  void setActive(bool active) {
    if (_disposed || _active == active || feed.sessionEnded) return;
    _active = active;
    if (!active) ++_generation;
    feed.setActive(active);
    if (active) _refreshOverview();
  }

  Future<void> refresh() async {
    if (_disposed || !_active || feed.sessionEnded) return;
    await Future.wait([feed.refresh(), _refreshOverview()]);
  }

  Future<void> loadMore() => feed.loadMore();
  void retryLive() {
    feed.retryLive();
    _refreshOverview();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    feed.removeListener(_changed);
    feed.dispose();
    super.dispose();
  }
}

class _WorkspaceOverview {
  const _WorkspaceOverview(this.value);
  final dynamic value;
}
