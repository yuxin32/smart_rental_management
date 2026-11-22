# Smart Rental Management — Integrated

Flutter application combining Tenant, Administrator, Property Owner and Cleaning Service Provider modules.

Open this folder (the folder containing `pubspec.yaml`) in Android Studio. Run `lib/main.dart` on an Android emulator.

The app connects to the integrated Supabase project `myetpfavvwuevdcybdes`. Its publishable client key is configured in `lib/core/config/supabase_config.dart`; server secret keys are never included in the app.

See [integration notes](docs/INTEGRATION.md) for schema decisions, first administrator setup, source revisions, verification and remaining deployment requirements.

The schema was installed on a new project. No old accounts or business records were migrated. Old login credentials therefore cannot sign into this project.

Backend migrations are exclusively for this integrated environment. Do not apply them to either original Supabase project.
