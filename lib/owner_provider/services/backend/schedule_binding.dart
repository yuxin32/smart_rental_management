import 'package:flutter/foundation.dart';

import '../../models/demo_data.dart';
import 'cursor_feed.dart';
import 'supabase_backend_provider.dart';
import 'workspace_binding.dart';

/// One bounded, participant-scoped MYT week. A partial calendar must never
/// masquerade as a complete free/busy view. No local stores or seeded fallback.
class ScheduleBinding extends ChangeNotifier {
  ScheduleBinding({
    required DateTime weekStart,
    bool monthView = false,
    required CursorFeed<Map<String, dynamic>> Function(DateTime, DateTime)
        openFeed,
  })  : _monthView = monthView,
        _weekStart = monthView
            ? DateTime.utc(weekStart.year, weekStart.month, 1)
            : monday(weekStart),
        _openFeed = openFeed {
    _createFeed();
  }

  factory ScheduleBinding.connected(SupabaseBackendProvider backend,
      {required bool provider, DateTime? initialDay}) {
    final userId = backend.client.auth.currentUser?.id;
    return ScheduleBinding(
        weekStart: initialDay ?? malaysiaNow(),
        monthView: provider,
        openFeed: (start, end) {
          if (userId == null || backend.client.auth.currentUser?.id != userId) {
            throw StateError('Session changed.');
          }
          return backend.bookings.openScheduleFeed(
              provider: provider, startUtc: start, endUtc: end);
        });
  }

  static DateTime malaysiaNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 8));
  static DateTime monday(DateTime day) {
    final date = DateTime.utc(day.year, day.month, day.day);
    return date.subtract(Duration(days: date.weekday - 1));
  }

  static DateTime weekStartUtc(DateTime wallMonday) =>
      DateTime.utc(wallMonday.year, wallMonday.month, wallMonday.day)
          .subtract(const Duration(hours: 8));

  final CursorFeed<Map<String, dynamic>> Function(DateTime, DateTime) _openFeed;
  DateTime _weekStart;
  bool _monthView;
  bool get monthView => _monthView;
  DateTime get periodEnd => _monthView
      ? DateTime.utc(_weekStart.year, _weekStart.month + 1, 1)
      : _weekStart.add(const Duration(days: 7));
  late CursorFeed<Map<String, dynamic>> _feed;
  bool _active = false;
  bool _disposed = false;
  bool _sessionEnded = false;
  DateTime get weekStart => _weekStart;
  bool get loading => _feed.loading;
  bool get hasSnapshot => _feed.hasSnapshot;
  bool get refreshing => _feed.refreshing;
  Object? get refreshError => _feed.refreshError;
  bool get hasMore => _feed.hasMore;
  bool get loadingMore => _feed.loadingMore;
  Object? get moreError => _feed.moreError;
  Object? get liveError => _feed.liveError;
  Object? get error {
    if (_sessionEnded) return StateError('Session ended. Sign in again.');
    if (_feed.error != null) return _feed.error;
    try {
      bookings;
      return null;
    } catch (failure) {
      return failure;
    }
  }

  bool get complete =>
      (!loading || (_feed.preserveOnRefresh && _feed.hasSnapshot)) &&
      error == null &&
      !hasMore &&
      !loadingMore &&
      moreError == null;
  List<DemoBooking> get bookings =>
      _feed.items.map(WorkspaceBinding.projectBooking).toList();

  void _createFeed() {
    final start = weekStartUtc(_weekStart);
    _feed = _openFeed(start, weekStartUtc(periodEnd));
    _feed.addListener(_changed);
    _feed.setActive(_active);
  }

  void _changed() {
    if (_disposed) return;
    if (_feed.sessionEnded) _sessionEnded = true;
    notifyListeners();
  }

  void changeWeek(DateTime day) {
    if (_disposed || _sessionEnded) return;
    final next = monday(day);
    if (next == _weekStart && !_monthView) return;
    _feed.removeListener(_changed);
    _feed.dispose();
    _weekStart = next;
    _monthView = false;
    _createFeed();
    notifyListeners();
  }

  void changeMonth(DateTime day) {
    if (_disposed || _sessionEnded) return;
    final next = DateTime.utc(day.year, day.month, 1);
    if (next == _weekStart && _monthView) return;
    _feed.removeListener(_changed);
    _feed.dispose();
    _weekStart = next;
    _monthView = true;
    _createFeed();
    notifyListeners();
  }

  void setActive(bool active) {
    if (_disposed || _sessionEnded) return;
    _active = active;
    _feed.setActive(active);
  }

  Future<void> refresh() => _feed.refresh();
  Future<void> loadMore() => _feed.loadMore();
  void retryLive() => _feed.retryLive();
  @override
  void dispose() {
    _disposed = true;
    _feed.removeListener(_changed);
    _feed.dispose();
    super.dispose();
  }
}
