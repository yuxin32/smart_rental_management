import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/screens/owner_records_view.dart';
import 'package:smart_rental_management/owner_provider/services/backend/cursor_feed.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'package:smart_rental_management/owner_provider/widgets/booking_card.dart';

class SearchCall {
  const SearchCall(this.query, this.group, this.oldest);
  final String query, group;
  final bool oldest;
}

Map<String, dynamic> booking(int id, String status) => {
      'booking_id': '$id',
      'unit_name': id == 1 ? 'A-101' : 'B-201',
      'building_name': id == 1 ? 'Maple Residence' : 'Lakeview Suites',
      'service_name': 'Deep cleaning',
      'current_status': status,
      'requested_start_at': '2026-11-27T01:00:00Z',
      'requested_end_at': '2026-11-27T03:00:00Z',
    };

Future<void> mountBookings(WidgetTester tester,
    {required List<SearchCall> calls,
    bool dark = false,
    double scale = 1,
    bool empty = false,
    bool failed = false,
    VoidCallback? onRead}) async {
  final records = [booking(1, 'Pending'), booking(2, 'Completed')];
  await tester.pumpWidget(MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('Bookings')),
      body: OwnerRecordsView(
        providers: false,
        openFeed: ({required providers, required query, required group, required oldest}) {
          calls.add(SearchCall(query, group, oldest));
          final rows = empty ? <Map<String, dynamic>>[] : records.where((row) {
            final text = '${row['unit_name']} ${row['building_name']} ${row['service_name']}'.toLowerCase();
            final matchesQuery = text.contains(query.toLowerCase());
            final matchesStatus = switch (group) {
              'pending' => row['current_status'] == 'Pending',
              'history' => row['current_status'] == 'Completed',
              'completed' => row['current_status'] == 'Completed',
              'all' => true,
              _ => false,
            };
            return matchesQuery && matchesStatus;
          }).toList();
          return CursorFeed<Map<String, dynamic>>(
            active: false,
            loadPage: (_) async {
              onRead?.call();
              if (failed) throw StateError('Private database detail');
              return CursorPage(items: rows);
            },
            idOf: (row) => row['booking_id'] as String,
            compare: (a, b) => (oldest ? 1 : -1) *
                (a['booking_id'] as String).compareTo(b['booking_id'] as String),
          );
        },
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('compact search and Sort share a row and show the first booking early', (tester) async {
    phone(tester);
    await mountBookings(tester, calls: []);
    expect(find.text('All your bookings'), findsNothing);
    expect(find.text('Select History above to use this filter.'), findsNothing);
    final search = tester.getRect(find.byKey(const Key('owner-record-search')));
    final sort = tester.getRect(find.byKey(const Key('owner-booking-sort')));
    expect((search.top - sort.top).abs(), lessThan(1));
    expect(sort.left, greaterThan(search.right));
    expect(tester.getTopLeft(find.byType(BookingCard).first).dy, lessThan(310));
    expect(find.text('2 bookings shown · Newest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('History dropdown is disabled elsewhere and resets without losing query or sort', (tester) async {
    phone(tester);
    final calls = <SearchCall>[];
    await mountBookings(tester, calls: calls);
    DropdownButton<String> picker() => tester.widget(find.byKey(const Key('owner-booking-group')));
    expect(picker().onChanged, isNull);
    await tester.enterText(find.byKey(const Key('owner-record-search')), 'cleaning');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('owner-booking-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<bool>, 'Oldest first'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('owner-booking-tab-history')));
    await tester.pumpAndSettle();
    expect(picker().onChanged, isNotNull);
    expect(calls.last.group, 'history');
    await tester.tap(find.byKey(const Key('owner-booking-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();
    expect(calls.last.group, 'completed');
    expect(picker().value, 'completed');
    await tester.tap(find.byKey(const ValueKey('owner-booking-tab-pending')));
    await tester.pumpAndSettle();
    expect(calls.last.group, 'pending');
    expect(calls.last.query, 'cleaning');
    expect(calls.last.oldest, isTrue);
    expect(picker().value, 'history');
    expect(picker().onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('owner-booking-tab-history')));
    await tester.pumpAndSettle();
    expect(picker().value, 'history');
    expect(calls.last.group, 'history');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sort is explicit, clear search reuses the active filter, refresh keeps both', (tester) async {
    phone(tester);
    final calls = <SearchCall>[];
    var reads = 0;
    await mountBookings(tester, calls: calls, onRead: () => reads++);
    await tester.tap(find.byKey(const Key('owner-booking-sort')));
    await tester.pumpAndSettle();
    final count = calls.length;
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<bool>, 'Newest first'));
    await tester.pumpAndSettle();
    expect(calls.length, count);
    await tester.tap(find.byKey(const ValueKey('owner-booking-tab-pending')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('owner-record-search')), 'Maple');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(calls.last.query, 'Maple');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(calls.last.query, '');
    expect(calls.last.group, 'pending');
    final readsBefore = reads;
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(reads, greaterThan(readsBefore));
    expect(calls.last.group, 'pending');
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('search, tabs, sort and History fit 320px at 200% dark=$dark', (tester) async {
      phone(tester);
      final calls = <SearchCall>[];
      await mountBookings(tester, calls: calls, dark: dark, scale: 2, empty: true);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('owner-booking-sort')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(CheckedPopupMenuItem<bool>, 'Oldest first'));
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<bool>, 'Oldest first'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('owner-booking-tab-history')));
      await tester.tap(find.byKey(const ValueKey('owner-booking-tab-history')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('owner-booking-group')));
      await tester.tap(find.byKey(const Key('owner-booking-group')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancelled').last);
      await tester.tap(find.text('Cancelled').last);
      await tester.pumpAndSettle();
      expect(calls.last.group, 'cancelled');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed initial query does not mislabel unknown results as zero bookings', (tester) async {
    phone(tester);
    await mountBookings(tester, calls: [], failed: true);
    expect(find.text('Bookings unavailable · Newest'), findsOneWidget);
    expect(find.text('0 bookings shown · Newest'), findsNothing);
    expect(find.textContaining('Private database detail'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
