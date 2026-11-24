import 'support/weekly_hours_fixture.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/features/availability/domain/provider_setup.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_provider_setup_screen.dart';
import 'package:smart_rental_management/owner_provider/screens/earnings_history_screen.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_schedule_screen.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'package:smart_rental_management/owner_provider/services/backend/cursor_feed.dart';
import 'package:smart_rental_management/owner_provider/services/backend/earnings_binding.dart';
import 'package:smart_rental_management/owner_provider/services/backend/earnings_snapshot.dart';
import 'package:smart_rental_management/owner_provider/services/backend/provider_profile_binding.dart';
import 'package:smart_rental_management/owner_provider/services/backend/provider_profile_snapshot.dart';
import 'package:smart_rental_management/owner_provider/services/backend/schedule_binding.dart';
import 'package:smart_rental_management/owner_provider/services/backend/session_snapshot_cache.dart';
import 'package:smart_rental_management/owner_provider/services/backend/workspace_binding.dart';
import 'support/profile_fixture.dart';
import 'support/earnings_fixture.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'silent schedule refresh and failure fit 320x568 at 200% text, dark=$dark',
        (tester) async {
      await (FontLoader('Inter')
            ..addFont(rootBundle.load('assets/fonts/Inter.ttf')))
          .load();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<CursorPage<Map<String, dynamic>>>();
      final b = ScheduleBinding(
          weekStart: DateTime.utc(2026, 10, 19),
          openFeed: (start, end) => CursorFeed(
              active: false,
              preserveOnRefresh: true,
              initialPage: const CursorPage(items: []),
              loadPage: (_) => pending.future,
              idOf: (r) => r['booking_id'] as String,
              compare: (_, __) => 0));
      b.setActive(true);
      await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (_, child) => MediaQuery(
              data: const MediaQueryData(
                  size: Size(320, 568), textScaler: TextScaler.linear(2)),
              child: child!),
          home: ProviderScheduleScreen(
              providerName: '', bookings: const [], binding: b)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Showing saved schedule'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      pending.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Saved schedule may be out of date'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      b.dispose();
    });
  }
  test('memory snapshots: TTL, LRU, byte budget, identity and logout epochs',
      () {
    String? actor = 'a';
    var now = DateTime.utc(2026, 10, 23);
    final cache = SessionSnapshotCache(
        currentUserId: () => actor,
        now: () => now,
        maxEntries: 2,
        maxBytes: 20);
    final lease = cache.lease();
    cache.put('a', 'old', lease: lease, bytes: 8);
    cache.put('b', 'other', lease: lease, bytes: 8);
    expect(cache.peek<String>('a')!.value, 'old');
    cache.put('c', 'new', lease: lease, bytes: 8);
    expect(cache.peek<String>('b'), isNull);
    cache.put('oversized', 'x', lease: lease, bytes: 21);
    expect(cache.entryCount, 2);
    expect(cache.sizeBytes, 16);
    now = now.add(const Duration(minutes: 5));
    expect(cache.peek<String>('a'), isNull);
    actor = null;
    cache.bindSession(actor);
    actor = 'a';
    cache.bindSession(actor);
    cache.put('old-flight', 'x', lease: lease, bytes: 8);
    expect(cache.entryCount, 0);
    cache.put('private', 'a', lease: cache.lease(), bytes: 8);
    actor = 'b';
    expect(cache.peek<String>('private'), isNull);
  });

  test(
      'writes invalidate before/after, block concurrent reads, including unknown result',
      () async {
    final cache = SessionSnapshotCache(currentUserId: () => 'a');
    final old = cache.lease();
    cache.put('private', 'before', lease: old, bytes: 8);
    final pending = Completer<void>();
    final write = cache.write(() => pending.future);
    expect(cache.entryCount, 0);
    cache.put('racing', 'old', lease: cache.lease(), bytes: 8);
    expect(cache.entryCount, 0);
    pending.complete();
    await write;
    cache.put('old', 'x', lease: old, bytes: 8);
    expect(cache.entryCount, 0);
    cache.put('new', 'x', lease: cache.lease(), bytes: 8);
    await expectLater(
        cache.write<void>(() async => throw StateError('timeout')),
        throwsStateError);
    expect(cache.entryCount, 0);
  });

  test(
      'cached empty page is valid; refresh failure retains it; retry replaces it',
      () async {
    var fail = true;
    final feed = CursorFeed<String>(
        active: false,
        preserveOnRefresh: true,
        initialPage: const CursorPage(items: []),
        loadPage: (_) async {
          if (fail) throw StateError('offline');
          return const CursorPage(items: ['fresh']);
        },
        idOf: (s) => s,
        compare: (a, b) => a.compareTo(b));
    feed.setActive(true);
    expect(feed.refreshing, true);
    await tick();
    expect(feed.hasSnapshot, true);
    expect(feed.error, isNull);
    expect(feed.refreshError, isNotNull);
    fail = false;
    await feed.refresh();
    expect(feed.items, ['fresh']);
    expect(feed.refreshError, isNull);
    feed.dispose();
  });

  test(
      'authorization/malformed refresh removes stale rows and invalidates cache',
      () async {
    for (final failure in [
      const PostgrestException(message: 'denied', code: '42501'),
      const FormatException('bad')
    ]) {
      var rejected = 0;
      final feed = CursorFeed<String>(
          active: false,
          preserveOnRefresh: true,
          initialPage: const CursorPage(items: ['private']),
          onSnapshotRejected: () => rejected++,
          loadPage: (_) async => throw failure,
          idOf: (s) => s,
          compare: (_, __) => 0);
      feed.setActive(true);
      await tick();
      expect(feed.items, isEmpty);
      expect(feed.hasSnapshot, false);
      expect(feed.error, isNotNull);
      expect(rejected, 1);
      feed.dispose();
    }
  });

  test('cached incomplete week never becomes a free calendar', () async {
    final pending = Completer<CursorPage<Map<String, dynamic>>>();
    final binding = ScheduleBinding(
        weekStart: DateTime.utc(2026, 10, 19),
        openFeed: (start, end) => CursorFeed(
            active: false,
            preserveOnRefresh: true,
            initialPage:
                const CursorPage(items: [], next: PageCursor('t', 'id')),
            loadPage: (_) => pending.future,
            idOf: (r) => r['booking_id'] as String,
            compare: (_, __) => 0));
    binding.setActive(true);
    expect(binding.refreshing, true);
    expect(binding.complete, false);
    pending.completeError(StateError('offline'));
    await tick();
    expect(binding.refreshError, isNotNull);
    expect(binding.complete, false);
    binding.dispose();
  });

  test('complete cached week remains visible but is marked updating', () async {
    final pending = Completer<CursorPage<Map<String, dynamic>>>();
    final binding = ScheduleBinding(
        weekStart: DateTime.utc(2026, 10, 19),
        openFeed: (start, end) => CursorFeed(
            active: false,
            preserveOnRefresh: true,
            initialPage: const CursorPage(items: []),
            loadPage: (_) => pending.future,
            idOf: (r) => r['booking_id'] as String,
            compare: (_, __) => 0));
    binding.setActive(true);
    expect(binding.complete, true);
    expect(binding.refreshing, true);
    pending.complete(const CursorPage(items: []));
    await tick();
    expect(binding.complete, true);
    expect(binding.refreshing, false);
    binding.dispose();
  });

  test(
      'profile re-entry uses saved view but editor always reads fresh baseline',
      () async {
    final cache = SessionSnapshotCache(currentUserId: () => profileActor);
    ProviderProfileBinding view(Future<ProviderProfileSnapshot> Function() load,
            {bool cached = true}) =>
        ProviderProfileBinding(
            load: load,
            userId: profileActor,
            currentUserId: () => profileActor,
            sessionChanges: const Stream.empty(),
            cache: cache,
            allowCached: cached);
    final first = view(() async => profileReport());
    first.setActive(true);
    await tick();
    first.dispose();
    final pending = Completer<ProviderProfileSnapshot>();
    final second = view(() => pending.future);
    second.setActive(true);
    expect(second.snapshot!.name, 'Test Provider');
    expect(second.refreshing, true);
    pending.completeError(StateError('offline'));
    await tick();
    expect(second.snapshot, isNotNull);
    expect(second.refreshError, isNotNull);
    second.dispose();
    final editor = view(() async => profileReport(overrides: {'revision': 2}),
        cached: false);
    expect(editor.snapshot, isNull);
    editor.setActive(true);
    await tick();
    expect(editor.snapshot!.revision, 2);
    editor.dispose();
  });

  test(
      'profile security error clears cached identity; initial offline never invents data',
      () async {
    final cache = SessionSnapshotCache(currentUserId: () => profileActor);
    cache.put('profile:self:v1', profileReport(),
        lease: cache.lease(), bytes: 500);
    final b = ProviderProfileBinding(
        load: () async =>
            throw const PostgrestException(message: 'denied', code: '42501'),
        userId: profileActor,
        currentUserId: () => profileActor,
        sessionChanges: const Stream.empty(),
        cache: cache,
        allowCached: true);
    b.setActive(true);
    await tick();
    expect(b.snapshot, isNull);
    expect(cache.entryCount, 0);
    b.dispose();
  });

  test(
      'earnings cache isolated by period; late earlier-period response cannot replace current',
      () async {
    final cache = SessionSnapshotCache(currentUserId: () => earningsActor);
    EarningsBinding make(EarningsLoader load) => EarningsBinding(
        load: load,
        userId: earningsActor,
        currentUserId: () => earningsActor,
        sessionChanges: const Stream.empty(),
        changes: () => const Stream.empty(),
        cache: cache);
    final first =
        make((period, {before, asOf}) async => earningsReport(period: period));
    first.setActive(true);
    await tick();
    first.dispose();
    final pending = Completer<EarningsSnapshot>();
    final b = make((period, {before, asOf}) async =>
        period == EarningsPeriod.thisMonth
            ? pending.future
            : earningsReport(period: period));
    b.setActive(true);
    expect(b.refreshing, true);
    expect(b.snapshot!.period, EarningsPeriod.thisMonth);
    b.select(EarningsPeriod.allTime);
    expect(b.snapshot, isNull);
    await tick();
    expect(b.snapshot!.period, EarningsPeriod.allTime);
    pending.complete(earningsReport());
    await tick();
    expect(b.snapshot!.period, EarningsPeriod.allTime);
    b.dispose();
  });

  test(
      'workspace re-entry retains overview including valid empty provider profile',
      () async {
    final cache = SessionSnapshotCache(currentUserId: () => 'a');
    var fail = false;
    WorkspaceBinding make() => WorkspaceBinding(
        provider: true,
        cache: cache,
        feed: CursorFeed<Map<String, dynamic>>(
            active: false,
            preserveOnRefresh: true,
            initialPage: const CursorPage(items: []),
            loadPage: (_) async => const CursorPage(items: []),
            idOf: (r) => r['booking_id'] as String,
            compare: (_, __) => 0),
        loadOverview: () async {
          if (fail) throw StateError('offline');
          return null;
        });
    final first = make();
    first.setActive(true);
    await tick();
    first.dispose();
    fail = true;
    final second = make();
    second.setActive(true);
    expect(second.loading, false);
    expect(second.refreshing, true);
    await tick();
    expect(second.error, isNull);
    expect(second.refreshError, isNotNull);
    second.dispose();
  });

  testWidgets(
      'availability saved data stays visible read-only while refresh waits and fails',
      (tester) async {
    const saved = ProviderSetupData(
        services: [ProviderServiceItem(id: 's', name: 'Real service')],
        selectedServiceIds: {'s'},
        slots: [],
        unavailableDates: {});
    final pending = Completer<ProviderSetupData>();
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: ConnectedProviderSetupScreen(
            loadDayOffConstraints: (first, last) async =>
                ProviderDayOffConstraints(
                    firstDate: first,
                    lastDate: last,
                    confirmedDates: const {},
                    unavailableDates: const {}),
            initialData: saved,
            load: () => pending.future,
            saveServices: (_) async {
              writes++;
            },
            loadWeeklyHours: () async => weeklyHoursFixture(),
            saveWeeklyHours: (days, expected) async {
              writes++;
              return expected;
            },
            addUnavailableDate: (_) async {},
            removeUnavailableDate: (_) async {})));
    expect(find.text('Loading your availability'), findsNothing);
    expect(find.text('Real service'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull);
    pending.completeError(StateError('offline'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Real service'), findsOneWidget);
    expect(find.text('Retry update'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cached earnings avoids full page loader and exposes refresh failure',
      (tester) async {
    final cache = SessionSnapshotCache(currentUserId: () => earningsActor);
    EarningsBinding make(EarningsLoader load) => EarningsBinding(
        load: load,
        userId: earningsActor,
        currentUserId: () => earningsActor,
        sessionChanges: const Stream.empty(),
        changes: () => const Stream.empty(),
        cache: cache);
    final first =
        make((period, {before, asOf}) async => earningsReport(period: period));
    first.setActive(true);
    await tester.pump();
    first.dispose();
    final pending = Completer<EarningsSnapshot>();
    final b = make((_, {before, asOf}) => pending.future);
    b.setActive(true);
    await tester.pumpWidget(MaterialApp(
        home: EarningsHistoryScreen(
            providerName: '', bookings: const [], binding: b)));
    expect(find.text('Showing saved data · updating…'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Loading earnings'), findsNothing);
    pending.completeError(StateError('offline'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Retry update'), findsOneWidget);
    expect(b.snapshot, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    b.dispose();
  });
}
