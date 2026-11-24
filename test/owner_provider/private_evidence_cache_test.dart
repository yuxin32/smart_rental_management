import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/services/backend/authenticated_memory_cache.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_evidence_repository.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_owner_repository.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_provider_repository.dart';

class CacheFixtureAuth extends GoTrueClient {
  CacheFixtureAuth() : super(autoRefreshToken: false);
  String? user = 'owner-a';
  @override
  User? get currentUser => user == null
      ? null
      : User(
          id: user!,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2030-01-01',
        );
}

class CacheFixtureClient extends SupabaseClient {
  CacheFixtureClient(this.fixture, String url)
      : super(
          url,
          'fixture-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
  final CacheFixtureAuth fixture;
  @override
  GoTrueClient get auth => fixture;
}

class StorageFixture {
  late HttpServer server;
  late StreamSubscription<HttpRequest> listener;
  late CacheFixtureClient client;
  late AuthenticatedMemoryCache cache;
  final auth = CacheFixtureAuth();
  int metadataReads = 0, imageReads = 0, catalogueReads = 0;
  bool deny = false;
  bool hidden = false;
  String path = 'booking/before_old.jpg';
  final Uint8List bytes = img.encodeJpg(img.Image(width: 8, height: 8));
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    listener = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.contains('/booking_evidence')) {
        metadataReads++;
        if (deny) {
          request.response.statusCode = 403;
          request.response.write(
            jsonEncode(
              {'code': '42501', 'message': 'fixture access revoked'},
            ),
          );
        } else if (hidden) {
          request.response.write('[]');
        } else {
          request.response.write(
            jsonEncode([
              {
                'booking_id': 'booking',
                'before_path': path,
                'after_path': null,
                'completion_remarks': 'Fixture only',
              }
            ]),
          );
        }
      } else if (request.uri.path.contains('/storage/v1/object/')) {
        imageReads++;
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.add(bytes);
      } else if (request.uri.path.endsWith('/rpc/my_provider_weekly_hours')) {
        request.response.write(jsonEncode({
          'provider_id': auth.user,
          'revision': '00000000000000000000000000000000',
          'slots': [],
          'required_intervals': [],
          'required_service_ids': [],
        }));
      } else if (request.uri.path.contains('/service_type')) {
        catalogueReads++;
        request.response.write(
          jsonEncode([
            {'service_type_id': 'service', 'name': 'Standard cleaning'},
          ]),
        );
      } else {
        request.response.write('[]');
      }
      await request.response.close();
    });
    client = CacheFixtureClient(auth, 'http://127.0.0.1:${server.port}');
    cache = AuthenticatedMemoryCache(currentUserId: () => auth.user);
  }

  Future<void> close() async {
    cache.clear();
    await client.dispose();
    auth.dispose();
    await listener.cancel();
    await server.close(force: true);
  }
}

void main() {
  // These exercise the actual SDK against loopback responses, not real RLS.
  test(
      'reopening evidence downloads once but freshly authorizes every cache hit',
      () async {
    final fixture = StorageFixture();
    await fixture.start();
    addTearDown(fixture.close);
    final repository =
        SupabaseEvidenceRepository(fixture.client, cache: fixture.cache);
    final first = await repository.download(fixture.path);
    final second = await repository.download(fixture.path);
    expect(first, second);
    expect(fixture.imageReads, 1);
    expect(fixture.metadataReads, 2);
    expect(() => first[0] = 1, throwsUnsupportedError);
    expect(fixture.cache.sizeBytes, first.length);
  });

  test('revoked participant access cannot be bypassed with cached photo bytes',
      () async {
    final fixture = StorageFixture();
    await fixture.start();
    addTearDown(fixture.close);
    final repository =
        SupabaseEvidenceRepository(fixture.client, cache: fixture.cache);
    await repository.download(fixture.path);
    fixture.deny = true;
    await expectLater(
      repository.download(fixture.path),
      throwsA(isA<PostgrestException>()),
    );
    expect(fixture.imageReads, 1);
    expect(fixture.metadataReads, 2);
  });

  test('replacement path evicts old bytes and an old URL is no longer served',
      () async {
    final fixture = StorageFixture();
    await fixture.start();
    addTearDown(fixture.close);
    final repository =
        SupabaseEvidenceRepository(fixture.client, cache: fixture.cache);
    final previous = fixture.path;
    await repository.download(previous);
    fixture.path = 'booking/before_new.jpg';
    await repository.forBooking('booking');
    expect(fixture.cache.entryCount, 0);
    await expectLater(repository.download(previous), throwsStateError);
    await repository.download(fixture.path);
    expect(fixture.imageReads, 2);
  });

  test('an RLS-style empty metadata result cannot expose cached bytes',
      () async {
    final fixture = StorageFixture();
    await fixture.start();
    addTearDown(fixture.close);
    final repository =
        SupabaseEvidenceRepository(fixture.client, cache: fixture.cache);
    await repository.download(fixture.path);
    fixture.hidden = true;
    await expectLater(repository.download(fixture.path), throwsStateError);
    expect(fixture.cache.entryCount, 0);
    expect(fixture.imageReads, 1);
  });

  test('different authenticated account re-downloads rather than reusing bytes',
      () async {
    final fixture = StorageFixture();
    await fixture.start();
    addTearDown(fixture.close);
    final repository =
        SupabaseEvidenceRepository(fixture.client, cache: fixture.cache);
    await repository.download(fixture.path);
    fixture.auth.user = 'owner-b';
    final bytes = await repository.download(fixture.path);
    expect(img.decodeJpg(bytes), isNotNull);
    expect(fixture.imageReads, 2);
  });

  test(
      'shared service catalogue is immutable, cached and explicitly refreshable',
      () async {
    final fixture = StorageFixture();
    await fixture.start();
    addTearDown(fixture.close);
    final owner = SupabaseOwnerRepository(fixture.client, cache: fixture.cache);
    final provider =
        SupabaseProviderRepository(fixture.client, cache: fixture.cache);
    final rows = await owner.serviceTypes();
    await owner.serviceTypes();
    await provider.loadSetup();
    expect(fixture.catalogueReads, 1);
    expect(() => rows.first['name'] = 'changed', throwsUnsupportedError);
    expect(() => rows.add({}), throwsUnsupportedError);
    await owner.serviceTypes(force: true);
    expect(fixture.catalogueReads, 2);
  });
}
