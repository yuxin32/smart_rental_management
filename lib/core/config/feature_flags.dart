/// Temporary switches used while individual modules are being developed and
/// demonstrated. When enabled, tenants may skip document submission and an
/// administrator may assign a unit after account setup. Set this to `false`
/// before evaluating the final verification workflow.
abstract final class AppFeatureFlags {
  static const bypassTenantDocumentVerificationForTesting = true;
}
