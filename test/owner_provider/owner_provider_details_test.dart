import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/screens/owner_records_view.dart';
import 'package:smart_rental_management/owner_provider/screens/owner_workspace_dashboard.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'package:smart_rental_management/owner_provider/widgets/owner_workspace_navigation.dart';

Map<String, dynamic> profile() => {
  'provider_id': 'provider',
  'full_name': 'Setapak Cleaning',
  'service_area': 'Kuala Lumpur',
  'bio': 'Original provider introduction.',
  'hourly_rate': 40,
  'daily_rate': 280,
  'rating_average': 5.0,
  'completed_job_count': 0,
  'services': [
    {
      'name': 'Deep cleaning',
      'description': 'Detailed cleaning of a rental unit.',
    },
    {
      'name': 'Standard cleaning',
      'description': 'Routine cleaning of a rental unit.',
    },
  ],
};

void main() {
  Widget app(
    Map<String, dynamic> row, {
    bool dark = false,
    double scale = 1,
    Future<void> Function()? request,
  }) => MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    initialRoute: '/details',
    routes: {
      '/': (_) => const Scaffold(body: Text('Provider directory')),
      '/details': (_) => OwnerDestinationFrame(
        activeId: 'browse',
        onChange: (_) async {},
        child: OwnerProviderDetails(row: row, onRequestCleaning: request),
      ),
    },
  );

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'public profile preserves data, bottom menu and request at 320px dark=$dark scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final gate = Completer<void>();
          var opens = 0;
          await tester.pumpWidget(
            app(
              profile(),
              dark: dark,
              scale: scale,
              request: () {
                opens++;
                return gate.future;
              },
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Setapak Cleaning'), findsOneWidget);
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          expect(find.byType(OwnerWorkspaceNav), findsOneWidget);
          final request = find.widgetWithText(FilledButton, 'Request cleaning');
          expect(request.hitTestable(), findsOneWidget);
          expect(find.text('Original provider introduction.'), findsNothing);
          final scroll = find.byType(Scrollable).first;
          for (final label in [
            'Hourly',
            'RM 40',
            '8-hour day',
            'RM 280',
            'Deep cleaning',
            'Routine cleaning of a rental unit.',
          ]) {
            await tester.scrollUntilVisible(
              find.text(label),
              100,
              scrollable: scroll,
              maxScrolls: 40,
            );
            expect(find.text(label), findsOneWidget);
          }
          await tester.scrollUntilVisible(
            find.text('About this provider'),
            100,
            scrollable: scroll,
            maxScrolls: 40,
          );
          await tester.tap(find.text('About this provider'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Original provider introduction.'),
            100,
            scrollable: scroll,
          );
          expect(find.text('Original provider introduction.'), findsOneWidget);
          expect(find.text('Edit profile'), findsNothing);
          expect(find.text('Working hours'), findsNothing);
          expect(
            find.text(
              'This profile shows the latest information loaded in the directory.',
            ),
            findsNothing,
          );
          await tester.tap(request);
          await tester.pump();
          expect(opens, 1);
          expect(tester.widget<FilledButton>(request).onPressed, isNull);
          await tester.tap(request);
          await tester.pump();
          expect(opens, 1);
          gate.complete();
          await tester.pumpAndSettle();
          expect(tester.widget<FilledButton>(request).onPressed, isNotNull);
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Provider directory'), findsOneWidget);
        },
      );
    }
  }
  testWidgets(
    'single rate and missing public details never invent prices or ratings',
    (tester) async {
      final row = profile()
        ..['daily_rate'] = null
        ..['hourly_rate'] = 55.25
        ..['rating_average'] = null
        ..['bio'] = ''
        ..['services'] = [];
      await tester.pumpWidget(app(row, request: () async {}));
      await tester.pumpAndSettle();
      expect(find.text('RM 55.25'), findsOneWidget);
      expect(find.text('8-hour day'), findsNothing);
      expect(find.text('No ratings yet'), findsOneWidget);
      expect(find.text('About this provider'), findsNothing);
      expect(find.text('No services listed yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed request navigation is retryable and hides exception data',
    (tester) async {
      await tester.pumpWidget(
        app(
          profile(),
          request: () async => throw StateError('PRIVATE DETAILS'),
        ),
      );
      await tester.pumpAndSettle();
      final request = find.widgetWithText(FilledButton, 'Request cleaning');
      await tester.tap(request);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not open your cleaning request. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE DETAILS'), findsNothing);
      expect(tester.widget<FilledButton>(request).onPressed, isNotNull);
    },
  );
}
