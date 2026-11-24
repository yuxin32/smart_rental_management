import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/services/backend/provider_profile_snapshot.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_provider_repository.dart';
import 'support/profile_fixture.dart';
import 'package:smart_rental_management/owner_provider/services/backend/session_snapshot_cache.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _Auth extends GoTrueClient {
  _Auth()
      : super(url: 'https://fixture.invalid/auth/v1', autoRefreshToken: false);
  String? identity = profileActor;
  @override
  User? get currentUser => identity == null
      ? null
      : User(
          id: identity!,
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01');
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
  late _Auth auth;
  late _Client client;
  late HttpServer server;
  late SupabaseProviderRepository repo;
  var mode = 'normal';
  final calls = <String>[];
  Map? lastBody;
  const draft = ProviderProfileDraft(
      name: 'Saved',
      bio: 'Bio',
      phone: '',
      area: 'Area',
      origin: 'Private',
      hourly: 55.25,
      daily: 300.5,
      avatar: 1,
      sharePhone: false,
      services: {profileService});
  setUp(() async {
    auth = _Auth();
    mode = 'normal';
    calls.clear();
    lastBody = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      calls.add(req.uri.path);
      final body = await utf8.decoder.bind(req).join();
      if (body.isNotEmpty && jsonDecode(body) is Map)
        lastBody = jsonDecode(body) as Map;
      req.response.headers.contentType = ContentType.json;
      final response = profileFixture();
      if (mode == 'session') auth.identity = 'different';
      if (mode == 'wrong-id') response['provider_id'] = 'different';
      if (mode == 'conflict') {
        req.response.statusCode = 409;
        req.response
            .write(jsonEncode({'code': '40001', 'message': 'Profile changed'}));
      } else {
        req.response.write(jsonEncode(response));
      }
      await req.response.close();
    });
    client = _Client('http://127.0.0.1:${server.port}', auth);
    repo = SupabaseProviderRepository(client);
  });
  tearDown(() async {
    await client.dispose();
    auth.dispose();
    await server.close(force: true);
  });
  test(
      'profile read uses single own-only snapshot RPC not demo or raw broad queries',
      () async {
    final result = await repo.myProfile();
    expect(result.id, profileActor);
    expect(calls, ['/rest/v1/rpc/my_provider_profile_with_location']);
    expect(lastBody, anyOf(isNull, isEmpty));
  });
  test(
      'atomic save transmits allowlisted values with revision and original contact only',
      () async {
    await repo.saveMyProfile(draft, profileReport());
    expect(calls, ['/rest/v1/rpc/save_my_provider_profile']);
    expect(
        lastBody!.keys,
        unorderedEquals(
            ['p_input', 'p_expected_revision', 'p_expected_contact']));
    expect(lastBody!['p_expected_revision'], 1);
    expect(lastBody!['p_expected_contact'], '+60 12-345 6789');
    expect(lastBody!['p_input'], draft.json);
  });
  test('wrong draft owner and no session fail before a write', () async {
    auth.identity = 'other';
    await expectLater(
        repo.saveMyProfile(draft, profileReport()), throwsStateError);
    auth.identity = null;
    await expectLater(repo.myProfile(), throwsStateError);
    expect(calls, isEmpty);
  });
  test('late session change or wrong response identity rejected', () async {
    mode = 'session';
    await expectLater(repo.myProfile(), throwsStateError);
    auth.identity = profileActor;
    mode = 'wrong-id';
    await expectLater(repo.myProfile(), throwsFormatException);
  });
  test('revision conflicts are surfaced without a silent retry overwrite',
      () async {
    mode = 'conflict';
    await expectLater(repo.saveMyProfile(draft, profileReport()),
        throwsA(isA<PostgrestException>()));
    expect(calls.length, 1);
  });
  test('real save path invalidates snapshots on confirmation and on rejection',
      () async {
    final cache = SessionSnapshotCache(currentUserId: () => auth.identity);
    repo = SupabaseProviderRepository(client, snapshots: cache);
    for (final conflict in [false, true]) {
      mode = conflict ? 'conflict' : 'normal';
      final oldLease = cache.lease();
      cache.put('profile:self:v1', profileReport(),
          lease: oldLease, bytes: 512);
      if (conflict) {
        await expectLater(repo.saveMyProfile(draft, profileReport()),
            throwsA(isA<PostgrestException>()));
      } else {
        await repo.saveMyProfile(draft, profileReport());
      }
      expect(cache.entryCount, 0);
      cache.put('late-read', profileReport(), lease: oldLease, bytes: 512);
      expect(cache.entryCount, 0);
    }
    expect(calls.length, 2); // No automatic write retries.
  });
}
