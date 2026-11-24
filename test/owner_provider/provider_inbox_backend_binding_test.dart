import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_rental_management/owner_provider/main.dart';
import 'package:smart_rental_management/owner_provider/models/demo_data.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_inbox_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/cursor_feed.dart';
import 'package:smart_rental_management/owner_provider/services/backend/workspace_binding.dart';
import 'package:smart_rental_management/owner_provider/services/booking_store.dart';
import 'package:smart_rental_management/owner_provider/services/message_store.dart';
import 'package:smart_rental_management/owner_provider/services/property_store.dart';
import 'package:smart_rental_management/owner_provider/services/provider_store.dart';
import 'package:smart_rental_management/owner_provider/services/review_store.dart';
import 'package:smart_rental_management/owner_provider/services/user_session.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'package:smart_rental_management/owner_provider/widgets/workspace_actions.dart';

Map<String, dynamic> row(String id, {String status = 'Pending'}) => {
      'booking_id': id,
      'current_status': status,
      'unit_name': 'Server unit $id',
      'building_name': 'Server building',
      'service_name': 'Cleaning',
      'requested_start_at': '2030-01-01T01:00:00Z',
      'requested_end_at': '2030-01-01T03:00:00Z',
    };

WorkspaceBinding bindingFor(
  Future<CursorPage<Map<String, dynamic>>> Function(PageCursor?) load,
) =>
    WorkspaceBinding(
      provider: true,
      feed: CursorFeed<Map<String, dynamic>>(
        active: false,
        loadPage: load,
        idOf: (item) => item['booking_id'] as String,
        compare: (a, b) =>
            (a['booking_id'] as String).compareTo(b['booking_id'] as String),
      ),
      loadOverview: () async => {
        'approval_status': 'approved',
        'rating_average': 4.75,
        'completed_job_count': 42,
      },
    );

class RecordingActions implements WorkspaceActions {
  String? opened;
  @override
  Future<void> messages(BuildContext context) async {
    opened = 'messages';
  }

  @override
  Future<void> notifications(BuildContext context) async {
    opened = 'notifications';
  }

  @override
  Future<void> about(BuildContext context) async {
    opened = 'about';
  }

  @override
  Future<void> profile(BuildContext context, {bool edit = false}) async {
    opened = edit ? 'edit-profile' : 'profile';
  }

  @override
  Future<void> booking(BuildContext context, String id) async {
    opened = id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> mount(
  WidgetTester tester,
  WorkspaceBinding binding, {
  WorkspaceActions? actions,
  bool dark = false,
  bool showShell = false,
}) async {
  binding.setActive(true);
  Widget screen = ProviderInboxScreen(
    binding: binding,
    actions: actions,
    // A preview name must never filter authenticated server rows.
    provider: DemoProvider.seeded()[1],
    showShell: showShell,
  );
  if (!showShell) screen = Scaffold(body: screen);
  Widget app = MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: screen,
  );
  if (showShell) {
    final session = UserSession();
    final bookings = BookingStore(initialBookings: []);
    final providers = ProviderStore();
    final properties = PropertyStore();
    final reviews = ReviewStore();
    final messages = MessageStore();
    for (final resource in <ChangeNotifier>[
      session,
      bookings,
      providers,
      properties,
      reviews,
      messages,
    ]) {
      addTearDown(resource.dispose);
    }
    app = UserSessionAccess(
      session: session,
      child: AppProviders(
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        onToggleTheme: () {},
        bookingStore: bookings,
        providerStore: providers,
        propertyStore: properties,
        reviewStore: reviews,
        messageStore: messages,
        child: app,
      ),
    );
  }
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  // NestedScrollView must collapse its header before the lazy inner list can
  // build or expose the target. ensureVisible alone cannot do both reliably.
  await tester.scrollUntilVisible(
    target.hitTestable(),
    160,
    scrollable: find
        .descendant(
          of: find.byType(NestedScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 20,
  );
  await tester.pumpAndSettle();
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: 'The target must be built and reachable through actual scrolling.',
  );
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'expired response uses its actual instant and keeps details $dark',
        (tester) async {
      final now = DateTime.now().toUtc();
      final binding = bindingFor((_) async => CursorPage(items: [
            {
              ...row('expired'),
              'requested_start_at':
                  now.subtract(const Duration(minutes: 1)).toIso8601String(),
              'requested_end_at':
                  now.add(const Duration(hours: 2)).toIso8601String()
            },
            {
              ...row('future'),
              'requested_start_at':
                  now.add(const Duration(days: 1)).toIso8601String(),
              'requested_end_at':
                  now.add(const Duration(days: 1, hours: 2)).toIso8601String()
            },
          ]));
      final actions = RecordingActions();
      await mount(tester, binding, dark: dark, actions: actions);
      await reveal(tester, find.text('Expired'));
      final expiredText =
          tester.widget<Text>(find.text('Response time passed'));
      final context = tester.element(find.text('Expired'));
      expect(expiredText.style!.color, Theme.of(context).colorScheme.error);
      expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
      expect(binding.bookings.first.status, BookingStatus.pending);
      await tester.tap(find.text('Server unit expired, Server building'));
      await tester.pumpAndSettle();
      expect(actions.opened, 'expired');
      await reveal(tester, find.text('Server unit future, Server building'));
      expect(find.text('Pending'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      binding.dispose();
    });
  }
  testWidgets(
      'Inbox guidance uses Next, blocks the whole shell and allows Back and Skip',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final binding = bindingFor((_) async => CursorPage(items: [row('guided')]));
    final actions = RecordingActions();
    await mount(tester, binding, actions: actions, showShell: true);
    expect(find.text('Your work overview'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byTooltip('Messages')));
    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('nav-earnings'))));
    await tester.pumpAndSettle();
    expect(actions.opened, isNull);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Your main pages'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Review a new request'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Your main pages'), findsNothing);
    await tester.tap(find.byTooltip('Messages'));
    await tester.pumpAndSettle();
    expect(actions.opened, 'messages');
    await tester.pumpWidget(const SizedBox());
    binding.dispose();
  });
  testWidgets('Inbox uses bottom tabs and header messages without a drawer',
      (tester) async {
    final binding = bindingFor((_) async => const CursorPage(items: []));
    final actions = RecordingActions();
    await mount(tester, binding, actions: actions, showShell: true);
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).drawer, isNull);
    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.byTooltip('Switch to dark mode'), findsNothing);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-earnings')), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(actions.opened, 'notifications');
    await tester.tap(find.byTooltip('Messages'));
    await tester.pumpAndSettle();
    expect(actions.opened, 'messages');
    expect(find.textContaining('not connected yet'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    binding.dispose();
  });
  for (final state in ['empty', 'populated', 'error']) {
    testWidgets(
        'pulling Inbox header refreshes $state state without a refresh button',
        (tester) async {
      var reads = 0;
      final binding = bindingFor((_) async {
        final call = ++reads;
        if (state == 'error' && call == 1) throw StateError('offline');
        if (state == 'empty' && call == 1) return const CursorPage(items: []);
        return CursorPage(items: [row(call == 1 ? 'before' : 'fresh')]);
      });
      await mount(tester, binding);
      expect(reads, 1);
      expect(find.text('Refresh inbox'), findsNothing);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await tester.dragFrom(
          tester.getCenter(find.text('Your cleaning work, in one place.')),
          const Offset(0, 420));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(binding.bookings.single.id, 'fresh');
      expect(binding.error, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      binding.dispose();
    });
  }
  testWidgets(
      'every empty job tab supports pull to refresh with one request per gesture',
      (tester) async {
    var reads = 0;
    final binding = bindingFor((_) async {
      reads++;
      return const CursorPage(items: []);
    });
    await mount(tester, binding);
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    for (var index = 0; index < 4; index++) {
      tabs.controller!.animateTo(index);
      await tester.pumpAndSettle();
      final scroll = find.byType(ListView).hitTestable();
      // Expose the empty list, then expand the header back to its top boundary.
      final nested =
          tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
      nested.outerController
          .jumpTo(nested.outerController.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(scroll, findsOneWidget);
      await tester.drag(scroll, const Offset(0, 500));
      await tester.pumpAndSettle();
      // Once at the very top, a further pull refreshes the selected tab.
      if (reads == index + 1) {
        await tester.drag(scroll, const Offset(0, 420));
        await tester.pumpAndSettle();
      }
      expect(reads, index + 2);
      expect(tester.takeException(), isNull);
    }
    tabs.controller!.animateTo(0);
    await tester.pumpAndSettle();
    final nested =
        tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
    nested.outerController
        .jumpTo(nested.outerController.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(tabs.controller!.index, 1);
    expect(reads, 5); // Horizontal tab swipes must not request a refresh.
    await tester.pumpWidget(const SizedBox());
    binding.dispose();
  });
  testWidgets(
      'connected bottom Profile opens original-profile route rather than setup',
      (tester) async {
    final binding = bindingFor((_) async => const CursorPage(items: []));
    final actions = RecordingActions();
    await mount(tester, binding, actions: actions, showShell: true);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(actions.opened, 'profile');
    await tester.pumpWidget(const SizedBox());
    binding.dispose();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'coachmark_seen_provider_inbox_v1': true,
    });
  });
  testWidgets(
      'server cards ignore preview identity and review uses shared actions',
      (tester) async {
    final binding = bindingFor((_) async => CursorPage(items: [row('one')]));
    addTearDown(binding.dispose);
    final actions = RecordingActions();
    await mount(tester, binding, actions: actions);

    expect(find.text('Your cleaning work, in one place.'), findsOneWidget);
    expect(find.text('At a glance'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Rating 4.75 · 42 completed jobs'), findsOneWidget);
    expect(find.text('Open Earnings'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    expect(find.text('Review request'), findsNothing);
    await reveal(tester, find.text('Server unit one, Server building'));
    await tester.tap(find.text('Server unit one, Server building'));
    expect(actions.opened, 'one');
    expect(binding.bookings.single.status, BookingStatus.pending);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'malformed server projections render an error before reading cards',
      (tester) async {
    final binding = bindingFor(
      (_) async => CursorPage(
        items: [
          row('invalid', status: 'Unsupported status'),
        ],
      ),
    );
    addTearDown(binding.dispose);
    await mount(tester, binding, showShell: true);

    expect(binding.error, isA<FormatException>());
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('New (—)'),
      ),
      findsOneWidget,
    );
    await reveal(tester, find.text('Could not load inbox'));
    expect(find.text('Could not load inbox'), findsOneWidget);
    expect(find.textContaining('Unsupported status'), findsNothing);
    expect(find.text('Review request'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial counts and paging retry retain server cards',
      (tester) async {
    var nextCalls = 0;
    final binding = bindingFor((cursor) async {
      if (cursor == null) {
        return CursorPage(
          items: [row('one')],
          next: const PageCursor('2030-01-01T01:00:00Z', 'one'),
        );
      }
      if (nextCalls++ == 0) throw StateError('private transport diagnostic');
      return CursorPage(items: [row('two')]);
    });
    addTearDown(binding.dispose);
    await mount(tester, binding, showShell: true);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('New (1+)'),
      ),
      findsOneWidget,
    );
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.labelStyle?.fontFamily, 'Inter');
    expect(tabs.unselectedLabelStyle?.fontFamily, 'Inter');
    await reveal(tester, find.text('Load more jobs'));
    await tester.tap(find.text('Load more jobs'));
    await tester.pumpAndSettle();
    expect(binding.bookings, hasLength(1));
    expect(find.text('Retry load more'), findsOneWidget);
    expect(find.textContaining('private transport diagnostic'), findsNothing);
    await reveal(tester, find.text('Retry load more'));
    await tester.tap(find.text('Retry load more'));
    await tester.pumpAndSettle();
    expect(binding.bookings, hasLength(2));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('New (2)'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('original hero and cards fit a narrow dark connected workspace',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final binding = bindingFor((_) async => CursorPage(items: [row('dark')]));
    addTearDown(binding.dispose);
    await mount(tester, binding, dark: true);

    expect(find.text('Your cleaning work, in one place.'), findsOneWidget);
    expect(find.text('At a glance'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await reveal(tester, find.text('Server unit dark, Server building'));
    await tester.pumpAndSettle();
    expect(find.text('Server unit dark, Server building'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Widget removal must leave caller-owned binding usable.
    await binding.refresh();
    expect(binding.bookings, hasLength(1));
  });
}
