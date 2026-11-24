import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/services/backend/auth_session_storage.dart';
import 'package:smart_rental_management/owner_provider/services/backend/auth_recovery_redirect.dart';
import 'package:smart_rental_management/owner_provider/services/backend/password_recovery_controller.dart';
import 'auth_storage_fixtures.dart';

/// Local HTTP only, unsigned synthetic sessions, no email or hosted service.
class RecoverySdkFixture {
  late HttpServer server;
  final vault = MemoryAuthStore();
  final legacy = MemoryAuthStore();
  late AuthSessionStorage storage;
  late PasswordRecoveryController recovery;
  int exchanges = 0, updates = 0, recoveries = 0;
  Uri? requestedRedirect;
  String? updateError;
  bool failExchange = false, failLogout = false, failRecover = false;
  bool dropUpdateResponse = false;
  Map<String, dynamic>? lastUpdate;
  Completer<void>? holdExchange, holdUpdate;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('x-supabase-api-version', '2024-01-01');
      final path = request.uri.path;
      if (path == '/auth/v1/recover') {
        recoveries++;
        requestedRedirect =
            Uri.tryParse(request.uri.queryParameters['redirect_to'] ?? '');
        request.response.statusCode = failRecover ? 429 : 200;
        request.response.write(
          failRecover
              ? '{"code":"over_email_send_rate_limit","msg":"Synthetic limit"}'
              : '{}',
        );
      } else if (path == '/auth/v1/token') {
        exchanges++;
        await holdExchange?.future;
        request.response.statusCode = failExchange ? 400 : 200;
        request.response.write(
          failExchange
              ? '{"code":"flow_state_not_found","msg":"Synthetic expired link"}'
              : syntheticSession(),
        );
      } else if (path == '/auth/v1/user') {
        updates++;
        lastUpdate = jsonDecode(body) as Map<String, dynamic>;
        await holdUpdate?.future;
        if (dropUpdateResponse) {
          final socket =
              await request.response.detachSocket(writeHeaders: false);
          socket.destroy();
          return;
        }
        if (updateError != null) {
          request.response.statusCode = updateError == 'expired'
              ? 401
              : updateError == 'outage'
                  ? 500
                  : 422;
          request.response.write(
            jsonEncode({
              'code': updateError,
              'msg': 'SYNTHETIC_PRIVATE_SERVER_MESSAGE',
            }),
          );
        } else {
          request.response
              .write(jsonEncode(jsonDecode(syntheticSession())['user']));
        }
      } else if (path == '/auth/v1/logout') {
        request.response.statusCode = failLogout ? 500 : 204;
        if (failLogout) {
          request.response.write('{"msg":"Synthetic logout outage"}');
        }
      } else if (path == '/rest/v1/user_account') {
        request.response.write(
          jsonEncode([
            {
              'user_id': testAuthUser,
              'email': 'test-user@fixture.invalid',
              'role': 'owner',
            }
          ]),
        );
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });
    storage = AuthSessionStorage(
      protectedStore: vault,
      legacyStore: legacy,
      projectRef: testAuthProject,
      environment: 'staging',
      hasCurrentSession: () =>
          Supabase.instance.client.auth.currentSession != null,
      isCurrentSession: (raw) => authStorageSessionMatches(
        raw,
        Supabase.instance.client.auth.currentSession?.accessToken ?? '',
      ),
    );
    await Supabase.initialize(
      url: 'http://${server.address.host}:${server.port}',
      publishableKey: 'SYNTHETIC_LOCAL_TEST_KEY',
      debug: false,
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: storage,
        pkceAsyncStorage: ProtectedPkceStorage(storage),
      ),
    );
    recovery = PasswordRecoveryController(
      client: Supabase.instance.client,
      storage: storage,
      redirect:
          AuthRecoveryRedirect('https://app.fixture.invalid/auth/recovery'),
    );
  }

  Uri link([String code = 'SYNTHETIC_RECOVERY_CODE']) =>
      Uri.parse('https://app.fixture.invalid/auth/recovery?code=$code');
  Future<void> ready() async {
    await recovery.requestEmail('test-user@fixture.invalid');
    await recovery.handleLink(link());
  }

  Future<void> dispose() async {
    recovery.dispose();
    await Supabase.instance.dispose();
    await server.close(force: true);
  }
}
