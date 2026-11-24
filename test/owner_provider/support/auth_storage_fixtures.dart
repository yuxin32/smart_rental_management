import 'dart:convert';
import 'package:smart_rental_management/owner_provider/services/backend/auth_session_storage.dart';

const testAuthProject = 'aaaaaaaaaaaaaaaaaaaa';
const testAuthUser = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
String syntheticSession({
  String project = testAuthProject,
  String user = testAuthUser,
  int expires = 4102444800,
  String suffix = 'a',
}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  // Deliberately unsigned software-test fixture, never a real credential.
  final token = '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({
        'iss': 'https://$project.supabase.co/auth/v1',
        'sub': user,
        'exp': expires,
        'aud': 'authenticated',
        'role': 'authenticated',
        'fixture': suffix,
      })}.SYNTHETIC_NOT_A_VALID_SIGNATURE';
  return jsonEncode({
    'access_token': token,
    'refresh_token': 'SYNTHETIC_REFRESH_$suffix',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': expires,
    'user': {
      'id': user,
      'aud': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-01-01T00:00:00Z',
      'email': 'test-user@fixture.invalid',
    },
  });
}

class MemoryAuthStore implements AuthKeyValueStore {
  final values = <String, String>{};
  final operations = <String>[];
  String? failRead, failWrite, failDelete;
  bool dropWrites = false;
  Future<void> Function(String key)? beforeWrite;
  @override
  Future<String?> read(String key) async {
    operations.add('read:$key');
    if (failRead == key) throw StateError('SYNTHETIC_SECRET_DO_NOT_LOG');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    operations.add('write:$key');
    await beforeWrite?.call(key);
    if (failWrite == key) throw StateError('SYNTHETIC_SECRET_DO_NOT_LOG');
    if (!dropWrites) values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    operations.add('delete:$key');
    if (failDelete == key) throw StateError('SYNTHETIC_SECRET_DO_NOT_LOG');
    values.remove(key);
  }
}
