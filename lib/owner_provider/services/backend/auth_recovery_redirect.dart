/// Exact callback allow-list. Configuration must not come from an email link.
class AuthRecoveryRedirect {
  AuthRecoveryRedirect(String value, {bool allowDevelopment = false})
      : uri = Uri.parse(value) {
    final development = allowDevelopment &&
        ((uri.scheme == 'http' &&
                ['localhost', '127.0.0.1', '[::1]'].contains(uri.host)) ||
            (uri.scheme == 'smartrental' &&
                uri.host == 'auth' &&
                !uri.hasPort));
    if ((!development && (uri.scheme != 'https' || uri.hasPort)) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path !=
            (uri.scheme == 'smartrental' ? '/recovery' : '/auth/recovery') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Configure a trusted password recovery URL.');
    }
  }

  final Uri uri;
  bool matches(Uri incoming) =>
      incoming.scheme == uri.scheme &&
      incoming.host == uri.host &&
      incoming.port == uri.port &&
      incoming.userInfo.isEmpty &&
      incoming.path == uri.path;

  String? code(Uri incoming) {
    if (!matches(incoming) ||
        incoming.hasFragment ||
        incoming.query.length > 4096) return null;
    Map<String, List<String>> values;
    try {
      values = incoming.queryParametersAll;
    } on FormatException {
      return null;
    }
    if (values.length != 1 || values['code']?.length != 1) return null;
    final code = values['code']!.single;
    return RegExp(r'^[a-zA-Z0-9_-]{8,2048}$').hasMatch(code) ? code : null;
  }
}
