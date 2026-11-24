import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:smart_rental_management/owner_provider/models/demo_data.dart';
import 'package:smart_rental_management/owner_provider/models/local_preview_data.dart';
import 'package:smart_rental_management/owner_provider/screens/earnings_history_screen.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';

Future<void> selectPeriod(WidgetTester tester, String label) async {
  final option = find.text(label).first;
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('earnings summary fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: EarningsHistoryScreen(
        providerName: 'Provider A',
        bookings: LocalPreviewData.bookings(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Earnings'), findsOneWidget);
    expect(find.text('View earnings trend'), findsOneWidget);
    expect(find.textContaining('Net RM '), findsWidgets);
    expect(tester.takeException(), isNull);

    await selectPeriod(tester, 'Last 30 days');
    expect(tester.takeException(), isNull);

    await selectPeriod(tester, 'This month');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping an earning opens a persistent breakdown',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: EarningsHistoryScreen(
        providerName: 'Provider A',
        bookings: LocalPreviewData.bookings(),
      ),
    ));
    await tester.pumpAndSettle();
    await selectPeriod(tester, 'All time');

    final selectedJob = find.byKey(const ValueKey('earning-preview-006'));
    await tester.scrollUntilVisible(
      selectedJob,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(selectedJob);
    await tester.pumpAndSettle();

    expect(find.text('Earnings details'), findsOneWidget);
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isTrue);
    expect(find.text('Service amount'), findsOneWidget);
    expect(find.text('RM 160.00'), findsOneWidget);
    expect(find.text('Platform fee (15%)'), findsOneWidget);
    expect(find.text('− RM 24.00'), findsOneWidget);
    expect(find.text('Calculated earnings'), findsOneWidget);
    expect(find.text('RM 136.00'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    expect(find.text('Earnings details'), findsNothing);
  });

  testWidgets('summary, history and optional trend follow the period',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    final dates = [
      DateTime(today.year, today.month, today.day, 10),
      DateTime(today.year, today.month, today.day - 10, 10),
      DateTime(today.year, today.month, today.day - 40, 10),
    ];
    final bookings = [
      for (var i = 0; i < dates.length; i++)
        DemoBooking(
          id: 'chart-$i',
          property: 'Unit ${i + 1}',
          serviceType: 'Standard cleaning',
          providerName: 'Provider A',
          scheduledStart: dates[i],
          scheduledEnd: dates[i].add(const Duration(hours: 2)),
          status: BookingStatus.completed,
          specialInstructions: '',
          hourlyRateAtBooking: 80,
        ),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: EarningsHistoryScreen(
        providerName: 'Provider A',
        bookings: bookings,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Earnings trend'), findsNothing);
    final currentMonthRange = today.day == 1
        ? DateFormat('d MMM yyyy').format(today)
        : '1–${DateFormat('d MMM yyyy').format(today)}';
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('earnings-period-range')))
          .data,
      currentMonthRange,
    );
    await selectPeriod(tester, 'All time');
    expect(find.text('3 completed jobs  ·  avg RM 136/job'), findsOneWidget);
    expect(
      find.text('Gross RM 480  −  Platform fee RM 72'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('earnings-trend-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Earnings trend'), findsOneWidget);

    await selectPeriod(tester, 'Last 30 days');
    final last30Start = DateTime(today.year, today.month, today.day - 29);
    final rangeLabel = tester
        .widget<Text>(find.byKey(const ValueKey('earnings-period-range')))
        .data!;
    // Both endpoints must be present. A shared month may be written once,
    // e.g. 1–30 Oct 2026, when the rolling range stays within that month.
    final allowedStarts = <Matcher>[
      startsWith(DateFormat('d MMM').format(last30Start)),
      if (last30Start.year == today.year && last30Start.month == today.month)
        startsWith('${last30Start.day}–'),
    ];
    expect(
        rangeLabel,
        allOf(anyOf(allowedStarts),
            endsWith(DateFormat('d MMM yyyy').format(today))));
    expect(find.text('Weekly net earnings'), findsOneWidget);
    expect(find.text('2 completed jobs  ·  avg RM 136/job'), findsOneWidget);
    expect(
      find.text('Gross RM 320  −  Platform fee RM 48'),
      findsOneWidget,
    );
    final periodTooltips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .where((tooltip) => tooltip.message?.contains('completed') ?? false)
        .toList();
    final chartTotal = periodTooltips.fold<double>(0, (sum, tooltip) {
      final amount = RegExp(r'RM (\d+\.\d\d)').firstMatch(tooltip.message!)!;
      return sum + double.parse(amount.group(1)!);
    });
    expect(chartTotal, 272);

    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    await selectPeriod(tester, 'This month');
    final monthStart = DateTime(today.year, today.month, 1);
    final monthJobs = dates.where((date) => !date.isBefore(monthStart)).length;
    expect(find.text('Weekly net earnings'), findsOneWidget);
    expect(
      find.text(
        'Gross RM ${monthJobs * 160}  −  Platform fee RM ${monthJobs * 24}',
      ),
      findsOneWidget,
    );

    await selectPeriod(tester, 'All time');
    expect(find.text('Monthly net earnings'), findsOneWidget);
    expect(find.text('Gross RM 480  −  Platform fee RM 72'), findsOneWidget);
  });

  testWidgets('earnings row shows grouped amount on pointer hover and tap',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: EarningsHistoryScreen(
        providerName: 'Provider A',
        bookings: LocalPreviewData.bookings(),
      ),
    ));
    await tester.pumpAndSettle();
    await selectPeriod(tester, 'All time');
    await tester.tap(find.byKey(const ValueKey('earnings-trend-toggle')));
    await tester.pumpAndSettle();

    final bar = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          (widget.message?.contains('completed') ?? false) &&
          (widget.message?.contains('RM ') ?? false),
    );
    expect(bar, findsWidgets);
    await tester.ensureVisible(bar.first);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    await mouse.moveTo(tester.getCenter(bar.first));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('completed'), findsWidgets);

    await mouse.removePointer();
    await tester.pumpAndSettle();
    await tester.tap(bar.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('completed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a month row shows every completed job date', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final month = DateTime(now.year, now.month - 1, 1);
    final dates = [
      DateTime(month.year, month.month, 5, 9),
      DateTime(month.year, month.month, 18, 14),
      DateTime(month.year, month.month - 1, 20, 9),
    ];
    final bookings = [
      for (var i = 0; i < dates.length; i++)
        DemoBooking(
          id: 'month-$i',
          property: 'Unit ${i + 1}',
          serviceType: 'Standard cleaning',
          providerName: 'Provider A',
          scheduledStart: dates[i],
          scheduledEnd: dates[i].add(const Duration(hours: 2)),
          status: BookingStatus.completed,
          specialInstructions: '',
          hourlyRateAtBooking: 80,
        ),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: EarningsHistoryScreen(
        providerName: 'Provider A',
        bookings: bookings,
      ),
    ));
    await tester.pumpAndSettle();
    await selectPeriod(tester, 'All time');
    await tester.tap(find.byKey(const ValueKey('earnings-trend-toggle')));
    await tester.pumpAndSettle();

    final monthLabel = DateFormat('MMM yyyy').format(month);
    expect(find.text(monthLabel), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(ValueKey('earnings-bucket-$monthLabel')));
    await tester.tap(find.byKey(ValueKey('earnings-bucket-$monthLabel')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View jobs'));
    await tester.tap(find.text('View jobs'));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(DateFormat('MMMM yyyy').format(month))),
        findsOneWidget);
    expect(find.text('2 completed jobs · RM 272.00 earned'), findsOneWidget);
    final details = find.byType(BottomSheet);
    expect(
      find.descendant(
        of: details,
        matching: find.text(DateFormat('d MMM yyyy').format(dates[0])),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: details,
        matching: find.text(DateFormat('d MMM yyyy').format(dates[1])),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('single-job month shows history and a quiet trend state',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day, 10);
    final booking = DemoBooking(
      id: 'single-month',
      property: 'Unit A',
      serviceType: 'Standard cleaning',
      providerName: 'Provider A',
      scheduledStart: start,
      scheduledEnd: start.add(const Duration(hours: 2)),
      status: BookingStatus.completed,
      specialInstructions: '',
      hourlyRateAtBooking: 80,
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: EarningsHistoryScreen(
        providerName: 'Provider A',
        bookings: [booking],
      ),
    ));
    await tester.pumpAndSettle();
    await selectPeriod(tester, 'This month');

    expect(find.text('Earnings trend'), findsNothing);
    expect(find.byKey(const ValueKey('earning-single-month')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('earnings-trend-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Earnings trend'), findsOneWidget);
    expect(find.byKey(const ValueKey('earnings-bar-0')), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('earning-single-month')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('earning-single-month')));
    await tester.pumpAndSettle();
    expect(find.text('RM 136'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
