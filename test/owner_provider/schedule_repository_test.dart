import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/services/backend/cursor_feed.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_booking_repository.dart';
import 'package:smart_rental_management/owner_provider/services/backend/session_snapshot_cache.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

const actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
String id(int n) => 'bbbbbbbb-bbbb-4bbb-8bbb-${n.toString().padLeft(12, '0')}';

class _Auth extends GoTrueClient {
  _Auth()
      : super(url: 'https://fixture.invalid/auth/v1', autoRefreshToken: false);
  String identity = actor;
  @override
  User? get currentUser => User(
      id: identity,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2030-01-01');
}

class _Client extends SupabaseClient {
  _Client(String url, this.fixture)
      : super(url, 'sb_publishable_synthetic_fixture',
            authOptions: const AuthClientOptions(autoRefreshToken: false));
  final _Auth fixture;
  @override
  GoTrueClient get auth => fixture;
}

void main() {
  _NetworkBinding();
  final start = DateTime.utc(2030, 1, 6, 16);
  final end = start.add(const Duration(days: 7));
  late HttpServer server;
  late _Client client;
  late _Auth auth;
  late SupabaseBookingRepository repository;
  var mode = 'normal';
  var calls = <Uri>[];
  List<Map<String, dynamic>> cards = [];
  setUp(() async {
    mode = 'normal';
    calls = [];
    auth = _Auth();
    cards = List.generate(
        20,
        (i) => {
              'booking_id': id(i),
              'owner_id': actor,
              'provider_id': id(99),
              'current_status': 'Accepted',
              'requested_start_at': '2030-01-07T02:00:00Z',
              'requested_end_at': '2030-01-07T04:00:00Z',
            });
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/rest/v1/booking') {
        if (mode == 'session-change') auth.identity = id(100);
        if (mode == 'empty') {
          request.response.write('[]');
        } else {
          request.response.write(jsonEncode(List.generate(
              21,
              (i) => {
                    'booking_id': id(i),
                    'created_at': '2029-01-01T00:00:00.123456Z',
                  })));
        }
      } else if (request.uri.path == '/rest/v1/rpc/booking_cards_by_ids') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect((body['p_ids'] as List).length, 20);
        expect(body['p_ids'], isNot(contains(id(20))));
        request.response.write(jsonEncode(cards));
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });
    client = _Client('http://127.0.0.1:${server.port}', auth);
    repository = SupabaseBookingRepository(client);
  });
  tearDown(() async {
    await client.dispose();
    auth.dispose();
    await server.close(force: true);
  });

  test(
      'week overlap query reads only 21 IDs then safe cards for 20; keeps old created bookings',
      () async {
    final page = await repository.schedulePage(startUtc: start, endUtc: end);
    expect(page.items.length, 20);
    expect(page.next!.timestamp, '2029-01-01T00:00:00.123456Z');
    expect(page.next!.id, id(19));
    final query = calls.first.queryParameters;
    expect(query['select'], 'booking_id,created_at');
    expect(query['limit'], '21');
    expect(query['requested_start_at'], 'lt.${end.toIso8601String()}');
    expect(query['requested_end_at'], 'gt.${start.toIso8601String()}');
    expect(query['created_at'], isNull);
    expect(query['current_status'], contains('Accepted'));
    expect(calls.length, 2);
  });
  test('cursor retains PostgreSQL precision and stable UUID tie-breaker',
      () async {
    await repository.schedulePage(
        startUtc: start,
        endUtc: end,
        before: PageCursor('2029-01-01T00:00:00.123456Z', id(19)));
    expect(calls.first.queryParameters['or'],
        contains('created_at.eq.2029-01-01T00:00:00.123456Z'));
    expect(
        calls.first.queryParameters['or'], contains('booking_id.lt.${id(19)}'));
  });
  test('invalid interval/cursor fail before network access', () async {
    await expectLater(
        repository.schedulePage(
            startUtc: start, endUtc: start.add(const Duration(days: 43))),
        throwsArgumentError);
    await expectLater(
        repository.schedulePage(startUtc: start.toLocal(), endUtc: end),
        throwsArgumentError);
    await expectLater(
        repository.schedulePage(
            startUtc: start,
            endUtc: end,
            before: const PageCursor('bad.or.query', 'bad-id')),
        throwsArgumentError);
    expect(calls, isEmpty);
  });
  test('session change stops before the second query', () async {
    mode = 'session-change';
    await expectLater(repository.schedulePage(startUtc: start, endUtc: end),
        throwsStateError);
    expect(calls.length, 1);
  });
  test('unexpected card ID or participant cannot enter calendar', () async {
    cards = [
      {...cards.first, 'owner_id': id(98), 'provider_id': id(99)}
    ];
    await expectLater(repository.schedulePage(startUtc: start, endUtc: end),
        throwsFormatException);
    cards = [
      {...cards.first, 'owner_id': actor, 'booking_id': id(444)}
    ];
    await expectLater(repository.schedulePage(startUtc: start, endUtc: end),
        throwsFormatException);
  });
  test(
      'rescheduled, cancelled and half-open boundary rows do not appear occupied',
      () async {
    cards = [
      {...cards[0], 'current_status': 'Cancelled'},
      {
        ...cards[1],
        'requested_start_at': end.toIso8601String(),
        'requested_end_at': end.add(const Duration(hours: 2)).toIso8601String()
      },
      {
        ...cards[2],
        'requested_start_at':
            start.subtract(const Duration(hours: 2)).toIso8601String(),
        'requested_end_at': start.toIso8601String()
      },
      {
        ...cards[3],
        'requested_start_at':
            start.subtract(const Duration(hours: 1)).toIso8601String(),
        'requested_end_at':
            start.add(const Duration(hours: 1)).toIso8601String()
      },
    ];
    final page = await repository.schedulePage(startUtc: start, endUtc: end);
    expect(page.items.map((row) => row['booking_id']), [id(3)]);
    expect(page.hasMore, true);
  });
  test('empty week performs no redundant card request', () async {
    mode = 'empty';
    final page = await repository.schedulePage(startUtc: start, endUtc: end);
    expect(page.items, isEmpty);
    expect(page.hasMore, false);
    expect(calls.length, 1);
  });
  test(
      'real repository seeds only same role and exact week, preserves partial cursor',
      () async {
    cards = cards
        .map((row) => {...row, 'created_at': '2029-01-01T00:00:00.123456Z'})
        .toList();
    final cache = SessionSnapshotCache(currentUserId: () => auth.identity);
    repository = SupabaseBookingRepository(client, snapshots: cache);
    final first = repository.openScheduleFeed(
        provider: false, startUtc: start, endUtc: end);
    await first
        .loadPage(null); // Exercise real HTTP read without opening Realtime.
    first.dispose();
    final restored = repository.openScheduleFeed(
        provider: false, startUtc: start, endUtc: end);
    expect(restored.items.length, 20);
    expect(restored.hasSnapshot, true);
    expect(restored.hasMore, true); // Cached head is NOT a complete calendar.
    final another = repository.openScheduleFeed(
        provider: false,
        startUtc: start.add(const Duration(days: 7)),
        endUtc: end.add(const Duration(days: 7)));
    final otherRole = repository.openScheduleFeed(
        provider: true, startUtc: start, endUtc: end);
    expect(another.hasSnapshot, false);
    expect(otherRole.hasSnapshot, false);
    expect(calls.length, 2); // Peeking did not issue extra requests.
    restored.dispose();
    another.dispose();
    otherRole.dispose();
  });
}
