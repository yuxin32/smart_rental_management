# Team handoff — Owner / Provider integration

## Get the correct source

Repository: <https://github.com/yuxin32/smart_rental_management>

Use **`integration-owner-provider-latest`**. The default `main` branch does not
contain the latest Owner / Provider integration. This handoff does not merge or
replace `main`.

First checkout in PowerShell, from the parent directory where you keep projects:

```powershell
git clone --branch integration-owner-provider-latest --single-branch https://github.com/yuxin32/smart_rental_management.git smart_rental_integration
cd smart_rental_integration
git branch --show-current
git log -1 --oneline
flutter --version
flutter pub get
flutter devices
```

Use Flutter **3.44.2 / Dart 3.12.2**. Open this new folder containing
`pubspec.yaml` in Android Studio, select `lib/main.dart`, then choose the Android
phone or emulator (not Windows desktop). Run from Android Studio, or substitute
the device ID printed by `flutter devices`:

```powershell
flutter run -d YOUR_ANDROID_DEVICE_ID
```

If you already cloned this repository, first run `git status`. Commit your own
changes on your feature branch before switching; do not discard local work.
Then fetch the integration branch and fast-forward it:

```powershell
git fetch origin integration-owner-provider-latest:refs/remotes/origin/integration-owner-provider-latest
git switch integration-owner-provider-latest
git pull --ff-only origin integration-owner-provider-latest
flutter pub get
```

If that local branch does not exist yet, use this instead of `git switch` above:

```powershell
git switch --track origin/integration-owner-provider-latest
```

Compare `git log -1 --oneline` with the handoff commit shared in chat. Start new
work on a separate feature branch based on this integration source:

```powershell
git switch -c feature/your-change
```

Push that feature branch and open a pull request into
`integration-owner-provider-latest` for review. Agree on merging integration into
`main` separately.

## Included in this update

- Compact Owner Bookings search / sorting / status and History controls.
- Alternative appointment times with explicit confirmation and a fresh
  server-side availability / quote check.
- Owner cleaning duration and crew selection, with the end time calculated from
  the chosen start and duration.
- Provider cleaning packages with a total session price and included tasks.
- Compact Working hours, editing by day, independent `+more` / collapse and
  protection for confirmed appointments and concurrent edits.
- A shared **`#13213A`** brand primary, based on the approved Tenant / Admin
  heading navy, for both module themes and sign-in role accents. Informational
  accents use the shared navy family; shared success / warning tokens use green
  / orange. Dark-mode foregrounds retain their readable light variants.

Typography changes remain **unapproved and unapplied**: Tenant / Admin retain
Roboto and Owner / Provider retain Inter. The proposed homepage rearrangement
and other preview-only designs are not part of this update. Existing typography,
screen structure, booking rules and semantic booking-status distinctions remain.

## Supabase is a separate step

This checkout targets Integration Staging **`myetpfavvwuevdcybdes`**. Do not
redirect it to either original source project's database. A GitHub clone copies
code and migration files; it does not copy hosted users, data, files or deploy
database changes. Use the existing shared Integration backend and arrange
dashboard access through its organization separately if needed.

The latest hosted evidence supplied before this handoff showed migration 052.
Migration **053 has been verified locally, but has not been deployed by this
handoff**. Before testing new package bookings:

1. In the Integration project's SQL Editor, run the read-only
   `supabase/deploy/verify_cleaning_packages.sql` and inspect the current state.
2. If 053 is missing and 052 is installed, the designated database maintainer
   reviews the upgrade, backs up Integration, then applies the **complete**
   `supabase/deploy/upgrade_cleaning_packages.sql` once.
3. Run the verification SQL again. Do not also run the raw 053 migration after
   the wrapper; they are two deployment methods for the same migration.
4. Provider enables a cleaning service and creates packages with agreed prices
   and scope. Packages are not automatically seeded from hourly rates.
5. Restart the updated app and perform the two-role checks in
   [CLEANING_PACKAGES.md](CLEANING_PACKAGES.md).

If the database is older than 052, follow
[OWNER_PROVIDER_LATEST_UPGRADE.md](OWNER_PROVIDER_LATEST_UPGRADE.md) first. A
normal teammate checkout does not need a new project or database password just
to run the app against the existing configured backend.

## What is intentionally not shared

Local `.env` files, database passwords, server secret keys, private backups,
Android signing keys, build folders and local `output/` captures are excluded.
The client project URL and publishable key are included as app configuration.
Exchange login credentials privately; do not add them to GitHub.

No APK is generated as part of this source handoff. Hosted Auth / Storage,
two-device realtime and physical-device acceptance testing remain separate from
local automated checks.

## Handoff verification

On 26 November 2026, the updated source passed all 399 Flutter tests. Static
analysis completed without errors or warnings; 433 informational findings
remain. Four local render checks covered role selection, administrator sign-in
and the Owner-facing Provider profile in light / dark appearance. The generated
053 deployment bundle matches its source migration. The earlier local SQL
receipt covers all 53 migrations, seven regression suites and three concurrency
scenarios in four deployment / grant combinations. This handoff did not rerun
or deploy SQL against hosted Supabase.
