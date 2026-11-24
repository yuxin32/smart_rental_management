import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_rental_management/owner_provider/screens/onboarding_screen.dart';
import 'package:smart_rental_management/owner_provider/services/user_session.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'package:smart_rental_management/owner_provider/widgets/coach_mark.dart';

const _guideId = 'interaction-regression';
const _firstTitle = 'Find a rental unit';
const _body = 'Search by name or browse your saved rental units below.';

Future<void> _mountGuide(
  WidgetTester tester, {
  VoidCallback? underneath,
  GlobalKey<NavigatorState>? navigator,
  ValueNotifier<bool>? show,
  String body = _body,
  bool dark = false,
  double scale = 1,
}) async {
  final target = GlobalKey();
  final guide = CoachMarkOverlay(
    setId: _guideId,
    marks: [
      CoachMark(
          id: 'unit',
          title: _firstTitle,
          body: body,
          icon: Icons.apartment,
          accent: AppColors.primary,
          targetKey: target),
      const CoachMark(
          id: 'booking',
          title: 'Review your booking',
          body: _body,
          icon: Icons.event,
          accent: AppColors.primary),
      const CoachMark(
          id: 'help',
          title: 'Get help',
          body: _body,
          icon: Icons.help,
          accent: AppColors.primary),
    ],
    child: Align(
        alignment: Alignment.topCenter,
        child: TextButton(
            key: target,
            onPressed: underneath,
            child: const Text('Underlying unit'))),
  );
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigator,
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
      appBar: AppBar(
          title: TextButton(
              onPressed: underneath, child: const Text('Underlying header'))),
      body: show == null
          ? guide
          : ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, visible, __) =>
                  visible ? guide : const Text('Signed out')),
      bottomNavigationBar: SizedBox(
          height: 64,
          child: TextButton(
              onPressed: underneath,
              child: const Text('Underlying navigation'))),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'only Next advances; background, target and text never act or dismiss',
      (tester) async {
    var underlyingPresses = 0;
    await _mountGuide(tester, underneath: () => underlyingPresses++);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Back'))
            .onPressed,
        isNull);
    final header = tester.getCenter(find.text('Underlying header'));
    final target = tester.getCenter(find.text('Underlying unit'));
    final navigation = tester.getCenter(find.text('Underlying navigation'));
    for (final point in [const Offset(4, 200), header, target, navigation]) {
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
    }
    await tester.tap(find.text(_body));
    await tester.dragFrom(const Offset(8, 200), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(find.text(_firstTitle), findsOneWidget);
    expect(underlyingPresses, 0);
    expect(await CoachMarkService.hasSeen(_guideId), isFalse);
    await _tap(tester, 'Next');
    expect(find.text('2 / 3'), findsOneWidget);
    await _tap(tester, 'Back');
    expect(find.text('1 / 3'), findsOneWidget);
    await _tap(tester, 'Skip');
    expect(find.text(_firstTitle), findsNothing);
    expect(await CoachMarkService.hasSeen(_guideId), isTrue);
    await _tap(tester, 'Underlying navigation');
    expect(underlyingPresses, 1);
  });

  testWidgets(
      'hardware Back goes to previous step; only Done records completion',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await _mountGuide(tester, navigator: navigator);
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await _tap(tester, 'Next');
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await _tap(tester, 'Next');
    await _tap(tester, 'Next');
    expect(find.text('3 / 3'), findsOneWidget);
    expect(await CoachMarkService.hasSeen(_guideId), isFalse);
    await _tap(tester, 'Done');
    expect(await CoachMarkService.hasSeen(_guideId), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await _mountGuide(tester);
    expect(find.text(_firstTitle), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'removing a private screen removes its guide without marking it seen',
      (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await _mountGuide(tester, show: visible);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text(_firstTitle), findsNothing);
    expect(await CoachMarkService.hasSeen(_guideId), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'guidance remains usable at 320px and 200% text (${dark ? 'dark' : 'light'})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mountGuide(tester,
          dark: dark, scale: 2, body: List.filled(12, _body).join(' '));
      expect(tester.takeException(), isNull);
      expect(find.text('Next').hitTestable(), findsOneWidget);
      expect(find.text('Skip').hitTestable(), findsOneWidget);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      await _tap(tester, 'Next');
      expect(find.text('2 / 3'), findsOneWidget);
      await _tap(tester, 'Back');
      expect(find.text('1 / 3'), findsOneWidget);
      await _tap(tester, 'Skip');
      expect(tester.takeException(), isNull);
    });
  }

  for (final role in UserRole.values) {
    testWidgets(
        '$role introduction needs buttons; swipe and background do not advance',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = UserSession()
        ..signIn(email: 'reader@example.com', displayName: 'Aina', role: role);
      addTearDown(session.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(UserSessionAccess(
          session: session,
          child: MaterialApp(
            navigatorKey: navigator,
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: const OnboardingScreen(),
          )));
      await tester.pumpAndSettle();
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.page, 0);
      await tester.tapAt(const Offset(10, 200));
      await tester.drag(find.byType(PageView), const Offset(-280, 0));
      await tester.pumpAndSettle();
      expect(pageView.controller!.page, 0);
      await _tap(tester, 'Next');
      expect(pageView.controller!.page, 1);
      await _tap(tester, 'Back');
      expect(pageView.controller!.page, 0);
      await _tap(tester, 'Next');
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(pageView.controller!.page, 0);
      expect(session.hasSeenOnboarding, isFalse);
      await _tap(tester, 'Next');
      await _tap(tester, 'Next');
      expect(find.text('Get started').hitTestable(), findsOneWidget);
      await _tap(tester, 'Get started');
      expect(session.hasSeenOnboarding, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('introduction Skip is an explicit way out', (tester) async {
    final session = UserSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(UserSessionAccess(
        session: session,
        child: MaterialApp(
            home: const OnboardingScreen(), theme: AppTheme.light())));
    await tester.pumpAndSettle();
    await _tap(tester, 'Skip');
    expect(session.hasSeenOnboarding, isTrue);
  });
}
