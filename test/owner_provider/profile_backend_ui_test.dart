import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_profile_screen.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_edit_profile_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/provider_profile_snapshot.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'support/profile_fixture.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter.ttf')))
        .load();
    var sdk = File(Platform.resolvedExecutable).parent;
    while (!Directory('${sdk.path}/bin/cache/artifacts/material_fonts')
        .existsSync()) {
      if (sdk.parent.path == sdk.path)
        throw StateError('Flutter fonts missing');
      sdk = sdk.parent;
    }
    for (final font in [
      ('Roboto', 'roboto-regular.ttf'),
      ('MaterialIcons', 'materialicons-regular.otf')
    ]) {
      final bytes = await File(
              '${sdk.path}/bin/cache/artifacts/material_fonts/${font.$2}')
          .readAsBytes();
      await (FontLoader(font.$1)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      for (final edit in [false, true]) {
        testWidgets(
            'original ${edit ? 'editor' : 'profile'} connected $dark scale $scale',
            (tester) async {
          tester.view.physicalSize = Size(scale == 2 ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final snapshot = profileReport();
          final boundary = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: dark ? AppTheme.dark() : AppTheme.light(),
                  builder: (ctx, child) => MediaQuery(
                      data: MediaQuery.of(ctx)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: edit
                      ? ProviderEditProfileScreen(
                          provider: snapshot.presentation,
                          snapshot: snapshot,
                          onSaveConnected: (d, b) async => snapshot,
                          onReloadConnected: () async => snapshot,
                          canEditConnected: () => true,
                          onManageAvailability: () async {})
                      : ProviderProfileScreen(
                          provider: snapshot.presentation,
                          snapshot: snapshot,
                          onEdit: () {},
                          onRefresh: () {}))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (scale == 1)
            await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await Directory('output/profile-ui').create(recursive: true);
              await File(
                      'output/profile-ui/${edit ? 'edit' : 'profile'}-${dark ? 'dark' : 'light'}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          if (edit) {
            expect(find.text('About you'), findsOneWidget);
            expect(
                tester
                    .widget<TextFormField>(
                        find.byKey(const ValueKey('profile-Hourly rate')))
                    .controller!
                    .text,
                '55.25');
            expect(
                tester
                    .widget<TextField>(find.descendant(
                        of: find.byKey(const ValueKey('profile-Email')),
                        matching: find.byType(TextField)))
                    .readOnly,
                true);
            await tester.scrollUntilVisible(find.text('Contact & privacy'), 250,
                scrollable: find.byType(Scrollable).first);
            await tester.pumpAndSettle();
            expect(find.text('Show phone to owners'), findsOneWidget);
            expect(tester.takeException(), isNull);
          } else {
            expect(find.text('Online'), findsNothing);
            expect(find.text('Pending review'), findsOneWidget);
            expect(find.text('128'), findsNothing);
            expect(find.text('96%'), findsNothing);
            await tester.scrollUntilVisible(find.text('Contact & privacy'), 200,
                scrollable: find.byType(Scrollable).first);
            await tester.pumpAndSettle();
            expect(find.text('provider@profile.invalid'), findsOneWidget);
            expect(find.text('Private starting address'), findsNothing);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
  Future<void> mountEditor(WidgetTester tester,
      {required Future<ProviderProfileSnapshot> Function(
              ProviderProfileDraft, ProviderProfileSnapshot)
          save,
      Future<ProviderProfileSnapshot> Function()? reload}) async {
    final p = profileReport();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (ctx) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(ctx).push(
                        MaterialPageRoute<void>(
                            builder: (_) => ProviderEditProfileScreen(
                                provider: p.presentation,
                                snapshot: p,
                                onSaveConnected: save,
                                onReloadConnected: reload ?? () async => p,
                                canEditConnected: () => true,
                                onManageAvailability: () async {}))),
                    child: const Text('Open editor'))))));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'save remains pending until server confirms; no preview store required',
      (tester) async {
    final wait = Completer<ProviderProfileSnapshot>();
    var calls = 0;
    ProviderProfileDraft? saved;
    await mountEditor(tester, save: (d, b) {
      calls++;
      saved = d;
      expect(b.revision, 1);
      return wait.future;
    });
    await tester.enterText(
        find.byKey(const ValueKey('profile-Display name')), 'Updated Name');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Saving...'), findsOneWidget);
    expect(find.text('Profile saved to your account'), findsNothing);
    expect(saved!.hourly, 55.25);
    expect(saved!.services, {profileService});
    expect(saved!.sharePhone, false);
    wait.complete(profileReport(
        overrides: {'revision': 2, 'full_name': 'Updated Name'}));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(find.text('Profile saved to your account'), findsOneWidget);
  });
  testWidgets(
      'conflict retains draft and requires checking server before retry',
      (tester) async {
    var calls = 0;
    await mountEditor(tester, save: (d, b) async {
      calls++;
      throw const PostgrestException(
          message: 'sensitive detail', code: '40001');
    });
    await tester.enterText(
        find.byKey(const ValueKey('profile-Display name')), 'Draft Name');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Draft Name'), findsWidgets);
    expect(find.textContaining('sensitive detail'), findsNothing);
    expect(
        find.text(
            'This profile changed elsewhere. Reload the saved profile before editing again.'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byWidgetPredicate((w) => w is FilledButton))
            .onPressed,
        isNull);
    expect(calls, 1);
    await tester.tap(find.byTooltip('Reload saved profile'));
    await tester.pumpAndSettle();
    expect(find.text('Keep editing'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('profile-Display name')))
            .controller!
            .text,
        'Test Provider');
  });
  testWidgets('validation prevents empty name and direct email edit',
      (tester) async {
    var calls = 0;
    await mountEditor(tester, save: (d, b) async {
      calls++;
      return b;
    });
    await tester.enterText(
        find.byKey(const ValueKey('profile-Display name')), '');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Display name is required'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byKey(const ValueKey('profile-Email')),
                matching: find.byType(TextField)))
            .readOnly,
        true);
  });
  testWidgets(
      'uncertain network save keeps draft and blocks duplicate until checked',
      (tester) async {
    var calls = 0;
    await mountEditor(tester, save: (d, b) async {
      calls++;
      throw TimeoutException('private transport detail');
    });
    await tester.enterText(
        find.byKey(const ValueKey('profile-Display name')), 'Network draft');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Network draft'), findsWidgets);
    expect(find.textContaining('private transport detail'), findsNothing);
    expect(find.text('Check saved profile'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byWidgetPredicate((w) => w is FilledButton))
            .onPressed,
        isNull);
    expect(find.text('Profile saved to your account'), findsNothing);
  });
}
