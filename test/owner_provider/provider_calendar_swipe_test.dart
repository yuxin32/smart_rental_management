import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_schedule_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/cursor_feed.dart';
import 'package:smart_rental_management/owner_provider/services/backend/schedule_binding.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';

final _calendar = find.byType(ProviderMonthCalendar);
final _day = find.byKey(const ValueKey('provider-calendar-2026-12-15'));
DateTime month(WidgetTester tester) =>
    tester.widget<ProviderMonthCalendar>(_calendar).month;

Future<void> mount(WidgetTester tester,
    {bool dark = false, double scale = 1, ScheduleBinding? binding}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: ProviderScheduleScreen(
          providerName: 'Provider',
          bookings: const [],
          initialDay: DateTime.utc(2026, 12, 15),
          binding: binding)));
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('horizontal drags cross years once in each direction: $dark',
        (tester) async {
      await mount(tester, dark: dark);
      // Slow dragging over a tappable date must work without a fast flick.
      await tester.timedDrag(
          _day, const Offset(-170, 0), const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(month(tester), DateTime.utc(2027, 1, 1));
      expect(tester.widget<ProviderMonthCalendar>(_calendar).selectedDay,
          DateTime.utc(2027, 1, 1));
      await tester.drag(_calendar, const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(month(tester), DateTime.utc(2026, 12, 1));
      // Arrows are still functional.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(month(tester), DateTime.utc(2026, 11, 1));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('date taps and short horizontal drags do not switch months',
      (tester) async {
    await mount(tester);
    await tester.tap(_day);
    await tester.pumpAndSettle();
    expect(tester.widget<ProviderMonthCalendar>(_calendar).selectedDay.day, 15);
    await tester.drag(_day, const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(month(tester), DateTime.utc(2026, 12, 1));
  });
  testWidgets(
      'vertical calendar drags scroll the page instead of changing month',
      (tester) async {
    await mount(tester, scale: 2);
    final position = tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first)
        .position;
    final before = position.pixels;
    await tester.drag(_calendar, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(before));
    expect(month(tester), DateTime.utc(2026, 12, 1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('swiping connected schedule opens the next backend month once',
      (tester) async {
    final ranges = <DateTime>[];
    final binding = ScheduleBinding(
        weekStart: DateTime.utc(2026, 12, 1),
        monthView: true,
        openFeed: (start, end) {
          ranges.add(start);
          return CursorFeed<Map<String, dynamic>>(
              active: false,
              loadPage: (_) async => const CursorPage(items: []),
              idOf: (row) => row['booking_id'] as String,
              compare: (a, b) => 0);
        });
    addTearDown(binding.dispose);
    binding.setActive(true);
    await mount(tester, binding: binding);
    final before = ranges.length;
    await tester.drag(_day, const Offset(-170, 0));
    await tester.pumpAndSettle();
    expect(month(tester), DateTime.utc(2027, 1, 1));
    expect(ranges.length, before + 1);
    expect(binding.weekStart, DateTime.utc(2027, 1, 1));
    expect(tester.widget<ProviderMonthCalendar>(_calendar).complete, isTrue);
    expect(tester.takeException(), isNull);
  });
}
