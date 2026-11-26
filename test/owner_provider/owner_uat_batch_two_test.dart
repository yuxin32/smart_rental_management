import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/models/demo_data.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_booking_history_sheet.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_property_form_screen.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_workspace_screen.dart';
import 'package:smart_rental_management/owner_provider/screens/property_list_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_backend_provider.dart';
import 'package:smart_rental_management/owner_provider/services/user_session.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'package:smart_rental_management/owner_provider/widgets/bedroom_count_field.dart';
import 'package:smart_rental_management/owner_provider/widgets/booking_activity_tile.dart';
import 'package:smart_rental_management/owner_provider/widgets/connected_workspace_components.dart';
import 'support/owner_uat_steps.dart';

const booking = {
  'booking_id': '11111111-1111-4111-8111-111111111111',
  'owner_id': 'owner',
  'provider_id': 'provider',
  'current_status': 'Accepted',
  'unit_name': 'Unit A-12',
  'building_name': 'Menara Suria',
  'service_name': 'Standard cleaning',
  'quoted_amount': 120,
  'requested_start_at': '2026-11-01T02:00:00Z',
  'requested_end_at': '2026-11-01T05:00:00Z',
};
Widget app(Widget home, {bool dark = false, double scale = 1}) => MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: home);
void phone(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('output/owner-uat-batch-two-ui').create(recursive: true);
    await File('output/owner-uat-batch-two-ui/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter.ttf')))
        .load();
    var sdk = File(Platform.resolvedExecutable).parent;
    while (!Directory('${sdk.path}/bin/cache/artifacts/material_fonts')
        .existsSync()) {
      final parent = sdk.parent;
      if (parent.path == sdk.path)
        throw StateError('Flutter fonts unavailable');
      sdk = parent;
    }
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf'
    }.entries) {
      await (FontLoader(entry.key)
            ..addFont(Future.value(ByteData.sublistView(await File(
                    '${sdk.path}/bin/cache/artifacts/material_fonts/${entry.value}')
                .readAsBytes()))))
          .load();
    }
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets(
      'bedroom choice validates common and custom counts without silent defaults',
      (tester) async {
    final value = TextEditingController();
    final form = GlobalKey<FormState>();
    int? saved;
    await tester.pumpWidget(app(Scaffold(
        body: Form(
            key: form,
            child: SingleChildScrollView(
                child: Column(children: [
              BedroomCountField(controller: value),
              FilledButton(
                  onPressed: () {
                    if (form.currentState!.validate())
                      saved = int.parse(value.text);
                  },
                  child: const Text('Save')),
            ]))))));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(value.text, isEmpty);
    expect(find.text('Select the number of bedrooms'), findsOneWidget);
    await chooseBedrooms(tester, 3);
    await tester.tap(find.text('Save'));
    expect(saved, 3);
    await chooseBedrooms(tester, 8);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 8);
    final other = find.byKey(const Key('property-bedrooms-other'));
    for (final bad in ['0', '101', '']) {
      await tester.enterText(other, bad);
      saved = null;
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Enter a number from 7 to 100'), findsOneWidget);
    }
    await chooseBedrooms(tester, 6);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    expect(saved, 6);
    expect(find.byKey(const Key('property-bedrooms-other')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    value.dispose();
  });

  testWidgets('editing a larger property preserves its exact bedroom count',
      (tester) async {
    phone(tester);
    ConnectedPropertyInput? saved;
    final p = DemoProperty(
        id: 'property',
        unit: 'A-12',
        tower: 'Building',
        address: 'Address',
        bedrooms: 42,
        sizeSqft: 980,
        cleaningWindowStart: const TimeOfDay(hour: 8, minute: 0),
        cleaningWindowEnd: const TimeOfDay(hour: 18, minute: 0));
    await tester.pumpWidget(app(ConnectedPropertyFormScreen(
        initial: p, onSave: (v) async => saved = v)));
    final other = find.byKey(const Key('property-bedrooms-other'));
    await tester.ensureVisible(other);
    expect(tester.widget<TextFormField>(other).controller!.text, '42');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved!.bedrooms, 42);
    expect(saved!.unitName, 'A-12');
  });

  testWidgets(
      'new property examples are guidance and are never prefilled values',
      (tester) async {
    var writes = 0;
    await tester.pumpWidget(
        app(ConnectedPropertyFormScreen(onSave: (_) async => writes++)));
    for (final hint in [
      'e.g. A-101 or 12-05',
      'e.g. Menara Suria, Tower A',
      'e.g. 12 Jalan Example, Kuala Lumpur',
      'e.g. 980'
    ]) {
      final field = tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, hint));
      expect(field.controller!.text, isEmpty);
    }
    await tester.tap(find.text('Add property'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Unit / apartment number is required'), findsOneWidget);
    expect(find.text('Select the number of bedrooms'), findsOneWidget);
  });

  testWidgets('My properties has one Add entry in its top app bar',
      (tester) async {
    var opens = 0;
    await tester.pumpWidget(app(PropertyListScreen(
        bookings: const [],
        connectedProperties: const [],
        totalCount: 0,
        connectedCounts: const {},
        onAddConnected: () => opens++)));
    expect(find.byTooltip('Add property'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    expect(
        find.ancestor(
            of: find.byTooltip('Add property'), matching: find.byType(AppBar)),
        findsOneWidget);
    await tester.tap(find.byTooltip('Add property'));
    expect(opens, 1);
  });

  for (final role in [UserRole.owner, UserRole.provider]) {
    for (final state in ['loading', 'ready', 'error']) {
      testWidgets(
          'booking details has Back and Refresh, no Logout role=$role state=$state',
          (tester) async {
        phone(tester);
        final hold = Completer<void>();
        final client = (await tester.runAsync(() async => SupabaseClient(
                'https://fixture.invalid', 'sb_publishable_fixture',
                authOptions: const AuthClientOptions(autoRefreshToken: false),
                httpClient: MockClient((r) async {
              if (state == 'loading') await hold.future;
              return http.Response(
                  jsonEncode(state == 'error'
                      ? {'message': 'PRIVATE FAILURE'}
                      : [booking]),
                  state == 'error' ? 503 : 200,
                  request: r,
                  headers: {'content-type': 'application/json'});
            }))))!;
        addTearDown(() => tester.runAsync(client.dispose));
        final backend = SupabaseBackendProvider(client);
        await tester.pumpWidget(app(Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ConnectedWorkspaceScreen(
                                backend: backend,
                                role: role,
                                bookingId: booking['booking_id'] as String))),
                    child: const Text('Open'))))));
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (state != 'loading') await tester.pumpAndSettle();
        expect(find.byTooltip('Sign out'), findsNothing);
        expect(find.byIcon(Icons.logout), findsNothing);
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.byTooltip('Refresh'), findsOneWidget);
        expect(find.textContaining('PRIVATE FAILURE'), findsNothing);
        if (!hold.isCompleted) hold.complete();
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }

  for (final provider in [false, true]) {
    for (final status in [
      'Pending',
      'Accepted',
      'In Progress',
      'Completed',
      'Cancelled',
      'Declined'
    ]) {
      testWidgets(
          'activity/cancel buttons retain status rules provider=$provider status=$status 320px/200%',
          (tester) async {
        phone(tester, width: 320, height: 568);
        int activity = 0, cancel = 0;
        await tester.pumpWidget(app(
            Scaffold(
                body: SingleChildScrollView(
                    child: ConnectedBookingCard(
                        row: {...booking, 'current_status': status},
                        now: status == 'Pending'
                            ? () => DateTime.utc(2026, 10, 31)
                            : null,
                        isProvider: provider,
                        busy: false,
                        propertyName: 'Unit A-12, Menara Suria',
                        onAction: (_) {},
                        onHistory: () => activity++,
                        onMessages: () {},
                        onEvidence: () {},
                        onReview: () {},
                        onCancel: () => cancel++))),
            dark: provider,
            scale: 2));
        final activityButton = find.ancestor(
            of: find.text('Status history'),
            matching: find.byWidgetPredicate((w) => w is TextButton));
        await tester.ensureVisible(activityButton);
        await tester.tap(activityButton);
        await tester.pumpAndSettle();
        expect(activity, 1);
        expect(cancel, 0);
        final canCancel = provider
            ? status == 'Accepted'
            : ['Pending', 'Accepted'].contains(status);
        final cancelButton = find.ancestor(
            of: find.text('Cancel booking'),
            matching: find.byWidgetPredicate((w) => w is OutlinedButton));
        expect(cancelButton, canCancel ? findsOneWidget : findsNothing);
        if (canCancel) {
          await tester.ensureVisible(cancelButton);
          expect(tester.getSize(cancelButton).height, greaterThanOrEqualTo(48));
          await tester.tap(cancelButton);
          expect(cancel, 1);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('busy cancellation cannot dispatch a second operation',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: ConnectedBookingCard(
                row: booking,
                isProvider: false,
                busy: true,
                onAction: (_) {},
                onHistory: () {},
                onMessages: () {},
                onEvidence: () {},
                onReview: () {},
                onCancel: () => calls++)))));
    final button = find.ancestor(
        of: find.text('Cancel booking'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton));
    await tester.ensureVisible(button);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(calls, 0);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'actual activity events remain readable and cancelled branch adds no completion dark=$dark',
        (tester) async {
      phone(tester);
      final boundary = GlobalKey();
      final events = [
        {
          'new_status': 'Pending',
          'previous_status': null,
          'changed_at': '2026-10-26T01:00:00Z'
        },
        {
          'new_status': 'Cancelled',
          'previous_status': 'Accepted',
          'changed_at': '2026-10-26T03:00:00Z',
          'change_reason':
              'The rental unit is no longer available for this appointment.'
        },
        {
          'new_status': 'Accepted',
          'previous_status': 'Pending',
          'changed_at': '2026-10-26T02:00:00Z'
        },
      ];
      await tester.pumpWidget(app(
          RepaintBoundary(
              key: boundary,
              child: Scaffold(
                  body: ConnectedBookingHistorySheet(
                      bookingId: 'booking', load: (_) async => events))),
          dark: dark));
      await tester.pumpAndSettle();
      expect(find.text('Booking cancelled'), findsOneWidget);
      expect(find.text('Cleaning completed'), findsNothing);
      expect(find.text('Latest update'), findsOneWidget);
      final tiles = tester
          .widgetList<BookingActivityTile>(find.byType(BookingActivityTile))
          .toList();
      expect(tiles.first.event['new_status'], 'Cancelled');
      expect(find.text('Reason'), findsOneWidget);
      expect(find.textContaining('→'), findsNothing);
      await capture(tester, boundary, 'activity-${dark ? 'dark' : 'light'}');
    });

    testWidgets(
        'property hints and bedroom dropdown render at phone size dark=$dark',
        (tester) async {
      phone(tester);
      final boundary = GlobalKey();
      await tester.pumpWidget(app(
          RepaintBoundary(
              key: boundary,
              child: ConnectedPropertyFormScreen(onSave: (_) async {})),
          dark: dark));
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'property-${dark ? 'dark' : 'light'}');
      await chooseBedrooms(tester, 8);
      expect(find.byKey(const Key('property-bedrooms-other')), findsOneWidget);
      await capture(
          tester, boundary, 'bedrooms-other-${dark ? 'dark' : 'light'}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'status history has one drag handle and closes without changing the booking',
      (tester) async {
    await tester.pumpWidget(app(Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ConnectedBookingHistorySheet(
                        bookingId: 'booking', load: (_) async => const [])),
                child: const Text('Open activity'))))));
    await tester.tap(find.text('Open activity'));
    await tester.pumpAndSettle();
    final bars = find
        .descendant(
            of: find.byType(BottomSheet), matching: find.byType(DecoratedBox))
        .evaluate()
        .where((element) {
      final size = tester.getSize(find.byWidget(element.widget));
      return size.height > 0 &&
          size.height <= 6 &&
          size.width >= 24 &&
          size.width <= 48;
    });
    expect(bars.length, 1);
    expect(find.byTooltip('Close status history'), findsOneWidget);
    await tester.tap(find.byTooltip('Close status history'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectedBookingHistorySheet), findsNothing);
  });
}
