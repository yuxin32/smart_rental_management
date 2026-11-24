import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/features/availability/domain/provider_setup.dart';
import 'package:smart_rental_management/owner_provider/services/backend/session_snapshot_cache.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_provider_repository.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

const _actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _other = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

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
  final calls = <({String path, String method, dynamic body})>[];
  var mode = '';
  Map<String, dynamic> state() => {
        'provider_id': mode == 'foreign' ? _other : _actor,
        'revision': List.filled(32, 'a').join(),
        'slots': [],
        'required_intervals': [],
        'required_service_ids': [],
      };
  setUp(() async {
    calls.clear();
    mode = '';
    auth = _Auth();
    cache = SessionSnapshotCache(currentUserId: () => auth.identity);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final content = await utf8.decoder.bind(request).join();
      calls.add((
        path: request.uri.path,
        method: request.method,
        body: content.isEmpty ? null : jsonDecode(content)
      ));
      if (mode == 'session') auth.identity = _other;
      if (mode == 'epoch') {
        cache.bindSession(null);
        cache.bindSession(_actor);
      }
      request.response.headers.contentType = ContentType.json;
      if (mode == 'offline' || mode == 'conflict') {
        request.response.statusCode = mode == 'offline' ? 503 : 409;
        request.response.write(jsonEncode({
              'code': mode == 'conflict' ? 'PT409' : 'PGRST000',
          'message': 'Synthetic unavailable response'
        }));
      } else {
        request.response.write(jsonEncode(state()));
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
  test('each preflight is a fresh own-account RPC with no actor input',
      () async {
    await repo.weeklyState();
    await repo.weeklyState();
    expect(calls.length, 2);
    for (final call in calls) {
      expect(call.path, '/rest/v1/rpc/my_provider_weekly_hours');
      expect(call.method, 'POST');
      expect(call.body ?? {}, isEmpty);
    }
  });
  test('copy is one RPC carrying all weekdays and expected revision', () async {
    final base = await repo.weeklyState();
    calls.clear();
    final lease = cache.lease();
    cache.put('provider:setup', 'old', lease: lease, bytes: 100);
    await repo.replaceWeeklyHours({
      3: [const ProviderWorkingRange(480, 1080)],
      4: [
        const ProviderWorkingRange(540, 720),
        const ProviderWorkingRange(840, 1080)
      ],
    }, base);
    expect(calls.length, 1);
    expect(calls.single.path, '/rest/v1/rpc/replace_my_weekly_hours');
    expect(calls.single.body, {
      'p_expected_revision': base.revision,
      'p_changes': [
        {
          'weekday': 3,
          'slots': [
            {'start_minute': 480, 'end_minute': 1080}
          ]
        },
        {
          'weekday': 4,
          'slots': [
            {'start_minute': 540, 'end_minute': 720},
            {'start_minute': 840, 'end_minute': 1080}
          ]
        },
      ],
    });
    expect(cache.entryCount, 0);
    expect(cache.valid(lease), isFalse);
  });
  test('invalid ranges and foreign expected owner never reach the network',
      () async {
    final base = await repo.weeklyState();
    calls.clear();
    await expectLater(
        repo.replaceWeeklyHours({
          1: [const ProviderWorkingRange(480, 540)]
        }, base),
        throwsArgumentError);
    await expectLater(
        repo.replaceWeeklyHours({8: []}, base), throwsArgumentError);
    final foreign = ProviderWeeklyState(
        providerId: _other,
        revision: base.revision,
        slots: [],
        required: [],
        requiredServices: {});
    await expectLater(
        repo.replaceWeeklyHours({1: []}, foreign), throwsStateError);
    expect(calls, isEmpty);
  });
  for (final scenario in ['session', 'epoch', 'foreign']) {
    test('$scenario preflight is rejected', () async {
      mode = scenario;
      await expectLater(
          repo.weeklyState(),
          throwsA(scenario == 'foreign'
              ? isA<FormatException>()
              : isA<StateError>()));
    });
  }
  for (final scenario in ['offline', 'conflict']) {
    test('$scenario save invalidates cache and is never automatically replayed',
        () async {
      final base = await repo.weeklyState();
      calls.clear();
      cache.put('provider:setup', 'old', lease: cache.lease(), bytes: 100);
      mode = scenario;
      await expectLater(repo.replaceWeeklyHours({1: []}, base),
          throwsA(isA<PostgrestException>()));
      expect(calls.length, 1);
      expect(cache.entryCount, 0);
    });
  }
  test('session changes while saving reject the response', () async {
    final base = await repo.weeklyState();
    mode = 'session';
    await expectLater(repo.replaceWeeklyHours({1: []}, base), throwsStateError);
  });
  test('missing session fails without a network request', () async {
    auth.identity = null;
    await expectLater(repo.weeklyState(), throwsStateError);
    expect(calls, isEmpty);
  });
}
