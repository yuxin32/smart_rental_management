import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'package:smart_rental_management/owner_provider/widgets/provider_working_hours_summary.dart';

Map<String, dynamic> slot(int day, String start, String end) =>
    {'weekday': day, 'start_time': start, 'end_time': end};

void main() {
  Future<void> mount(WidgetTester tester, List<Map<String, dynamic>> slots,
      {bool dark = false, double scale = 1}) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ProviderWorkingHoursSummary(slots: slots),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sorts and groups days, expands and collapses only that day',
      (tester) async {
    final slots = [
      slot(2, '08:00:00', '10:00:00'),
      slot(1, '18:00:00', '20:00:00'),
      slot(1, '09:00:00', '11:00:00'),
      slot(1, '15:00:00', '17:00:00'),
      slot(2, '14:00:00', '16:00:00'),
      slot(1, '06:00:00', '08:00:00'),
      slot(1, '12:00:00', '14:00:00'),
    ];
    await mount(tester, slots);
    final monday = find.byKey(const ValueKey(1));
    final tuesday = find.byKey(const ValueKey(2));
    Finder inDay(Finder day, String text) =>
        find.descendant(of: day, matching: find.text(text));
    expect(inDay(monday, '06:00 – 08:00'), findsOneWidget);
    expect(inDay(monday, '09:00 – 11:00'), findsOneWidget);
    expect(find.text('12:00 – 14:00'), findsNothing);
    expect(find.descendant(of: tuesday, matching: find.byType(TextButton)),
        findsNothing);
    expect(
        tester.getTopLeft(monday).dy, lessThan(tester.getTopLeft(tuesday).dy));
    await tester.tap(find.text('+3 more'));
    await tester.pumpAndSettle();
    expect(inDay(monday, '18:00 – 20:00'), findsOneWidget);
    expect(tester.getTopLeft(find.text('12:00 – 14:00')).dy,
        lessThan(tester.getTopLeft(find.text('15:00 – 17:00')).dy));
    expect(inDay(tuesday, '14:00 – 16:00'), findsOneWidget);
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text('12:00 – 14:00'), findsNothing);
    expect(find.text('+3 more'), findsOneWidget);
    expect(find.text('Not working'), findsNWidgets(5));
    expect(find.byType(Divider), findsNWidgets(7));
    expect(slots.first['weekday'], 2); // Rendering must not reorder input.
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'no expand action for one or exactly two slots; empty stays clear',
      (tester) async {
    await mount(tester, [
      slot(1, '08:00', '12:00'),
      slot(1, '14:00', '18:00'),
      slot(3, '09:00', '13:00'),
    ]);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('Wednesday'), findsOneWidget);
    await mount(tester, []);
    expect(find.text('No working slots saved yet.'), findsOneWidget);
    expect(find.text('Not working'), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('expanded hours fit narrow screen at 200% text dark=$dark',
        (tester) async {
      await mount(
          tester,
          [
            slot(1, '06:00', '08:00'),
            slot(1, '09:00', '11:00'),
            slot(1, '12:00', '14:00'),
            slot(1, '15:00', '17:00'),
            slot(3, '08:00', '18:00'),
          ],
          dark: dark,
          scale: 2);
      await tester.ensureVisible(find.text('+2 more'));
      await tester.tap(find.text('+2 more'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('15:00 – 17:00'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Sunday'), 200);
      expect(tester.takeException(), isNull);
    });
  }
}
