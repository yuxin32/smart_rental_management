# Smart Rental Management — Integrated

Flutter application combining Tenant, Administrator, Property Owner and Cleaning Service Provider modules.

Open this folder (the folder containing `pubspec.yaml`) in Android Studio. Run `lib/main.dart` on an Android emulator.

The app connects to the integrated Supabase project `myetpfavvwuevdcybdes`. Its publishable client key is configured in `lib/core/config/supabase_config.dart`; server secret keys are never included in the app.

See [integration notes](docs/INTEGRATION.md) for schema decisions, first administrator setup, source revisions, verification and remaining deployment requirements.

Both source projects' test records and seven Auth accounts have now been migrated. Use the same existing email/password combinations in the appropriate role workspace. Original user IDs, relationships and password hashes were preserved. See docs/DATA_MIGRATION.md for reconciliation and verification details.

Backend migrations are exclusively for this integrated environment. Do not apply them to either original Supabase project.
