import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/features/availability/domain/cleaning_package.dart';
import 'package:smart_rental_management/owner_provider/features/availability/domain/provider_setup.dart';
import 'package:smart_rental_management/owner_provider/widgets/provider_cleaning_packages.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_provider_setup_screen.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'support/weekly_hours_fixture.dart';

const serviceId = '11111111-1111-4111-8111-111111111111';
const service = ProviderServiceItem(
    id: '11111111-1111-4111-8111-111111111111', name: 'Standard cleaning');
const package = CleaningPackage(
    id: '22222222-2222-4222-8222-222222222222',
    providerId: '33333333-3333-4333-8333-333333333333',
    serviceTypeId: serviceId,
    durationMinutes: 180,
    cleanerCount: 1,
    totalPrice: 120,
    scope: 'Floors and bathrooms',
    enabled: true,
    revision: 1);

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'package edit validates total and passes current revision, Cancel writes nothing',
      (tester) async {
    var saves = 0, reads = 0;
    CleaningPackageDraft? submitted;
    CleaningPackage? expected;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: ProviderCleaningPackages(
                    services: const [service],
                    selectedServices: const {serviceId},
                    enabled: true,
                    load: () async {
                      reads++;
                      return [package];
                    },
                    save: (draft, base) async {
                      saves++;
                      submitted = draft;
                      expected = base;
                      return package;
                    },
                    onBusyChanged: (_) {})))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('edit-package-${package.id}')));
    await tester.pumpAndSettle();
    expect(reads, 2);
    await tester.enterText(find.byKey(const ValueKey('package-total')), '');
    await reveal(tester, find.text('Save package'));
    await tester.tap(find.text('Save package'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('Enter a valid total, e.g. 120.00.'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('package-total')), '135.50');
    await reveal(tester, find.text('Save package'));
    await tester.tap(find.text('Save package'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(submitted!.totalPrice, 135.5);
    expect(expected!.revision, 1);
    await tester.tap(find.byKey(ValueKey('edit-package-${package.id}')));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saves, 1);
  });

  testWidgets('unconfirmed save requires refresh instead of silent replay',
      (tester) async {
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: ProviderCleaningPackages(
                    services: const [service],
                    selectedServices: const {serviceId},
                    enabled: true,
                    load: () async => [package],
                    save: (draft, base) async {
                      saves++;
                      throw StateError('connection lost');
                    },
                    onBusyChanged: (_) {})))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('edit-package-${package.id}')));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Save package'));
    await tester.tap(find.text('Save package'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('Refresh packages'), findsOneWidget);
    expect(find.byKey(ValueKey('edit-package-${package.id}')), findsNothing);
    await tester.tap(find.text('Refresh packages'));
    await tester.pumpAndSettle();
    expect(saves, 1);
  });

  testWidgets('working hours can open when package endpoint fails',
      (tester) async {
    final weekly = weeklyHoursFixture(slots: const []);
    final data = ProviderSetupData(
        services: const [service],
        selectedServiceIds: const {serviceId},
        slots: const [],
        unavailableDates: const {},
        weeklyState: weekly);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: ConnectedProviderSetupScreen(
            load: () async => data,
            saveServices: (_) async {},
            loadWeeklyHours: () async => weekly,
            saveWeeklyHours: (changes, expected) async => weekly,
            addUnavailableDate: (_) async {},
            removeUnavailableDate: (_) async {},
            loadDayOffConstraints: (first, last) async =>
                ProviderDayOffConstraints(
                    firstDate: first,
                    lastDate: last,
                    confirmedDates: const {},
                    unavailableDates: const {}),
            loadPackages: () async => throw StateError('not deployed'),
            savePackage: (draft, base) async => package)));
    await tester.pumpAndSettle();
    expect(find.text('Refresh packages'), findsOneWidget);
    await tester.tap(find.text('Working hours'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('provider-weekly-hours')), findsOneWidget);
    expect(find.text('Packages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('package editor fits 320px and large text dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ProviderCleaningPackages(
                          services: const [service],
                          selectedServices: const {serviceId},
                          load: () async => [package],
                          save: (draft, base) async => package,
                          enabled: true,
                          onBusyChanged: (_) {}))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await reveal(tester, find.byKey(ValueKey('edit-package-${package.id}')));
      await tester.tap(find.byKey(ValueKey('edit-package-${package.id}')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await reveal(tester, find.text('Save package'));
      expect(tester.takeException(), isNull);
    });
  }
}
