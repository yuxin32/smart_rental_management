import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_booking_request_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/service_location.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_owner_repository.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_booking_repository.dart';
import 'package:smart_rental_management/owner_provider/widgets/service_location_fields.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'support/time_slot_steps.dart';

const later = EligibleProviderItem(
    providerId: 'p-later',
    displayName: 'Lina Cleaning',
    serviceArea: 'Setapak',
    completedJobCount: 12,
    quoteBasis: 'hourly',
    quotedAmount: 120,
    hourlyRate: 40,
    distanceKm: 2.4);
const repriced = EligibleProviderItem(
    providerId: 'p-later',
    displayName: 'Lina Cleaning',
    serviceArea: 'Setapak',
    completedJobCount: 12,
    quoteBasis: 'hourly',
    quotedAmount: 135,
    hourlyRate: 45,
    distanceKm: 2.4);

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder.hitTestable(), 180,
      scrollable: find
          .descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable))
          .first,
      maxScrolls: 35);
  await tester.pumpAndSettle();
}

Future<void> openResults(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('request-unit')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('C-301, Lakeview').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('request-service')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Deep cleaning').last);
  await tester.pumpAndSettle();
  await reveal(tester, find.text('Continue to date & time'));
  await tester.tap(find.text('Continue to date & time'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select service date'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Next month'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('15').last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select time').first);
  await tester.pumpAndSettle();
  await chooseTimeSlot(tester, 540);
  await tester.tap(find.text('Select time').last);
  await tester.pumpAndSettle();
  await chooseTimeSlot(tester, 720);
  await reveal(tester, find.text('Find eligible providers'));
  await tester.tap(find.text('Find eligible providers'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter.ttf')))
        .load();
  });
  test(
      'map pin parsing accepts selected points, rejects viewports/short links/invalid coordinates',
      () {
    expect(validateMapPin(''), isNull);
    expect(validateMapPin('https://maps.google.com/?q=3.139,101.687'), isNull);
    expect(
        validateMapPin(
            'https://www.google.com/maps/place/Example/data=!3d3.139!4d101.687'),
        isNull);
    expect(validateMapPin('https://www.google.com/maps/@3.139,101.687,15z'),
        isNotNull);
    expect(validateMapPin('https://maps.app.goo.gl/example'), isNotNull);
    expect(validateMapPin('https://evil.invalid/?q=3.139,101.687'), isNotNull);
    expect(validateMapPin('https://maps.google.com/?q=91,101'), isNotNull);
  });
  for (final expired in [false, true]) {
    testWidgets(
        'alternative confirmation rechecks availability and quote expired=$expired',
        (tester) async {
      var searches = 0, submissions = 0;
      final starts = <DateTime>[];
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<bool>(
                              builder: (_) => ConnectedBookingRequestScreen(
                                  now: () => DateTime.utc(2026, 10, 29),
                                  loadProperties: () async => [
                                        {
                                          'property_id': 'unit',
                                          'unit_name': 'C-301',
                                          'building_name': 'Lakeview',
                                          'property_revision': 1,
                                          'cleaning_window_start': '08:00:00',
                                          'cleaning_window_end': '18:00:00',
                                          'location': {
                                            'area_id': 'my-kl-setapak',
                                            'area_name': 'Setapak, Kuala Lumpur'
                                          }
                                        }
                                      ],
                                  loadServiceTypes: () async => [
                                        {
                                          'service_type_id': 'deep',
                                          'name': 'Deep cleaning'
                                        }
                                      ],
                                  findEligible: (
                                          {required propertyId,
                                          required serviceTypeId,
                                          required start,
                                          required end}) async =>
                                      throw StateError(
                                          'Old search must not be used'),
                                  findMatches: (
                                      {required propertyId,
                                      required serviceTypeId,
                                      required start,
                                      required end}) async {
                                    starts.add(start);
                                    searches++;
                                    if (searches == 1)
                                      return ProviderSearchResult(
                                          current: const [],
                                          areaName: 'Setapak, Kuala Lumpur',
                                          alternatives: [
                                            AlternativeProviderTime(
                                                later,
                                                start.add(
                                                    const Duration(hours: 5)),
                                                end.add(
                                                    const Duration(hours: 5)))
                                          ]);
                                    return ProviderSearchResult(
                                        current: expired
                                            ? const []
                                            : const [repriced],
                                        areaName: 'Setapak, Kuala Lumpur');
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
                                      required instructions}) async {
                                    submissions++;
                                    expect(providerId, 'p-later');
                                    expect(expectedAmount, 135);
                                    expect(start.hour, 6);
                                    expect(end.hour, 9);
                                    return const BookingCreationOutcome(
                                        bookingId: 'booking',
                                        reused: false,
                                        quotedAmount: 135,
                                        quoteBasis: 'hourly',
                                        quoteCurrency: 'MYR');
                                  },
                                  findCreatedBooking: (_) async => null))),
                      child: const Text('Open request'))))));
      await tester.tap(find.text('Open request'));
      await tester.pumpAndSettle();
      await openResults(tester);
      expect(searches, 1);
      await reveal(tester, find.text('Other available times'));
      expect(find.text('Other available times'), findsOneWidget);
      expect(find.text('Change time required'), findsOneWidget);
      await reveal(tester, find.text('Use this time'));
      await tester.tap(find.text('Use this time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep my time'));
      await tester.pumpAndSettle();
      expect(searches, 1);
      expect(submissions, 0);
      await reveal(tester, find.text('Use this time'));
      await tester.tap(find.text('Use this time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change time & continue'));
      await tester.pumpAndSettle();
      expect(searches, 2);
      expect(submissions, 0);
      expect(starts.last.difference(starts.first), const Duration(hours: 5));
      if (expired) {
        expect(find.textContaining('That alternative is no longer available'),
            findsOneWidget);
        expect(find.text('Submit Pending request'), findsNothing);
      } else {
        await reveal(tester, find.text('Review your request'));
        expect(find.text('Review your request'), findsOneWidget);
        expect(find.textContaining('Total quoted amount: RM 135.00'),
            findsOneWidget);
        await reveal(tester, find.text('Submit Pending request'));
        await tester.tap(find.text('Submit Pending request'));
        await tester.pumpAndSettle();
        expect(submissions, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets('coverage fields wrap at 320px and 200% text dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pin = TextEditingController();
      addTearDown(pin.dispose);
      var selected = <String>{};
      await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(2)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: StatefulBuilder(
                      builder: (c, setState) => Form(
                          child: ServiceLocationFields(
                              loadAreas: () async => const [
                                    ServiceAreaOption('my-kl', 'Kuala Lumpur'),
                                    ServiceAreaOption('my-kl-wangsa-maju',
                                        'Wangsa Maju, Kuala Lumpur')
                                  ],
                              selected: selected,
                              onChanged: (v) => setState(() => selected = v),
                              multiple: true,
                              pinController: pin)))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Wangsa Maju, Kuala Lumpur'));
      await tester.tap(find.text('Wangsa Maju, Kuala Lumpur'));
      await tester.pumpAndSettle();
      expect(selected, contains('my-kl-wangsa-maju'));
      expect(tester.takeException(), isNull);
    });
  }
}
