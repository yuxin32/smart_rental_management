import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_booking_request_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_booking_repository.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_owner_repository.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'package:smart_rental_management/owner_provider/widgets/time_slot_picker.dart';

import 'support/time_slot_steps.dart';

EligibleProviderItem package({
  String id = 'package-1',
  int crew = 1,
  int minutes = 240,
  num total = 160,
}) =>
    EligibleProviderItem(
      providerId: 'provider', displayName: 'Setapak Cleaning',
      serviceArea: 'Setapak', completedJobCount: 12,
      quoteBasis: 'package', quotedAmount: total,
      // Deliberately present to ensure package quotes never display hourly pricing.
      hourlyRate: 40, dailyRate: 300,
      packageId: id, cleanerCount: crew, durationMinutes: minutes,
      packageScope: 'Floors and bathrooms',
    );

typedef Search = Future<ProviderSearchResult> Function(
    String service, DateTime start, DateTime end, int crew);

class Harness {
  final searches = <Map<String, Object>>[];
  final submissions = <Map<String, Object?>>[];
  Search? search;
  bool packageMode = true;
  bool creationAvailable = true;
  String windowStart = '09:00:00';
  String windowEnd = '17:00:00';
  DateTime now = DateTime.utc(2026, 11, 25);
  Future<BookingCreationOutcome> Function()? submit;

  Future<void> mount(WidgetTester tester,
      {double scale = 1, bool dark = false}) async {
    final screen = ConnectedBookingRequestScreen(
      now: () => now,
      initialPropertyId: 'unit',
      loadProperties: () async => [
        {
          'property_id': 'unit',
          'unit_name': 'C-301',
          'building_name': 'Lakeview',
          'property_revision': 1,
          'cleaning_window_start': windowStart,
          'cleaning_window_end': windowEnd,
          'location': {'area_name': 'Setapak'},
        }
      ],
      loadServiceTypes: () async => [
        {'service_type_id': 'standard', 'name': 'Standard cleaning'},
        {'service_type_id': 'deep', 'name': 'Deep cleaning'},
      ],
      findEligible: (
              {required propertyId,
              required serviceTypeId,
              required start,
              required end}) async =>
          throw StateError('Legacy search'),
      findMatches: (
              {required propertyId,
              required serviceTypeId,
              required start,
              required end}) async =>
          throw StateError('Legacy matches'),
      findPackageMatches: !packageMode
          ? null
          : (
              {required propertyId,
              required serviceTypeId,
              required start,
              required end,
              required cleanerCount}) async {
              searches.add({
                'property': propertyId,
                'service': serviceTypeId,
                'start': start,
                'end': end,
                'crew': cleanerCount
              });
              return await search?.call(
                      serviceTypeId, start, end, cleanerCount) ??
                  ProviderSearchResult(current: [
                    package(
                        crew: cleanerCount,
                        minutes: end.difference(start).inMinutes)
                  ], areaName: 'Setapak');
            },
      createPending: (
              {required clientRequestId,
              required providerId,
              required propertyId,
              required serviceTypeId,
              required start,
              required end,
              required expectedAmount,
              required expectedBasis,
              required instructions}) async =>
          throw StateError('Legacy creation'),
      createPackagePending: !creationAvailable
          ? null
          : (
              {required clientRequestId,
              required providerId,
              required propertyId,
              required serviceTypeId,
              required start,
              required end,
              required expectedAmount,
              required expectedBasis,
              required instructions,
              required packageId}) async {
              submissions.add({
                'token': clientRequestId,
                'provider': providerId,
                'property': propertyId,
                'service': serviceTypeId,
                'start': start,
                'end': end,
                'amount': expectedAmount,
                'basis': expectedBasis,
                'instructions': instructions,
                'package': packageId,
              });
              if (submit != null) return submit!();
              return BookingCreationOutcome(
                  bookingId: 'booking',
                  reused: false,
                  quotedAmount: expectedAmount,
                  quoteBasis: 'package',
                  quoteCurrency: 'MYR');
            },
      findCreatedBooking: (_) async => null,
    );
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<bool>(builder: (_) => screen)),
                  child: const Text('Open request')))),
    ));
    await tester.tap(find.text('Open request'));
    await tester.pumpAndSettle();
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder.hitTestable(), 150,
      scrollable: find
          .descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable))
          .first,
      maxScrolls: 40);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openForm(WidgetTester tester) =>
    tap(tester, find.text('Continue to service & time'));

Future<void> chooseDate(WidgetTester tester, {bool today = false}) async {
  await tap(tester, find.byKey(const Key('request-date')));
  await tester.tap(find.text(today ? '25' : '27').last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> chooseStart(WidgetTester tester, int minute) async {
  await tap(tester, find.byKey(const Key('request-start')));
  await chooseTimeSlot(tester, minute);
}

Future<void> chooseService(WidgetTester tester, String label) async {
  await tap(tester, find.byKey(const Key('request-service')));
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> openResults(WidgetTester tester) async {
  await openForm(tester);
  await chooseDate(tester);
  await chooseStart(tester, 540);
  await tap(tester, find.byKey(const Key('request-check-packages')));
}

void main() {
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter.ttf')))
        .load();
  });

  testWidgets(
      'compact fields share rows and service controls allowed durations',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = Harness();
    await h.mount(tester);
    await openForm(tester);
    expect(find.text('End time'), findsNothing);
    expect(tester.getTopLeft(find.text('Cleaners')).dy,
        tester.getTopLeft(find.text('Duration')).dy);
    expect(tester.getTopLeft(find.text('Date')).dy,
        tester.getTopLeft(find.text('Start time · MYT')).dy);
    for (final hour in [2, 3, 4]) {
      expect(find.byKey(ValueKey('request-duration-$hour')), findsOneWidget);
    }
    await chooseService(tester, 'Deep cleaning');
    for (final hour in [4, 6, 8]) {
      expect(find.byKey(ValueKey('request-duration-$hour')), findsOneWidget);
    }
    expect(find.byKey(const Key('request-duration-2')), findsNothing);
    await tap(tester, find.byKey(const Key('request-cleaners')));
    for (final count in [1, 2, 3, 4]) {
      expect(find.text('$count ${count == 1 ? 'cleaner' : 'cleaners'}').last,
          findsOneWidget);
    }
    await tester.tap(find.text('4 cleaners').last);
    await tester.pumpAndSettle();
    expect(find.text('4 cleaners · 4 hrs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'start boundary subtracts duration and changing duration clears invalid start',
      (tester) async {
    await Harness().mount(tester);
    await openForm(tester);
    await chooseDate(tester);
    await tap(tester, find.byKey(const Key('request-start')));
    var picker = tester.widget<TimeSlotPicker>(find.byType(TimeSlotPicker));
    expect(picker.firstMinute, 540);
    expect(picker.lastMinute, 780);
    await chooseTimeSlot(tester, 780);
    expect(find.text('Ends at 17:00'), findsOneWidget);
    await chooseService(tester, 'Deep cleaning');
    await tap(tester, find.byKey(const Key('request-duration-8')));
    expect(find.text('End time calculated automatically'), findsOneWidget);
    await tap(tester, find.byKey(const Key('request-start')));
    picker = tester.widget<TimeSlotPicker>(find.byType(TimeSlotPicker));
    expect(picker.firstMinute, 540);
    expect(picker.lastMinute, 540);
    await chooseTimeSlot(tester, 540);
    expect(find.text('Ends at 17:00'), findsOneWidget);
    await chooseService(tester, 'Standard cleaning');
    expect(find.text('Ends at 13:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a duration longer than unit window cannot search',
      (tester) async {
    final h = Harness()..windowEnd = '12:00:00';
    await h.mount(tester);
    await openForm(tester);
    await reveal(tester, find.byKey(const Key('request-check-packages')));
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('request-check-packages')))
            .onPressed,
        isNull);
    expect(find.textContaining('This duration does not fit'), findsOneWidget);
    await tap(tester, find.byKey(const Key('request-duration-3')));
    await chooseDate(tester);
    await chooseStart(tester, 540);
    await tap(tester, find.byKey(const Key('request-check-packages')));
    expect(h.searches.single['end'], DateTime.utc(2026, 11, 27, 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-day start slots exclude elapsed Malaysia times',
      (tester) async {
    final h = Harness()..now = DateTime.utc(2026, 11, 25, 2, 15);
    await h.mount(tester);
    await openForm(tester);
    await chooseDate(tester, today: true);
    await tap(tester, find.byKey(const Key('request-start')));
    final picker = tester.widget<TimeSlotPicker>(find.byType(TimeSlotPicker));
    expect(picker.firstMinute, 616);
    expect(picker.lastMinute, 780);
    await chooseTimeSlot(tester, 630);
    expect(find.text('Ends at 14:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'package submission uses total quote, exact UTC interval and crew',
      (tester) async {
    final h = Harness();
    await h.mount(tester);
    await openForm(tester);
    await tap(tester, find.byKey(const Key('request-cleaners')));
    await tester.tap(find.text('4 cleaners').last);
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('request-duration-3')));
    await chooseDate(tester);
    await chooseStart(tester, 540);
    await tap(tester, find.byKey(const Key('request-check-packages')));
    expect(h.searches.single, {
      'property': 'unit',
      'service': 'standard',
      'crew': 4,
      'start': DateTime.utc(2026, 11, 27, 1),
      'end': DateTime.utc(2026, 11, 27, 4),
    });
    await reveal(tester, find.text('Package total · RM 160.00'));
    expect(find.textContaining('/hour'), findsNothing);
    expect(find.textContaining('hourly rate'), findsNothing);
    await tap(tester, find.text('Select and review'));
    expect(find.text('4 cleaners · 3 hrs'), findsOneWidget);
    expect(find.text('Package scope: Floors and bathrooms'), findsOneWidget);
    expect(find.text('Total session price for the selected crew and duration.'),
        findsOneWidget);
    await reveal(tester, find.byKey(const Key('booking-instructions')));
    await tester.enterText(
        find.byKey(const Key('booking-instructions')), 'Use key box');
    await reveal(tester, find.byKey(const Key('booking-additional-tasks')));
    await tester.enterText(
        find.byKey(const Key('booking-additional-tasks')), 'Oven interior');
    await tap(tester, find.text('Submit Pending request'));
    final sent = h.submissions.single;
    expect(sent['amount'], 160);
    expect(sent['basis'], 'package');
    expect(sent['package'], 'package-1');
    expect(sent['provider'], 'provider');
    expect(sent['start'], h.searches.single['start']);
    expect(sent['end'], h.searches.single['end']);
    expect(sent['instructions'], contains('Use key box'));
    expect(
        sent['instructions'],
        contains(
            'Additional tasks to discuss (not included in the quote):\nOven interior'));
    expect(find.text('Open request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final changedPackage in [false, true]) {
    testWidgets(
        'alternative confirms same crew/duration and rechecks package identity changed=$changedPackage',
        (tester) async {
      final h = Harness();
      h.search = (service, start, end, crew) async {
        if (h.searches.length > 1) {
          return ProviderSearchResult(current: [
            package(
                id: changedPackage ? 'replacement' : 'package-1', total: 175),
          ]);
        }
        return ProviderSearchResult(current: [], alternatives: [
          AlternativeProviderTime(package(), start.add(const Duration(days: 1)),
              end.add(const Duration(days: 1))),
          AlternativeProviderTime(
              package(id: 'wrong-crew', crew: 2), start, end),
          AlternativeProviderTime(package(id: 'wrong-duration', minutes: 120),
              start, start.add(const Duration(hours: 2))),
        ]);
      };
      await h.mount(tester);
      await openResults(tester);
      await reveal(tester, find.text('Choose this time'));
      expect(find.text('Choose this time'), findsOneWidget);
      await tap(tester, find.text('Choose this time'));
      expect(find.text('Change appointment time?'), findsOneWidget);
      await tester.tap(find.text('Keep my time'));
      await tester.pumpAndSettle();
      expect(h.searches, hasLength(1));
      await tap(tester, find.text('Choose this time'));
      await tester.tap(find.text('Use time & review'));
      await tester.pumpAndSettle();
      expect(h.searches, hasLength(2));
      expect(h.searches.last['crew'], 1);
      expect(
          (h.searches.last['end'] as DateTime)
              .difference(h.searches.last['start'] as DateTime),
          const Duration(hours: 4));
      expect(h.searches.last['start'], DateTime.utc(2026, 11, 28, 1));
      expect(h.submissions, isEmpty);
      if (changedPackage) {
        expect(find.textContaining('That alternative is no longer available'),
            findsOneWidget);
        expect(find.text('Review your request'), findsNothing);
      } else {
        expect(find.text('Total quoted amount: RM 175.00'), findsOneWidget);
        await tap(tester, find.text('Submit Pending request'));
        expect(h.submissions.single['amount'], 175);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'changing crew after search invalidates previous package selection',
      (tester) async {
    final h = Harness();
    await h.mount(tester);
    await openResults(tester);
    await tap(tester, find.text('Choose another date & time'));
    await tap(tester, find.byKey(const Key('request-cleaners')));
    await tester.tap(find.text('2 cleaners').last);
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('request-check-packages')));
    expect(h.searches, hasLength(2));
    expect(h.searches.last['crew'], 2);
    await tap(tester, find.text('Select and review'));
    expect(find.text('2 cleaners · 4 hrs'), findsOneWidget);
    expect(h.submissions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delayed search cannot overwrite edited package details',
      (tester) async {
    final waiting = Completer<ProviderSearchResult>();
    final h = Harness()
      ..search = ((service, start, end, crew) => waiting.future);
    await h.mount(tester);
    await openForm(tester);
    await chooseDate(tester);
    await chooseStart(tester, 540);
    await reveal(tester, find.byKey(const Key('request-check-packages')));
    await tester.tap(find.byKey(const Key('request-check-packages')));
    await tester.pump();
    // Keep working while the search is pending without settling its spinner.
    await tester.ensureVisible(find.byKey(const Key('request-duration-2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('request-duration-2')));
    await tester.pump();
    waiting.complete(ProviderSearchResult(current: [package()]));
    await tester.pumpAndSettle();
    expect(find.text('Service & time'), findsOneWidget);
    expect(find.text('Ends at 11:00'), findsOneWidget);
    expect(find.text('Select and review'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed submission retries the same package request token',
      (tester) async {
    final h = Harness()..submit = (() async => throw StateError('Offline'));
    await h.mount(tester);
    await openResults(tester);
    await tap(tester, find.text('Select and review'));
    await tap(tester, find.text('Submit Pending request'));
    expect(h.submissions, hasLength(1));
    await tap(tester, find.text('Submit Pending request'));
    expect(h.submissions, hasLength(2));
    expect(h.submissions.last['token'], h.submissions.first['token']);
    expect(h.submissions.last['package'], h.submissions.first['package']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('package mode never falls back to legacy creation',
      (tester) async {
    final h = Harness()..creationAvailable = false;
    await h.mount(tester);
    await openResults(tester);
    await tap(tester, find.text('Select and review'));
    await tap(tester, find.text('Submit Pending request'));
    expect(
        find.textContaining('Package booking is unavailable.'), findsOneWidget);
    expect(h.submissions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('compact package form adapts at 320px and 200% text dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await Harness().mount(tester, scale: 2, dark: dark);
      await openForm(tester);
      await reveal(tester, find.text('Cleaners'));
      expect(tester.getTopLeft(find.text('Duration')).dy,
          greaterThan(tester.getTopLeft(find.text('Cleaners')).dy));
      await reveal(tester, find.byKey(const Key('request-date')));
      expect(tester.takeException(), isNull);
      await reveal(tester, find.byKey(const Key('package-end-summary')));
      expect(tester.takeException(), isNull);
      await reveal(tester, find.byKey(const Key('request-check-packages')));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('legacy constructor retains service and manual end controls',
      (tester) async {
    await (Harness()..packageMode = false).mount(tester);
    await chooseService(tester, 'Standard cleaning');
    await tap(tester, find.text('Continue to date & time'));
    expect(find.text('Start time'), findsOneWidget);
    expect(find.text('End time'), findsOneWidget);
    expect(find.byKey(const Key('request-cleaners')), findsNothing);
    expect(find.text('Find eligible providers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'default package service does not block leaving an untouched form',
      (tester) async {
    await Harness().mount(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open request'), findsOneWidget);
    expect(find.byType(ConnectedBookingRequestScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
