import 'support/weekly_hours_fixture.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/features/availability/domain/provider_setup.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_provider_setup_screen.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';

Future<void> mount(
  WidgetTester tester, {
  required Future<ProviderDayOffConstraints> Function(DateTime, DateTime) load,
  required Future<void> Function(String) save,
  bool dark = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: ConnectedProviderSetupScreen(
        load: () async => const ProviderSetupData(
            services: [],
            selectedServiceIds: {},
            slots: [],
            unavailableDates: {}),
        loadDayOffConstraints: load,
        saveServices: (_) async {},
        loadWeeklyHours: () async => weeklyHoursFixture(),
        saveWeeklyHours: (days, expected) async {
          return expected;
        },
        addUnavailableDate: save,
        removeUnavailableDate: (_) async {},
      )));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Add day off'), 300,
      maxScrolls: 40, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

ProviderDayOffConstraints dates(DateTime first, DateTime last,
        {Set<String> booked = const {}, Set<String> blocked = const {}}) =>
    ProviderDayOffConstraints(
        firstDate: first,
        lastDate: last,
        confirmedDates: booked,
        unavailableDates: blocked);
Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('Add day off'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'confirmed dates are disabled before any write and next free date is initially selected',
      (tester) async {
    final saved = <String>[];
    var reads = 0;
    late DateTime first, second, third;
    await mount(tester,
        load: (start, end) async {
          reads++;
          first = start;
          second = DateTime(start.year, start.month, start.day + 1);
          third = DateTime(start.year, start.month, start.day + 2);
          return dates(start, end,
              booked: {ProviderDayOffConstraints.dateKey(first)},
              blocked: {ProviderDayOffConstraints.dateKey(second)});
        },
        save: (day) async => saved.add(day));
    await open(tester);
    final calendar =
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    expect(calendar.selectableDayPredicate!(first), isFalse);
    expect(calendar.selectableDayPredicate!(second), isFalse);
    expect(calendar.selectableDayPredicate!(third), isTrue);
    expect(calendar.initialDate, third);
    expect(reads, 1);
    expect(saved, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(saved, [ProviderDayOffConstraints.dateKey(third)]);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'failed fresh check provides retry instead of an unrestricted calendar',
      (tester) async {
    var reads = 0, writes = 0;
    await mount(tester, load: (first, last) async {
      if (++reads == 1) throw StateError('offline');
      return dates(first, last);
    }, save: (_) async {
      writes++;
    });
    await open(tester);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('Could not check dates'), findsOneWidget);
    expect(writes, 0);
    await tester.tap(find.text('Check dates again'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(writes, 0);
  });
  testWidgets('manual date entry also rejects a confirmed date before saving',
      (tester) async {
    late DateTime protected;
    var writes = 0;
    await mount(tester, load: (first, last) async {
      protected = first;
      return dates(first, last,
          booked: {ProviderDayOffConstraints.dateKey(first)});
    }, save: (_) async {
      writes++;
    });
    await open(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final input = find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.byType(TextFormField));
    await tester.enterText(
        input, '${protected.month}/${protected.day}/${protected.year}');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(
        find.text(
            'Choose a date without a confirmed job or an existing day off.'),
        findsOneWidget);
    expect(writes, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
  testWidgets(
      'calendar cannot open while verification is pending; cancelling does not write',
      (tester) async {
    final pending = Completer<ProviderDayOffConstraints>();
    late DateTime first, last;
    var reads = 0, writes = 0;
    await mount(tester, load: (start, end) {
      reads++;
      first = start;
      last = end;
      return pending.future;
    }, save: (_) async {
      writes++;
    });
    await tester.tap(find.text('Add day off'));
    await tester.pump();
    expect(find.text('Checking dates…'), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(find
                .ancestor(
                    of: find.text('Checking dates…'),
                    matching: find.byWidgetPredicate(
                        (widget) => widget is OutlinedButton))
                .first)
            .onPressed,
        isNull);
    pending.complete(dates(first, last));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(reads, 1);
  });
  testWidgets('no valid date never opens an invalid picker', (tester) async {
    var writes = 0;
    await mount(tester, load: (first, last) async {
      final blocked = <String>{};
      for (var day = first;
          !day.isAfter(last);
          day = DateTime(day.year, day.month, day.day + 1)) {
        blocked.add(ProviderDayOffConstraints.dateKey(day));
      }
      return dates(first, last, blocked: blocked);
    }, save: (_) async {
      writes++;
    });
    await open(tester);
    expect(find.text('No dates available'), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'new booking between opening and saving is still refused by the backend',
      (tester) async {
    var reads = 0, writes = 0;
    await mount(tester, load: (first, last) async {
      reads++;
      return dates(first, last);
    }, save: (_) async {
      writes++;
      throw StateError('confirmed booking');
    });
    await open(tester);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Change not saved'), findsOneWidget);
    expect(writes, 1);
    await tester.scrollUntilVisible(find.text('Add day off'), 300,
        maxScrolls: 40,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await open(tester);
    expect(reads, 2);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
  for (final dark in [false, true]) {
    testWidgets(
        'date picker fits a narrow phone at 200% text (${dark ? 'dark' : 'light'})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester,
          dark: dark,
          scale: 2,
          load: (first, last) async => dates(first, last),
          save: (_) async {});
      await open(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(find.text('OK').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  }
}
