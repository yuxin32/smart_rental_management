import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/services/backend/cursor_feed.dart';
import 'package:smart_rental_management/owner_provider/services/backend/schedule_binding.dart';

Map<String, dynamic> row(String id) => {
      'booking_id': id,
      'current_status': 'Accepted',
      'unit_name': 'Server unit',
      'building_name': 'Server building',
      'service_name': 'Cleaning',
      'requested_start_at': '2030-01-07T02:00:00Z',
      'requested_end_at': '2030-01-07T04:00:00Z'
    };
void main() {
  test('month windows use MYT boundaries, including leap days and year changes',
      () {
    final ranges = <(DateTime, DateTime)>[];
    final binding = ScheduleBinding(
        weekStart: DateTime(2032, 2, 29),
        monthView: true,
        openFeed: (start, end) {
          ranges.add((start, end));
          return CursorFeed<Map<String, dynamic>>(
              active: false,
              loadPage: (_) async => const CursorPage(items: []),
              idOf: (r) => r['booking_id'] as String,
              compare: (_, __) => 0);
        });
    addTearDown(binding.dispose);
    expect(ranges.single.$1, DateTime.utc(2032, 1, 31, 16));
    expect(ranges.single.$2, DateTime.utc(2032, 2, 29, 16));
    expect(ranges.single.$2.difference(ranges.single.$1).inDays, 29);
    binding.changeMonth(DateTime(2033, 1, 31));
    expect(ranges.last.$1, DateTime.utc(2032, 12, 31, 16));
    expect(ranges.last.$2, DateTime.utc(2033, 1, 31, 16));
  });
  test(
      'MYT Monday converts to previous Sunday 16 UTC independent of machine timezone',
      () {
    final week = ScheduleBinding.monday(DateTime(2030, 1, 9, 23));
    expect(week, DateTime.utc(2030, 1, 7));
    expect(ScheduleBinding.weekStartUtc(week), DateTime.utc(2030, 1, 6, 16));
  });
  test('paging stays explicitly incomplete until all calendar pages arrive',
      () async {
    final windows = <(DateTime, DateTime)>[];
    final binding = ScheduleBinding(
        weekStart: DateTime(2030, 1, 7),
        openFeed: (start, end) {
          windows.add((start, end));
          return CursorFeed<Map<String, dynamic>>(
              active: false,
              loadPage: (cursor) async => cursor == null
                  ? CursorPage(
                      items: [row('one')],
                      next: const PageCursor('2030-01-01', 'one'))
                  : CursorPage(items: [row('two')]),
              idOf: (row) => row['booking_id'] as String,
              compare: (_, __) => 0);
        });
    addTearDown(binding.dispose);
    binding.setActive(true);
    await binding.refresh();
    expect(binding.complete, false);
    expect(binding.bookings.length, 1);
    await binding.loadMore();
    expect(binding.complete, true);
    expect(binding.bookings.length, 2);
    expect(windows.single.$2.difference(windows.single.$1),
        const Duration(days: 7));
  });
  test('changing week clears previous cards and discards late responses',
      () async {
    final first = Completer<CursorPage<Map<String, dynamic>>>();
    var opens = 0;
    final binding = ScheduleBinding(
        weekStart: DateTime(2030, 1, 7),
        openFeed: (start, end) {
          final index = opens++;
          return CursorFeed<Map<String, dynamic>>(
              active: false,
              loadPage: (_) => index == 0
                  ? first.future
                  : Future.value(CursorPage(items: [row('new-week')])),
              idOf: (row) => row['booking_id'] as String,
              compare: (_, __) => 0);
        });
    addTearDown(binding.dispose);
    binding.setActive(true);
    binding.changeWeek(DateTime(2030, 1, 14));
    await binding.refresh();
    first.complete(CursorPage(items: [row('old-week')]));
    await Future<void>.delayed(Duration.zero);
    expect(binding.bookings.single.id, 'new-week');
    expect(binding.weekStart, DateTime.utc(2030, 1, 14));
  });
  test('session end clears private data and cannot create a new-week feed',
      () async {
    final sessions = StreamController<String?>.broadcast();
    var opens = 0;
    final binding = ScheduleBinding(
        weekStart: DateTime(2030, 1, 7),
        openFeed: (start, end) {
          opens++;
          return CursorFeed<Map<String, dynamic>>(
              active: false,
              ownerUserId: 'a',
              sessionChanges: sessions.stream,
              loadPage: (_) async => CursorPage(items: [row('private')]),
              idOf: (row) => row['booking_id'] as String,
              compare: (_, __) => 0);
        });
    binding.setActive(true);
    await binding.refresh();
    sessions.add('b');
    await Future<void>.delayed(Duration.zero);
    expect(binding.bookings, isEmpty);
    expect(binding.error, isNotNull);
    binding.changeWeek(DateTime(2030, 1, 14));
    expect(opens, 1);
    binding.dispose();
    await sessions.close();
  });
}
