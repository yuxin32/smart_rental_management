import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/models/local_preview_data.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_schedule_screen.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1200, 900),
  ]) {
    testWidgets('today job card fits schedule at ${size.width}px',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: ProviderScheduleScreen(
          providerName: 'Provider A',
          bookings: LocalPreviewData.bookings(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ProviderMonthCalendar), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Unit D-03, Menara Suria'), 180,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Unit D-03, Menara Suria'), findsWidgets);
      expect(find.text('Deep cleaning'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('month date selection and navigation update the focused day',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: ProviderScheduleScreen(
        providerName: 'Provider A',
        bookings: LocalPreviewData.bookings(),
      ),
    ));
    await tester.pumpAndSettle();

    final before = tester
        .widget<ProviderMonthCalendar>(find.byType(ProviderMonthCalendar));
    final month = before.month;
    final key =
        'provider-calendar-${month.year}-${month.month.toString().padLeft(2, '0')}-01';
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ProviderMonthCalendar>(find.byType(ProviderMonthCalendar))
            .selectedDay
            .day,
        1);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    final next = tester
        .widget<ProviderMonthCalendar>(find.byType(ProviderMonthCalendar));
    expect(next.month, DateTime.utc(month.year, month.month + 1, 1));
    expect(next.selectedDay.day, 1);
    expect(tester.takeException(), isNull);
  });
}
