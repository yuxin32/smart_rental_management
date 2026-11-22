import '../../owner_provider/services/backend/backend_config.dart';
import '../../owner_provider/services/backend/supabase_backend_provider.dart';
import 'supabase_config.dart';
abstract final class IntegratedBackend {
  static late final SupabaseBackendProvider instance;
  static Future<void> initialize() async {
    instance = (await SupabaseBackendProvider.initialize(const BackendConfig(
      url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey,
      environmentName: 'staging', projectRef: 'myetpfavvwuevdcybdes',
      recoveryRedirectUrl: 'smartrental://auth/recovery',
    )))!;
  }
}
