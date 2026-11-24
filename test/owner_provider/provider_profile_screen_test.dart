import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/models/demo_data.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_profile_screen.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'support/profile_fixture.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter.ttf')))
        .load();
  });
  for (final dark in [false, true]) {
    testWidgets(
        'own profile keeps relocated settings and account actions dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final report = profileReport();
      String? selected;
      await tester.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: ProviderProfileScreen(
            provider: report.presentation,
            snapshot: report,
            onSettings: (id) => selected = id),
      ));
      await tester.pumpAndSettle();
      for (final entry in [
        ('Notifications', 'notifications'),
        ('Appearance', 'appearance'),
        ('My statistics', 'stats'),
        ('Privacy & security', 'privacy'),
        ('About & help', 'about'),
      ]) {
        await tester.scrollUntilVisible(find.text(entry.$1).hitTestable(), 240,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text(entry.$1));
        await tester.pumpAndSettle();
        expect(selected, entry.$2);
      }
      final signOut = find.text('Sign out');
      await tester.scrollUntilVisible(signOut.hitTestable(), 160,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final offset = tester.getTopLeft(signOut);
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(selected, 'about');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(selected, 'about');
      expect(tester.getTopLeft(signOut), offset);

      await tester.tap(signOut);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(selected, 'sign-out');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('top profile actions work and weekly hours still expand in place',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final report = profileReport(overrides: {
      'weekly_slots': [
        for (final hour in [6, 9, 12, 15, 18])
          {
            'weekday': 1,
            'start_time': '${hour.toString().padLeft(2, '0')}:00:00',
            'end_time': '${(hour + 2).toString().padLeft(2, '0')}:00:00',
          },
      ],
    });
    var edits = 0;
    var availability = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: ProviderProfileScreen(
        provider: report.presentation,
        snapshot: report,
        onEdit: () => edits++,
        onManageAvailability: () => availability++,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.byTooltip('Edit profile'), findsNothing);
    expect(tester.getTopLeft(find.text('Edit profile')).dy,
        lessThan(tester.getTopLeft(find.text('Service profile')).dy));
    await tester.tap(find.text('Edit profile'));
    await tester.tap(find.text('Availability'));
    expect(edits, 1);
    expect(availability, 1);
    expect(find.text('On time'), findsNothing);
    expect(find.text('1 active job · next 7 days'), findsOneWidget);
    expect(find.text('RM 55.25 / hour'), findsOneWidget);
    expect(find.text('RM 300.50 / 8 hours'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('+3 more').hitTestable(), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('18:00 – 20:00'), findsNothing);
    await tester.tap(find.text('+3 more'));
    await tester.pumpAndSettle();
    expect(find.text('18:00 – 20:00'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Show less').hitTestable(), 80,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text('18:00 – 20:00'), findsNothing);
    expect(find.text('+3 more'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shows the report-aligned two-stage match breakdown',
      (tester) async {
    final provider = DemoProvider.seeded().first.copyWith(
          score: 2 / 3,
          distanceSuitability: 1,
          ratingSuitability: 0,
          workloadSuitability: 1,
          hasRankingBreakdown: true,
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderProfileScreen(provider: provider),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Two-stage match analysis'), findsOneWidget);
    expect(find.text('Distance'), findsWidgets);
    expect(find.text('Rating'), findsWidgets);
    expect(find.text('Workload'), findsWidgets);
    expect(find.text('Availability'), findsNothing);
    expect(find.text('1/3 weight'), findsNWidgets(3));
    expect(find.text('Sign out'), findsNothing);
    expect(find.text('Appearance'), findsNothing);
  });
}
