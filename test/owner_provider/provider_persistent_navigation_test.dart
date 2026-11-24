import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/widgets/provider_workspace_navigation.dart';
import 'package:smart_rental_management/owner_provider/widgets/app_bottom_nav.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_schedule_screen.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_profile_screen.dart';
import 'package:smart_rental_management/owner_provider/screens/earnings_history_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/schedule_binding.dart';
import 'package:smart_rental_management/owner_provider/services/backend/cursor_feed.dart';
import 'package:smart_rental_management/owner_provider/services/backend/earnings_binding.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'support/earnings_fixture.dart';
import 'support/profile_fixture.dart';

class _Routes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = routes.indexOf(oldRoute!);
    if (index >= 0) routes[index] = newRoute!;
  }
}

class _Tab extends StatelessWidget {
  const _Tab(this.id);
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('Page $id')),
      body: const SizedBox(),
      bottomNavigationBar: ProviderBottomNav(
          activeId: id,
          onChange: (next) =>
              ProviderTabNavigation.open(context, next, (_) => _Tab(next))));
}

void main() {
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter.ttf')))
        .load();
  });
  testWidgets(
      'Schedule retains shared menu; tab switching has bounded routes and Inbox returns home',
      (tester) async {
    final observer = _Routes();
    await tester.pumpWidget(
        MaterialApp(navigatorObservers: [observer], home: const _Tab('inbox')));
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Page schedule'), findsOneWidget);
    expect(tester.widget<AppBottomNav>(find.byType(AppBottomNav)).activeId,
        'schedule');
    expect(observer.routes.length, 2);
    final scheduleRoute = observer.routes.last;
    for (final label in [
      'Earnings',
      'Profile',
      'Schedule',
      'Profile',
      'Earnings'
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(observer.routes.length, 2);
      expect(find.byType(AppBottomNav), findsOneWidget);
    }
    expect(observer.routes, isNot(contains(scheduleRoute)));
    final route = observer.routes.last;
    await tester.tap(find.text('Earnings'));
    await tester.pumpAndSettle();
    expect(observer.routes.last, same(route));
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    expect(observer.routes.length, 1);
    expect(find.text('Page inbox'), findsOneWidget);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(observer.routes.length, 1);
    expect(find.text('Page inbox'), findsOneWidget);
  });
  testWidgets('rapid destination taps cannot push duplicate routes',
      (tester) async {
    var calls = 0;
    final wait = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            bottomNavigationBar: ProviderBottomNav(
                activeId: 'schedule',
                onChange: (id) {
                  calls++;
                  return wait.future;
                }))));
    await tester.tap(find.text('Earnings'));
    await tester.tap(find.text('Profile'));
    expect(calls, 1);
    wait.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    expect(calls, 1);
  });
  testWidgets(
      'settings subpage can return to active Profile or another tab without stacking',
      (tester) async {
    final observer = _Routes();
    await tester.pumpWidget(
        MaterialApp(navigatorObservers: [observer], home: const _Tab('inbox')));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    final profileRoute = observer.routes.last;
    Future<void> pushEditor() async {
      final context = tester.element(find.text('Page profile'));
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (context) => Scaffold(
              body: const Text('Day editor'),
              bottomNavigationBar: ProviderBottomNav(
                  activeId: 'profile',
                  allowActiveNavigation: true,
                  onChange: (id) => ProviderTabNavigation.open(
                      context, id, (_) => _Tab(id))))));
      await tester.pumpAndSettle();
      expect(observer.routes.length, 3);
    }

    await pushEditor();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(observer.routes.length, 2);
    expect(observer.routes.last, same(profileRoute));
    expect(find.text('Page profile'), findsOneWidget);
    await pushEditor();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(observer.routes.length, 2);
    expect(find.text('Page schedule'), findsOneWidget);
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    expect(observer.routes.length, 1);
  });
  for (final dark in [false, true]) {
    testWidgets(
        'actual Schedule and other primary pages keep bar at 320px/200% text $dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final schedule = ScheduleBinding(
          weekStart: DateTime.utc(2026, 10, 19),
          openFeed: (a, b) => CursorFeed<Map<String, dynamic>>(
              active: false,
              loadPage: (_) async => const CursorPage(items: []),
              idOf: (r) => r['booking_id'] as String,
              compare: (a, b) => 0));
      schedule.setActive(true);
      await schedule.refresh();
      final sessions = StreamController<String?>.broadcast(),
          live = StreamController<PageChange>.broadcast();
      final earnings = EarningsBinding(
          load: (p, {before, asOf}) async => earningsReport(period: p),
          userId: earningsActor,
          currentUserId: () => earningsActor,
          sessionChanges: sessions.stream,
          changes: () => live.stream);
      earnings.setActive(true);
      Future<void> mount(Widget child) async {
        await tester.pumpWidget(MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!),
            home: child));
        await tester.pumpAndSettle();
        expect(find.text('Inbox'), findsOneWidget);
        expect(find.text('Schedule'), findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);
        expect(tester.getBottomRight(find.byType(AppBottomNav)).dy, 568);
        expect(tester.takeException(), isNull);
      }

      await mount(ProviderScheduleScreen(
          providerName: '',
          bookings: const [],
          binding: schedule,
          bottomNavigationBar: ProviderBottomNav(
              activeId: 'schedule', onChange: (id) async {})));
      expect(
          tester
              .widget<Semantics>(find.byKey(const ValueKey('nav-schedule')))
              .properties
              .selected,
          true);
      await mount(EarningsHistoryScreen(
          providerName: '',
          bookings: const [],
          binding: earnings,
          bottomNavigationBar: ProviderBottomNav(
              activeId: 'earnings', onChange: (id) async {})));
      final profile = profileReport();
      await mount(ProviderProfileScreen(
          provider: profile.presentation,
          snapshot: profile,
          bottomNavigationBar:
              ProviderBottomNav(activeId: 'profile', onChange: (id) async {})));
      await tester.pumpWidget(const SizedBox());
      schedule.dispose();
      earnings.dispose();
      await sessions.close();
      await live.close();
    });
  }
  testWidgets('Schedule failure does not remove bottom navigation',
      (tester) async {
    final schedule = ScheduleBinding(
        weekStart: DateTime.utc(2026, 10, 19),
        openFeed: (a, b) => CursorFeed<Map<String, dynamic>>(
            active: false,
            loadPage: (_) async => throw StateError('offline'),
            idOf: (r) => r['booking_id'] as String,
            compare: (a, b) => 0));
    schedule.setActive(true);
    await schedule.refresh();
    await tester.pumpWidget(MaterialApp(
        home: ProviderScheduleScreen(
            providerName: '',
            bookings: const [],
            binding: schedule,
            bottomNavigationBar: ProviderBottomNav(
                activeId: 'schedule', onChange: (id) async {}))));
    await tester.pumpAndSettle();
    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(tester.widget<AppBottomNav>(find.byType(AppBottomNav)).activeId,
        'schedule');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    schedule.dispose();
  });
}
