import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_provider_repository.dart';
import 'package:smart_rental_management/owner_provider/services/backend/session_snapshot_cache.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

const _actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
String _id(int value) =>
    'bbbbbbbb-bbbb-4bbb-8bbb-${value.toString().padLeft(12, '0')}';

class _Auth extends GoTrueClient {
  _Auth()
      : super(url: 'https://fixture.invalid/auth/v1', autoRefreshToken: false);
  String? identity = _actor;
  @override
  User? get currentUser => identity == null
      ? null
      : User(
          id: identity!,
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
  late HttpServer server;
  late _Auth auth;
  late _Client client;
  late SessionSnapshotCache cache;
  late SupabaseProviderRepository repo;
  final first = DateTime(2030, 1, 1), last = DateTime(2030, 1, 31);
  final now = DateTime.utc(2030, 1, 1);
  final calls = <Uri>[];
  var mode = '';
  var bookings = <Map<String, dynamic>>[];
  Map<String, dynamic> booking(int number) => {
        'booking_id': _id(number),
        'provider_id': _actor,
        'current_status': number == 1 ? 'Accepted' : 'In Progress',
        'requested_start_at': '2030-01-0${number + 5}T18:30:00Z',
        'requested_end_at': '2030-01-0${number + 5}T20:30:00Z',
      };
  setUp(() async {
    calls.clear();
    mode = '';
    bookings = [booking(1), booking(2)];
    auth = _Auth();
    cache = SessionSnapshotCache(currentUserId: () => auth.identity);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      if (request.method != 'GET')
        throw StateError('Read-only check must not write.');
      if (request.uri.path == '/rest/v1/booking') {
        if (mode == 'session') auth.identity = _id(99);
        if (mode == 'epoch') {
          cache.bindSession(null);
          cache.bindSession(_actor);
        }
        if (mode == 'offline') {
          request.response.statusCode = 503;
          request.response.write(jsonEncode({'message': 'offline'}));
        } else {
          final after = request.uri.queryParameters['booking_id']?.substring(3);
          // Deliberately cap each response at one row. A short page is not EOF.
          final rows = bookings
              .where((row) =>
                  after == null ||
                  (row['booking_id'] as String).compareTo(after) > 0)
              .take(1)
              .toList();
          if (mode == 'duplicate' && after != null)
            rows
              ..clear()
              ..add(bookings.first);
          if (mode == 'foreign' && rows.isNotEmpty)
            rows[0] = {...rows[0], 'provider_id': _id(99)};
          if (mode == 'pending' && rows.isNotEmpty)
            rows[0] = {...rows[0], 'current_status': 'Pending'};
          if (mode == 'zone' && rows.isNotEmpty)
            rows[0] = {...rows[0], 'requested_start_at': '2030-01-06T18:30:00'};
          request.response.write(jsonEncode(rows));
        }
      } else if (request.uri.path == '/rest/v1/provider_unavailable_date') {
        request.response.headers
            .set('content-range', mode == 'truncated' ? '0-0/2' : '0-0/1');
        request.response.write(jsonEncode([
          {'provider_id': _actor, 'unavailable_on': '2030-01-09'}
        ]));
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });
    client = _Client('http://127.0.0.1:${server.port}', auth);
    repo = SupabaseProviderRepository(client, snapshots: cache);
  });
  tearDown(() async {
    await client.dispose();
    auth.dispose();
    await server.close(force: true);
  });

  test(
      'own minimal paginated rows protect MYT dates; existing day-off completeness is checked',
      () async {
    final dates = await repo.dayOffConstraints(first, last, now: now);
    expect(dates.confirmedDates, {'2030-01-07', '2030-01-08'});
    expect(dates.unavailableDates, {'2030-01-09'});
    for (final day in [7, 8, 9]) {
      expect(dates.allows(DateTime(2030, 1, day)), isFalse);
    }
    expect(dates.allows(DateTime(2030, 1, 10)), isTrue);
    expect(dates.allows(DateTime(2029, 12, 31)), isFalse);
    expect(dates.allows(DateTime(2030, 2, 1)), isFalse);
    expect(calls.length, 4); // Two capped pages, empty terminal page, days off.
    for (final uri in calls) {
      expect(uri.queryParameters['provider_id'], 'eq.$_actor');
    }
    final query = calls.first.queryParameters;
    expect(query['select'],
        'booking_id,provider_id,current_status,requested_start_at,requested_end_at');
    expect(query['current_status'], 'in.("Accepted","In Progress")');
    expect(query['requested_end_at'], 'gt.${now.toIso8601String()}');
    expect(query['requested_start_at'], 'lt.2030-01-31T16:00:00.000Z');
    expect(calls[1].queryParameters['booking_id'], 'gt.${_id(1)}');
    expect(cache.entryCount, 0); // Not a cache that can allow stale selections.
  });
  test('every opening queries fresh constraints', () async {
    expect(
        (await repo.dayOffConstraints(first, last, now: now))
            .confirmedDates
            .length,
        2);
    bookings = [];
    expect((await repo.dayOffConstraints(first, last, now: now)).confirmedDates,
        isEmpty);
    expect(calls.where((uri) => uri.path.endsWith('/booking')).length, 4);
  });
  for (final scenario in ['foreign', 'pending', 'zone', 'duplicate']) {
    test('$scenario response fails closed instead of showing selectable dates',
        () async {
      mode = scenario;
      await expectLater(
          repo.dayOffConstraints(first, last, now: now), throwsFormatException);
    });
  }
  for (final scenario in ['session', 'epoch', 'truncated']) {
    test('$scenario response rejects the constraint snapshot', () async {
      mode = scenario;
      await expectLater(
          repo.dayOffConstraints(first, last, now: now), throwsStateError);
    });
  }
  test('network failure does not return an empty available-date set', () async {
    mode = 'offline';
    await expectLater(repo.dayOffConstraints(first, last, now: now),
        throwsA(isA<PostgrestException>()));
  });
  test('missing session and unbounded range fail before a request', () async {
    await expectLater(repo.dayOffConstraints(first, DateTime(2035), now: now),
        throwsArgumentError);
    auth.identity = null;
    await expectLater(
        repo.dayOffConstraints(first, last, now: now), throwsStateError);
    expect(calls, isEmpty);
  });
}
