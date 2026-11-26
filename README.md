# Smart Rental Management — Integrated

Flutter application combining Tenant, Administrator, Property Owner and Cleaning Service Provider modules.

Open this folder (the folder containing `pubspec.yaml`) in Android Studio. Run `lib/main.dart` on an Android emulator.

The current combined source is available on **`integration`** and **`main`**. Continue development from **`integration`**. See the [team handoff guide](docs/TEAM_HANDOFF.md) for clone/update commands, Flutter version, Android setup and the separate migration 053 deployment step.

The app connects to the integrated Supabase project `myetpfavvwuevdcybdes`. Its publishable client key is configured in `lib/core/config/supabase_config.dart`; server secret keys are never included in the app.

See [integration notes](docs/INTEGRATION.md) for schema decisions, first administrator setup, source revisions, verification and remaining deployment requirements.

The latest Owner/Provider screens, matching, availability, calendar and Android reminders are included on the integration branch. See the [latest upgrade notes](docs/OWNER_PROVIDER_LATEST_UPGRADE.md) for migrations 047–052. The compact duration selector, cleaning packages and working-hours editor additionally require [migration 053](docs/CLEANING_PACKAGES.md). Verify hosted migration history before running the updated client; local test success does not mark deployment or hosted UAT complete.

Both source projects' test records and seven Auth accounts have now been migrated. Use the same existing email/password combinations in the appropriate role workspace. Original user IDs, relationships and password hashes were preserved. See docs/DATA_MIGRATION.md for reconciliation and verification details.

Backend migrations are exclusively for this integrated environment. Do not apply them to either original Supabase project.
