import 'package:web/web.dart' as web;

/// Capture once and remove secrets from the current address/history entry
/// before any asynchronous backend work. Hosting must also redact query logs.
Uri? takeRecoveryWebCallback() {
  final uri = Uri.parse(web.window.location.href);
  if (uri.path == '/auth/recovery') {
    web.window.history.replaceState(null, '', '/');
    return uri;
  }
  // Other Auth callbacks (e.g. signup confirmation) do not grant recovery or
  // auto-login. Still remove Auth URL fields; users verify then sign in normally.
  const sensitive = {
    'code',
    'access_token',
    'refresh_token',
    'token_type',
    'expires_in',
    'expires_at',
    'error',
    'error_code',
    'error_description',
    'type',
  };
  final query = Map<String, dynamic>.from(uri.queryParametersAll)
    ..removeWhere((key, _) => sensitive.contains(key));
  final authFragment = sensitive.any((key) =>
      uri.fragment.startsWith('$key=') || uri.fragment.contains('&$key='),);
  if (query.length != uri.queryParametersAll.length || authFragment) {
    final cleaned = uri.replace(
        queryParameters: query, fragment: authFragment ? '' : uri.fragment,);
    web.window.history.replaceState(null, '', cleaned.toString());
  }
  return null;
}
