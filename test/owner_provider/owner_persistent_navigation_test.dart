import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/screens/owner_home_screen.dart';
import 'package:smart_rental_management/owner_provider/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_rental_management/owner_provider/screens/owner_workspace_dashboard.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_backend_provider.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_owner_repository.dart';
import 'package:smart_rental_management/owner_provider/services/backend/cursor_feed.dart';
import 'package:smart_rental_management/owner_provider/services/backend/workspace_binding.dart';
import 'package:smart_rental_management/owner_provider/services/user_session.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'package:smart_rental_management/owner_provider/widgets/owner_workspace_navigation.dart';
import 'package:smart_rental_management/owner_provider/widgets/workspace_actions.dart';

const actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const propertyId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
Map<String, dynamic> property() => {
      'actor_id': actor,
      'property_id': propertyId,
      'unit_name': 'Synthetic Unit',
      'building_name': 'Test Building',
      'address': 'Synthetic address only',
      'bedrooms': 2,
      'size_sqft': 800,
      'cleaning_window_start': '08:00:00',
      'cleaning_window_end': '18:00:00',
      'property_revision': 1,
      'total': 0,
      'open': 0,
      'done': 0,
    };

class _Auth extends GoTrueClient {
  _Auth()
      : super(url: 'https://fixture.invalid/auth/v1', autoRefreshToken: false);
  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
  @override
  User get currentUser => User(
      id: actor,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01');
}

class _Client extends SupabaseClient {
  _Client(this.fixture, http.Client transport)
      : super('https://fixture.invalid', 'sb_publishable_fixture',
            httpClient: transport,
            authOptions: const AuthClientOptions(autoRefreshToken: false));
  final _Auth fixture;
  @override
  GoTrueClient get auth => fixture;
}

class _Routes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = routes.indexOf(oldRoute!);
    if (i >= 0) routes[i] = newRoute!;
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter.ttf')))
        .load();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  Future<SupabaseBackendProvider> backend(WidgetTester tester,
      {required String state, required Completer<void> hold}) async {
    final resources = (await tester.runAsync(() async {
      final auth = _Auth();
      final transport = MockClient((request) async {
        if (state == 'loading') await hold.future;
        if (state == 'error')
          return http.Response(jsonEncode({'message': 'PRIVATE FAILURE'}), 503,
              request: request, headers: {'content-type': 'application/json'});
        final path = request.url.path;
        final dynamic body = switch (path) {
          '/rest/v1/rpc/my_owner_portfolio_summary' => {
              'actor_id': actor,
              'property_count': 1,
              'building_count': 1,
              'size_sqft': 800,
              'open': 0,
              'done': 0,
              'total': 0,
            },
          '/rest/v1/rpc/my_owner_profile' => {
              'actor_id': actor,
              'email': 'synthetic@rental-test.invalid',
              'full_name': 'Synthetic Owner',
              'contact_number': null,
              'revision': 1,
              'property_count': 1
            },
          '/rest/v1/rpc/page_my_properties' => {
              'actor_id': actor,
              'total_count': 1,
              'items': [property()],
              'next_cursor': null
            },
          '/rest/v1/rpc/my_property' => property(),
          '/rest/v1/rpc/my_property_location' => <String,dynamic>{},
          '/rest/v1/rpc/list_my_property_locations' => <dynamic>[],
          '/rest/v1/rpc/page_my_property_bookings' => {
              'actor_id': actor,
              'items': [],
              'next_cursor': null
            },
          '/rest/v1/property' => [property()],
          '/rest/v1/service_type' => [
              {'service_type_id': 'service-1', 'name': 'Cleaning'}
            ],
          '/rest/v1/rpc/page_approved_provider_directory' => {
              'actor_id': actor,
              'items': [
                {
                  'provider_id': 'provider-1',
                  'listed_at': '2026-01-01T00:00:00Z',
                  'full_name': 'Synthetic Provider',
                  'bio': 'Cleaning for rental units',
                  'service_area': 'Test area',
                  'hourly_rate': 40,
                  'daily_rate': null,
                  'rating_average': null,
                  'completed_job_count': 0,
                  'services': [
                    {'name': 'Cleaning', 'description': 'Test scope'}
                  ]
                }
              ],
              'has_more': false
            },
          '/rest/v1/rpc/page_owner_booking_search' => {
              'actor_id': actor,
              'items': [],
              'has_more': false
            },
          _ => throw StateError('Unexpected offline request: $path'),
        };
        return http.Response(jsonEncode(body), 200,
            request: request, headers: {'content-type': 'application/json'});
      });
      return (auth, _Client(auth, transport));
    }))!;
    final result = SupabaseBackendProvider(resources.$2);
    addTearDown(() async {
      await tester.runAsync(resources.$2.dispose);
      resources.$1.dispose();
    });
    return result;
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget home, bool dark, {NavigatorObserver? observer}) =>
      MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          navigatorObservers: [if (observer != null) observer],
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: home);
  Finder nav(String label) => find.descendant(
      of: find.byType(OwnerWorkspaceNav), matching: find.text(label));

  for (final dark in [false, true]) {
    for (final id in ['properties', 'browse', 'profile']) {
      for (final state in ['loading', 'error', 'ready']) {
        testWidgets('$id retains menu/back in $state dark=$dark 320px/200%',
            (tester) async {
          phone(tester);
          final hold = Completer<void>();
          final connected = await backend(tester, state: state, hold: hold);
          final actions = WorkspaceActions(connected, UserRole.owner);
          await tester.pumpWidget(app(
              Scaffold(
                  body: Builder(
                      builder: (context) => TextButton(
                          onPressed: () => actions.ownerTab(context, id),
                          child: const Text('Open destination')))),
              dark));
          await tester.tap(find.text('Open destination'));
          if (state == 'loading') {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          } else {
            await tester.pumpAndSettle();
          }
          expect(find.byType(OwnerWorkspaceNav), findsOneWidget);
          expect(
              tester
                  .widget<OwnerWorkspaceNav>(find.byType(OwnerWorkspaceNav))
                  .activeId,
              id);
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          expect(find.textContaining('PRIVATE FAILURE'), findsNothing);
          if (state == 'ready') {
            expect(find.text('Sign in again'), findsNothing);
            expect(find.textContaining('Could not'), findsNothing);
          }
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
          expect(find.text('Open destination'), findsOneWidget);
          expect(find.byType(OwnerWorkspaceNav), findsNothing);
          await tester.pumpWidget(const SizedBox());
          if (!hold.isCompleted) hold.complete();
          await tester.pump();
        });
      }
    }
    testWidgets('actual Owner root tab switching/back is bounded dark=$dark',
        (tester) async {
      phone(tester);
      final hold = Completer<void>();
      final connected = await backend(tester, state: 'ready', hold: hold);
      final binding = WorkspaceBinding(
          provider: false,
          feed: CursorFeed<Map<String, dynamic>>(
              active: false,
              loadPage: (_) async => const CursorPage(items: []),
              idOf: (row) => row['booking_id'] as String,
              compare: (_, __) => 0),
          loadOverview: () async => const OwnerDashboardSnapshot(
              propertyCount: 1,
              pendingCount: 0,
              activeCount: 0,
              completedCount: 0));
      binding.setActive(true);
      final session = UserSession()
        ..signIn(
            email: 'synthetic@rental-test.invalid',
            displayName: 'Synthetic Owner',
            role: UserRole.owner);
      final routes = _Routes();
      await tester.pumpWidget(UserSessionAccess(
          session: session,
          child: app(
              OwnerHomeScreen(
                  binding: binding,
                  actions: WorkspaceActions(connected, UserRole.owner)),
              dark,
              observer: routes)));
      await tester.pumpAndSettle();
      for (final (label, id) in [
        ('Properties', 'properties'),
        ('Profile', 'profile'),
        ('Providers', 'browse'),
        ('Properties', 'properties'),
        ('Providers', 'browse')
      ]) {
        await tester.tap(nav(label));
        await tester.pumpAndSettle();
        expect(routes.routes.length, 2);
        expect(
            routes.routes.last.settings.name, OwnerTabNavigation.nameFor(id));
        expect(find.byType(OwnerWorkspaceNav), findsOneWidget);
        expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(nav('Providers')); // Same active tab must not push.
      await tester.pumpAndSettle();
      expect(routes.routes.length, 2);
      expect(find.text('Browse cleaning providers'), findsOneWidget);
      expect(find.text('Select service date'), findsNothing);
      await tester.scrollUntilVisible(
          find.text('View profile').hitTestable(), 160,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('View profile'));
      await tester.pumpAndSettle();
      expect(find.text('Provider profile'), findsOneWidget);
      expect(find.byType(OwnerWorkspaceNav), findsOneWidget);
      expect(routes.routes.length, 3);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Providers'), findsOneWidget);
      expect(routes.routes.length, 2);
      await tester.tap(nav('Properties'));
      await tester.pumpAndSettle();
      final unit = find.text('Unit Synthetic Unit, Test Building');
      await tester.scrollUntilVisible(unit, 180,
          scrollable: find.byType(Scrollable).first, maxScrolls: 30);
      await tester.pumpAndSettle();
      await tester.tap(unit);
      await tester.pumpAndSettle();
      expect(routes.routes.length, 3);
      expect(find.byType(OwnerWorkspaceNav), findsOneWidget);
      expect(find.text('Schedule new cleaning'), findsOneWidget);
      expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
      await tester.tap(nav('Profile'));
      await tester.pumpAndSettle();
      expect(routes.routes.length, 2);
      expect(routes.routes.last.settings.name,
          OwnerTabNavigation.nameFor('profile'));
      await tester.tap(nav('Bookings'));
      await tester.pumpAndSettle();
      expect(routes.routes.length, 1);
      expect(find.widgetWithText(AppBar, 'Bookings'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Owner Dashboard'), findsOneWidget);
      await tester.tap(nav('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(nav('Home'));
      await tester.pumpAndSettle();
      expect(routes.routes.length, 1);
      expect(find.text('Owner Dashboard'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      binding.dispose();
      session.dispose();
    });
  }

  testWidgets('rapid menu taps invoke only one navigation operation',
      (tester) async {
    final hold = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: OwnerDestinationFrame(
            activeId: 'profile',
            onChange: (_) {
              calls++;
              return hold.future;
            },
            child: const SizedBox())));
    await tester.tap(nav('Properties'));
    await tester.tap(nav('Providers'));
    expect(calls, 1);
    hold.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'local original properties/providers/profile also keep menu and Back',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(const RentalAppDemo(localPreviewRole: UserRole.owner));
    await tester.pumpAndSettle();
    for (final (label, title) in [
      ('Properties', 'My properties'),
      ('Providers', 'Browse providers'),
      ('Profile', 'Profile & settings')
    ]) {
      await tester.tap(nav(label));
      await tester.pumpAndSettle();
      expect(find.byType(OwnerWorkspaceNav), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      if (label == 'Properties')
        expect(find.byTooltip('Add property'), findsOneWidget);
      expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
      await tester.tap(nav('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Owner Dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
