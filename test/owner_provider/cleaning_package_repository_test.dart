import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/features/availability/domain/cleaning_package.dart';
import 'package:smart_rental_management/owner_provider/services/backend/cleaning_package_repository.dart';
import 'package:smart_rental_management/owner_provider/services/backend/session_snapshot_cache.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_booking_repository.dart';

const _actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _service = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _package = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _property = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _token = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _booking = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
final _start = DateTime.utc(2030, 1, 7, 1);
final _end = _start.add(const Duration(hours: 3));

class _Auth extends GoTrueClient {
  _Auth()
    : super(url: 'https://fixture.invalid/auth/v1', autoRefreshToken: false);
  String? identity = _actor;
  final events = StreamController<AuthState>.broadcast(sync: true);
  @override
  Stream<AuthState> get onAuthStateChange => events.stream;
  @override
  User? get currentUser => identity == null
      ? null
      : User(
          id: identity!,
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2030-01-01',
        );
}

class _Client extends SupabaseClient {
  _Client(this.fixture, http.Client transport)
    : super(
        'https://fixture.invalid',
        'sb_publishable_synthetic_fixture',
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
  final _Auth fixture;
  @override
  GoTrueClient get auth => fixture;
}

Map<String, dynamic> _row({int revision = 3}) => {
  'package_id': _package,
  'provider_id': _actor,
  'service_type_id': _service,
  'duration_minutes': 180,
  'cleaner_count': 2,
  'total_price': 125.50,
  'package_scope': 'Floors and bathrooms',
  'enabled': true,
  'revision': revision,
};

Map<String, dynamic> _match() => {
  'provider_id': _actor,
  'service_area': 'Kuala Lumpur',
  'bio': null,
  'hourly_rate': null,
  'daily_rate': null,
  'rating_average': null,
  'completed_job_count': 0,
  'full_name': 'Provider',
  'distance_km': null,
  'active_job_count': 0,
  'package_id': _package,
  'package_revision': 3,
  'cleaner_count': 2,
  'duration_minutes': 180,
  'package_scope': 'Floors and bathrooms',
  'total_price': 125.50,
  'quote_basis': 'package',
  'quoted_amount': 125.50,
};

CleaningPackageDraft _draft({
  int duration = 180,
  int crew = 2,
  num price = 125.50,
}) => CleaningPackageDraft(
  serviceTypeId: _service,
  durationMinutes: duration,
  cleanerCount: crew,
  totalPrice: price,
  scope: '  Floors and bathrooms  ',
);

void main() {
  late _Auth auth;
  late _Client client;
  late SessionSnapshotCache snapshots;
  late CleaningPackageRepository repo;
  late MockClient transport;
  final calls = <http.Request>[];
  var mode = '';
  Completer<void>? readStarted, releaseRead;

  setUp(() {
    mode = '';
    calls.clear();
    readStarted = null;
    releaseRead = null;
    auth = _Auth();
    snapshots = SessionSnapshotCache(currentUserId: () => auth.identity);
    transport = MockClient((request) async {
      calls.add(request);
      if (mode == 'dropped') {
        throw http.ClientException('Synthetic dropped connection');
      }
      if (mode == 'session') auth.identity = _property;
      if (mode == 'epoch') {
        snapshots.bindSession(null);
        snapshots.bindSession(_actor);
      }
      if (mode == 'authEpoch') {
        auth.identity = null;
        auth.events.add(AuthState(AuthChangeEvent.signedOut, null));
        auth.identity = _actor;
      }
      if (mode == 'conflict' || mode == 'offline') {
        return http.Response(
          jsonEncode({
            'code': mode == 'conflict' ? 'PT409' : 'PGRST000',
            'message': 'Synthetic failure',
          }),
          mode == 'conflict' ? 409 : 503,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map? ?? <String, dynamic>{};
      dynamic data;
      switch (request.url.path.split('/').last) {
        case 'booking':
          data = [];
        case 'my_cleaning_packages':
          if (releaseRead != null) {
            readStarted!.complete();
            await releaseRead!.future;
          }
          data = mode == 'empty'
              ? []
              : mode == 'shape'
              ? {}
              : [
                  {..._row(), if (mode == 'foreign') 'provider_id': _property},
                  if (mode == 'duplicate') _row(),
                ];
        case 'save_my_cleaning_package':
          expect(snapshots.entryCount, 0);
          data = {
            ..._row(revision: 4),
            'duration_minutes': body['p_duration_minutes'],
            'cleaner_count': body['p_cleaner_count'],
            'total_price': body['p_total_price'],
            'package_scope': body['p_package_scope'],
            'enabled': body['p_enabled'],
            if (mode == 'wrongPrice') 'total_price': 1,
            if (mode == 'foreign') 'provider_id': _property,
            if (mode == 'staleResponse') 'revision': 3,
          };
        case 'find_package_provider_matches':
          data = {
            'location_required': false,
            'area_name': 'Kuala Lumpur',
            'current': [
              {
                ..._match(),
                if (mode == 'wrongCrew') 'cleaner_count': 1,
                if (mode == 'newRevision') 'package_revision': 4,
              },
            ],
            'alternatives': [
              {
                ..._match(),
                'start_at': _start
                    .add(const Duration(days: 1))
                    .toIso8601String(),
                'end_at': _end.add(const Duration(days: 1)).toIso8601String(),
              },
            ],
          };
        case 'create_pending_package_booking':
          data = mode == 'rejected'
              ? {'created': false, 'reason': 'package_changed'}
              : {
                  'created': true,
                  'booking_id': _booking,
                  'reused': mode == 'reused',
                  'quoted_amount': 125.50,
                  'quote_basis': 'package',
                  'quote_currency': 'MYR',
                };
        default:
          throw StateError('Unexpected RPC ${request.url}');
      }
      return http.Response(
        jsonEncode(data),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    client = _Client(auth, transport);
    repo = CleaningPackageRepository(client, snapshots: snapshots);
  });
  tearDown(() async {
    repo.dispose();
    await client.dispose();
    await auth.events.close();
    auth.dispose();
    transport.close();
  });

  Future<dynamic> search() => repo.findPackageMatches(
    propertyId: _property,
    serviceTypeId: _service,
    start: _start,
    end: _end,
    cleanerCount: 2,
  );
  Future<dynamic> create({
    int? revision,
    DateTime? start,
    DateTime? end,
    String basis = 'package',
    num amount = 125.50,
    String token = _token,
    String instructions = '  Please ring  ',
  }) => repo.createPackagePending(
    clientRequestId: token,
    providerId: _actor,
    propertyId: _property,
    serviceTypeId: _service,
    start: start ?? _start,
    end: end ?? _end,
    expectedAmount: amount,
    expectedBasis: basis,
    packageId: _package,
    expectedPackageRevision: revision,
    instructions: instructions,
  );

  test(
    'own reads are fresh RPCs without actor input and immutable results',
    () async {
      final rows = await repo.myPackages();
      await repo.myPackages();
      expect(rows.single.providerId, _actor);
      expect(() => rows.clear(), throwsUnsupportedError);
      expect(calls.length, 2);
      for (final call in calls) {
        expect(call.method, 'POST');
        expect(call.url.path, '/rest/v1/rpc/my_cleaning_packages');
        expect(jsonDecode(call.body) ?? {}, isEmpty);
      }
    },
  );
  test('empty own packages are valid and never seeded', () async {
    mode = 'empty';
    expect(await repo.myPackages(), isEmpty);
    expect(calls.length, 1);
  });
  test(
    'create sends revision zero, no actor and exact total without multiplying crew',
    () async {
      final lease = snapshots.lease();
      snapshots.put('provider:setup', 'old', lease: lease, bytes: 100);
      final saved = await repo.savePackage(_draft());
      expect(saved.totalPrice, 125.50);
      expect(calls.length, 1);
      expect(jsonDecode(calls.single.body), {
        'p_service_type_id': _service,
        'p_duration_minutes': 180,
        'p_cleaner_count': 2,
        'p_total_price': 125.50,
        'p_package_scope': 'Floors and bathrooms',
        'p_enabled': true,
        'p_expected_revision': 0,
        'p_package_id': null,
      });
      expect(snapshots.entryCount, 0);
      expect(snapshots.valid(lease), isFalse);
    },
  );
  test(
    'edit changes duration and crew while preserving id and expected revision',
    () async {
      final base = CleaningPackage.parse(_row(), _actor);
      final result = await repo.savePackage(
        _draft(duration: 240, crew: 3),
        base: base,
      );
      expect(result.id, base.id);
      expect(result.durationMinutes, 240);
      expect(result.cleanerCount, 3);
      final body = jsonDecode(calls.single.body);
      expect(body['p_package_id'], _package);
      expect(body['p_expected_revision'], 3);
      expect(body['p_duration_minutes'], 240);
      expect(body['p_cleaner_count'], 3);
    },
  );
  test('bad draft and foreign base fail before network', () async {
    await expectLater(
      repo.savePackage(_draft(price: double.nan)),
      throwsArgumentError,
    );
    final base = CleaningPackage.parse({
      ..._row(),
      'provider_id': _property,
    }, _property);
    await expectLater(repo.savePackage(_draft(), base: base), throwsStateError);
    expect(calls, isEmpty);
  });
  for (final scenario in ['foreign', 'duplicate', 'shape']) {
    test('$scenario own response fails closed and clears snapshots', () async {
      snapshots.put(
        'provider:setup',
        'old',
        lease: snapshots.lease(),
        bytes: 100,
      );
      mode = scenario;
      await expectLater(repo.myPackages(), throwsFormatException);
      expect(snapshots.entryCount, 0);
    });
  }
  for (final scenario in ['session', 'epoch', 'authEpoch']) {
    test('$scenario read is rejected', () async {
      mode = scenario;
      await expectLater(repo.myPackages(), throwsStateError);
    });
    test('$scenario write response is rejected', () async {
      mode = scenario;
      await expectLater(repo.savePackage(_draft()), throwsStateError);
      expect(snapshots.entryCount, 0);
    });
  }
  test(
    'same-account logout race is rejected without an injected cache',
    () async {
      repo = CleaningPackageRepository(client);
      mode = 'authEpoch';
      await expectLater(repo.myPackages(), throwsStateError);
    },
  );
  for (final scenario in ['conflict', 'offline']) {
    test(
      '$scenario save invalidates before/after and never retries automatically',
      () async {
        snapshots.put(
          'provider:setup',
          'old',
          lease: snapshots.lease(),
          bytes: 100,
        );
        mode = scenario;
        await expectLater(
          repo.savePackage(_draft()),
          throwsA(isA<PostgrestException>()),
        );
        expect(calls.length, 1);
        expect(snapshots.entryCount, 0);
      },
    );
  }
  test('unchanged revision in successful save response is rejected', () async {
    mode = 'staleResponse';
    await expectLater(
      repo.savePackage(_draft(), base: CleaningPackage.parse(_row(), _actor)),
      throwsFormatException,
    );
  });
  test(
    'saved fields must match submitted price and disabling is supported',
    () async {
      const disabled = CleaningPackageDraft(
        serviceTypeId: _service,
        durationMinutes: 180,
        cleanerCount: 2,
        totalPrice: 125.50,
        scope: 'Floors and bathrooms',
        enabled: false,
      );
      final result = await repo.savePackage(
        disabled,
        base: CleaningPackage.parse(_row(), _actor),
      );
      expect(result.enabled, isFalse);
      expect(jsonDecode(calls.single.body)['p_enabled'], isFalse);
      mode = 'wrongPrice';
      await expectLater(repo.savePackage(_draft()), throwsFormatException);
    },
  );
  test('pre-write read cannot return after a save', () async {
    readStarted = Completer<void>();
    releaseRead = Completer<void>();
    final pending = repo.myPackages();
    await readStarted!.future;
    final checkPending = expectLater(pending, throwsStateError);
    await repo.savePackage(_draft());
    releaseRead!.complete();
    await checkPending;
  });
  test(
    'Owner search uses exact crew/UTC interval and supports no hourly rates',
    () async {
      final result = await search();
      expect(result.current.single.quoteBasis, 'package');
      expect(result.current.single.hourlyRate, isNull);
      expect(result.current.single.quotedAmount, 125.50);
      expect(
        result.alternatives.single.end.difference(
          result.alternatives.single.start,
        ),
        const Duration(hours: 3),
      );
      expect(jsonDecode(calls.single.body), {
        'p_property_id': _property,
        'p_service_type_id': _service,
        'p_start_at': _start.toIso8601String(),
        'p_end_at': _end.toIso8601String(),
        'p_cleaner_count': 2,
      });
    },
  );
  test('wrong crew in search response fails closed', () async {
    mode = 'wrongCrew';
    await expectLater(search(), throwsFormatException);
  });
  test(
    'create sends explicit package revision and stable idempotency token',
    () async {
      final result = await create(revision: 3);
      expect(result.bookingId, _booking);
      final body = jsonDecode(calls.single.body);
      expect(body['p_client_request_id'], _token);
      expect(body['p_package_id'], _package);
      expect(body['p_expected_package_revision'], 3);
      expect(body['p_expected_amount'], 125.50);
      expect(body['p_instructions'], 'Please ring');
      expect(body.containsKey('p_expected_basis'), isFalse);
      expect(snapshots.entryCount, 0);
    },
  );
  test(
    'legacy callback uses exact-context search revision for create',
    () async {
      await search();
      await create();
      expect(jsonDecode(calls.last.body)['p_expected_package_revision'], 3);
    },
  );
  test(
    'alternative package retains revision at the alternative interval',
    () async {
      await search();
      await create(
        start: _start.add(const Duration(days: 1)),
        end: _end.add(const Duration(days: 1)),
      );
      expect(jsonDecode(calls.last.body)['p_expected_package_revision'], 3);
    },
  );
  test(
    'missing quote, changed interval, or invalidated quote cannot create',
    () async {
      await expectLater(create(), throwsStateError);
      await search();
      await expectLater(
        create(
          start: _start.add(const Duration(hours: 1)),
          end: _end.add(const Duration(hours: 1)),
        ),
        throwsStateError,
      );
      snapshots.clear();
      await expectLater(create(), throwsStateError);
      expect(calls.length, 1);
    },
  );
  test('non-package or nonfinite create price fails before request', () async {
    await expectLater(
      create(revision: 3, basis: 'hourly'),
      throwsArgumentError,
    );
    await expectLater(
      create(revision: 3, amount: double.infinity),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });
  for (final failure in ['offline', 'dropped']) {
    test(
      '$failure create retries unchanged token and revision after absent lookup',
      () async {
        await search();
        mode = failure;
        await expectLater(
          create(),
          throwsA(
            failure == 'offline'
                ? isA<PostgrestException>()
                : isA<http.ClientException>(),
          ),
        );
        expect(
          calls.length,
          2,
        ); // Never automatically replay an uncertain write.
        final attempted = jsonDecode(calls.last.body);
        expect(snapshots.entryCount, 0);
        mode = '';
        final existing = await SupabaseBookingRepository(
          client,
        ).createdBookingIdForToken(_token);
        expect(existing, isNull);
        expect(calls.last.url.path, '/rest/v1/booking');
        final created = await create();
        expect(created.bookingId, _booking);
        expect(jsonDecode(calls.last.body), attempted);
        expect(calls.length, 4);
      },
    );
  }
  test(
    'uncertain token preserves original revision even after a fresh search',
    () async {
      await search();
      mode = 'offline';
      await expectLater(create(), throwsA(isA<PostgrestException>()));
      mode = 'newRevision';
      await search();
      mode = 'reused';
      final result = await create();
      expect(result.reused, isTrue);
      expect(jsonDecode(calls.last.body)['p_expected_package_revision'], 3);
    },
  );
  test(
    'uncertain token rejects changed details and explicit revision before sending',
    () async {
      await search();
      mode = 'offline';
      await expectLater(create(), throwsA(isA<PostgrestException>()));
      final sent = calls.length;
      mode = '';
      await expectLater(create(revision: 4), throwsStateError);
      await expectLater(
        create(instructions: 'Different instructions'),
        throwsStateError,
      );
      await expectLater(create(amount: 150), throwsStateError);
      await expectLater(
        create(
          start: _start.add(const Duration(hours: 1)),
          end: _end.add(const Duration(hours: 1)),
        ),
        throwsStateError,
      );
      await expectLater(create(token: _booking), throwsStateError);
      expect(calls.length, sent);
    },
  );
  test(
    'attempt revisions survive snapshot invalidation but clear on idle logout',
    () async {
      await search();
      mode = 'offline';
      await expectLater(create(), throwsA(isA<PostgrestException>()));
      snapshots.clear();
      mode = '';
      auth.identity = null;
      auth.events.add(AuthState(AuthChangeEvent.signedOut, null));
      auth.identity = _actor;
      await expectLater(create(), throwsStateError);
      expect(calls.length, 2);
    },
  );
  test('attempt revisions cannot cross account switches', () async {
    await search();
    mode = 'offline';
    await expectLater(create(), throwsA(isA<PostgrestException>()));
    mode = '';
    auth.identity = _property;
    await expectLater(create(), throwsStateError);
    auth.identity = _actor;
    await expectLater(create(), throwsStateError);
    expect(calls.length, 2);
  });
  test(
    'pending attempts are bounded and never supply another token revision',
    () async {
      mode = 'offline';
      String token(int number) =>
          'eeeeeeee-eeee-4eee-8eee-${number.toString().padLeft(12, '0')}';
      for (var index = 0; index < 33; index++) {
        await expectLater(
          create(token: token(index), revision: 3),
          throwsA(isA<PostgrestException>()),
        );
      }
      mode = '';
      await expectLater(create(token: token(0)), throwsStateError);
      await create(token: token(32));
      expect(jsonDecode(calls.last.body)['p_expected_package_revision'], 3);
    },
  );
  test('unauthenticated calls do not hit network', () async {
    auth.identity = null;
    await expectLater(repo.myPackages(), throwsStateError);
    await expectLater(repo.savePackage(_draft()), throwsStateError);
    await expectLater(search(), throwsStateError);
    await expectLater(create(revision: 3), throwsStateError);
    expect(calls, isEmpty);
  });
  test(
    'dispose cancels pending attempt listener and rejects further work',
    () async {
      await search();
      mode = 'offline';
      await expectLater(create(), throwsA(isA<PostgrestException>()));
      expect(auth.events.hasListener, isTrue);
      repo.dispose();
      repo.dispose();
      await Future<void>.value();
      expect(auth.events.hasListener, isFalse);
      mode = '';
      await expectLater(repo.myPackages(), throwsStateError);
      await expectLater(search(), throwsStateError);
      await expectLater(repo.savePackage(_draft()), throwsStateError);
      await expectLater(create(), throwsStateError);
      await expectLater(create(revision: 3), throwsStateError);
      expect(calls.length, 2);
    },
  );
  test(
    'dispose rejects an in-flight read and releases its temporary listener',
    () async {
      readStarted = Completer<void>();
      releaseRead = Completer<void>();
      final pending = repo.myPackages();
      await readStarted!.future;
      final rejected = expectLater(pending, throwsStateError);
      repo.dispose();
      releaseRead!.complete();
      await rejected;
      expect(auth.events.hasListener, isFalse);
    },
  );
}
