import 'dart:convert';
import 'auth_recovery_redirect.dart';

enum AppEnvironment { local, staging, production }

/// Build-time Supabase settings. The local preview remains available when
/// neither setting is supplied; a half-configured build fails explicitly.
class BackendConfig {
  const BackendConfig({
    required this.url,
    required this.publishableKey,
    this.environmentName = 'local',
    this.projectRef = '',
    this.allowProduction = false,
    this.recoveryRedirectUrl = '',
  });

  const BackendConfig.fromEnvironment()
      : url = const String.fromEnvironment('SUPABASE_URL'),
        publishableKey =
            const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
        environmentName =
            const String.fromEnvironment('APP_ENV', defaultValue: 'local'),
        projectRef = const String.fromEnvironment('SUPABASE_PROJECT_REF'),
        recoveryRedirectUrl =
            const String.fromEnvironment('AUTH_RECOVERY_REDIRECT_URL'),
        allowProduction =
            const bool.fromEnvironment('ALLOW_PRODUCTION_BACKEND');

  final String url;
  final String publishableKey;
  final String environmentName;
  final String projectRef;
  final bool allowProduction;
  final String recoveryRedirectUrl;

  AuthRecoveryRedirect? get recoveryRedirect => recoveryRedirectUrl.isEmpty
      ? null
      : AuthRecoveryRedirect(recoveryRedirectUrl,
          allowDevelopment: environment == AppEnvironment.staging,);

  AppEnvironment get environment => switch (environmentName) {
        'local' => AppEnvironment.local,
        'staging' => AppEnvironment.staging,
        'production' => AppEnvironment.production,
        _ => throw const FormatException(
            'APP_ENV must be local, staging or production.',
          ),
      };

  bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  void validate() {
    final target = environment;
    if (target == AppEnvironment.local) {
      if (url.isNotEmpty ||
          publishableKey.isNotEmpty ||
          projectRef.isNotEmpty ||
          recoveryRedirectUrl.isNotEmpty ||
          allowProduction) {
        throw const FormatException(
          'Local preview cannot contain backend settings. Select staging or production explicitly.',
        );
      }
      return;
    }
    final uri = Uri.tryParse(url);
    recoveryRedirect; // Validate before creating a client.
    if (!isConfigured ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Set both SUPABASE_URL (https) and SUPABASE_PUBLISHABLE_KEY.',
      );
    }
    if (!RegExp(r'^[a-z]{20}$').hasMatch(projectRef) ||
        uri.host != '$projectRef.supabase.co') {
      throw const FormatException(
        'SUPABASE_PROJECT_REF must match the hosted Supabase URL.',
      );
    }
    if (target == AppEnvironment.staging && allowProduction) {
      throw const FormatException(
        'Production access must not be enabled in staging.',
      );
    }
    if (target == AppEnvironment.production && !allowProduction) {
      throw const FormatException(
        'Production requires explicit ALLOW_PRODUCTION_BACKEND=true.',
      );
    }
    var isLegacyServiceRoleKey = false;
    final segments = publishableKey.split('.');
    if (segments.length == 3) {
      try {
        final payload = jsonDecode(
          utf8.decode(
            base64Url.decode(base64Url.normalize(segments[1])),
          ),
        );
        isLegacyServiceRoleKey = payload is Map<String, dynamic> &&
            payload['role'] == 'service_role';
      } on FormatException {
        // An opaque publishable key does not have to be a JWT.
      }
    }
    if (publishableKey.startsWith('sb_secret_') || isLegacyServiceRoleKey) {
      throw const FormatException(
        'Never include a Supabase secret/service-role key in a client build.',
      );
    }
  }

  /// Runs before creating any client or restoring a persisted Auth session.
  void validateForBuild({required bool isRelease}) {
    validate();
    if (isRelease) {
      // Production and release-staging recovery require a verified HTTPS
      // destination; development-only custom schemes are not a release option.
      AuthRecoveryRedirect(recoveryRedirectUrl);
    }
    if (isRelease && environment == AppEnvironment.local) {
      throw const FormatException(
        'Release builds require an explicitly configured backend.',
      );
    }
    if (!isRelease && environment == AppEnvironment.production) {
      throw const FormatException(
        'Development builds cannot connect to production. Use a separate staging project.',
      );
    }
  }

  /// This marker is administrator-owned. Never infer an environment from a
  /// project name, URL query parameter, Free/Pro plan, or a user's role.
  void verifyServerEnvironment(dynamic response) {
    if (environment == AppEnvironment.local ||
        response is! Map ||
        response['environment'] != environmentName ||
        response['project_ref'] != projectRef) {
      throw const FormatException(
        'Backend environment is unassigned or does not match this build.',
      );
    }
  }
}
