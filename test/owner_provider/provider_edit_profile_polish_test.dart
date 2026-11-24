import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_edit_profile_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/provider_profile_snapshot.dart';
import 'package:smart_rental_management/owner_provider/services/backend/service_location.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';

import 'support/profile_fixture.dart';

void main() {
  Future<void> reveal(WidgetTester tester, Finder target,
      {double delta = 160}) async {
    await tester.scrollUntilVisible(target.hitTestable(), delta,
        scrollable: find.byType(Scrollable).first, maxScrolls: 70);
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester,
      {bool dark = false,
      double scale = 1,
      Future<ProviderProfileSnapshot> Function(
              ProviderProfileDraft, ProviderProfileSnapshot)?
          save}) async {
    tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final report = profileReport(overrides: {
      'service_area': 'Setapak',
      'location': {
        'area_ids': ['setapak'],
        'pin_link': ''
      },
      'weekly_slots': [
        for (final hour in [6, 9, 12, 15, 18])
          {
            'weekday': 1,
            'start_time': '${hour.toString().padLeft(2, '0')}:00:00',
            'end_time': '${(hour + 2).toString().padLeft(2, '0')}:00:00',
          },
      ],
    });
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ProviderEditProfileScreen(
                provider: report.presentation,
                snapshot: report,
                canEditConnected: () => true,
                onSaveConnected: save ?? (d, b) async => b,
                onReloadConnected: () async => report,
                onManageAvailability: () async {},
                loadServiceAreas: () async => const [
                  ServiceAreaOption('setapak', 'Setapak'),
                  ServiceAreaOption('wangsa', 'Wangsa Maju'),
                ],
              ),
            )),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  testWidgets('fixed save, discard guard and expanded hours preserve the draft',
      (tester) async {
    ProviderProfileDraft? saved;
    await mount(tester, save: (draft, baseline) async {
      saved = draft;
      return baseline;
    });
    final saveButton =
        find.byWidgetPredicate((widget) => widget is FilledButton);
    final saveY = tester.getCenter(saveButton).dy;
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    expect(find.text('YOUR PROVIDER PROFILE'), findsNothing);
    expect(find.text('Avatar colour'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('profile-Display name')), 'Updated Provider');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await reveal(tester, find.text('+3 more'));
    await tester.tap(find.text('+3 more'));
    await tester.pumpAndSettle();
    expect(find.text('18:00 – 20:00'), findsOneWidget);
    await reveal(tester, find.text('Show less'));
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text('18:00 – 20:00'), findsNothing);
    expect(tester.getCenter(saveButton).dy, saveY);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('profile-Display name')))
            .controller!
            .text,
        'Updated Provider');
    await reveal(tester, find.byKey(const ValueKey('profile-Hourly rate')),
        delta: -160);
    await tester.enterText(
        find.byKey(const ValueKey('profile-Hourly rate')), '65.00');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Wangsa Maju'));
    await tester.tap(find.text('Wangsa Maju'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(saveButton).dy, saveY);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.name, 'Updated Provider');
    expect(saved!.hourly, 65);
    expect(saved!.daily, 300.50);
    expect(saved!.coverageAreaIds, {'setapak', 'wangsa'});
    expect(saved!.origin, 'Private starting address');
    expect(saved!.services, {profileService});
    expect(find.text('Open editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('new groups and loaded coverage fit 200% text dark=$dark',
        (tester) async {
      await mount(tester, dark: dark, scale: 2);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Avatar color 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      for (final label in [
        'Services & rates',
        'Service coverage',
        'Private starting address',
        'Working hours',
        'Contact & privacy',
      ]) {
        await reveal(tester, find.text(label).first);
        expect(tester.takeException(), isNull);
      }
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: find.byKey(const ValueKey('profile-Email')),
                  matching: find.byType(TextField)))
              .readOnly,
          true);
      expect(find.text('Save changes').hitTestable(), findsOneWidget);
    });
  }
}
