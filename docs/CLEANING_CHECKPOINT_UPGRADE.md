# Cleaning start and completion checkpoints

The integrated Owner/Provider module now includes the previously approved start/evidence/completion flow from local source checkpoint `975f201`.

## Behaviour

- Before the agreed start instant, Start cleaning is disabled. The database checks server time independently of the device clock.
- At the agreed time, Start cleaning opens Before evidence. A selected photo is previewed before upload. The job starts only after the assigned Provider saves a server-verified Before photo.
- Starting locks that Before attachment. The Provider can then add/replace/remove the After photo while work is in progress.
- Completion requires both verified attachments and the confirmation checkbox. Extra comments are optional and limited to 1,000 characters. The confirmation, comments, status change and history entry are saved in one transaction.
- Network retries keep the selected bytes and upload ID. An uncertain start/completion response checks current server status before offering another attempt.
- Jobs already In Progress before this upgrade retain the legacy photo path; the migration does not rewrite historical evidence or status.

Shared authentication, the four-role router, account field mapping and physical rental-unit linkage remain unchanged.

## Deployment boundary

This change has been tested locally. It has **not** been deployed to the hosted Integration project and has not been pushed to GitHub by this task. The new client completion flow requires migrations 047 and 048 before hosted testing.

The original integrated baseline is migrations 001–046. Its existing deployment bundle deliberately shares a temporary permission inventory between migrations 014 and 032, so use the documented transactional baseline bundle for a fresh database. This task does not rewrite that baseline.

For an existing Integration database at 046, review `supabase/deploy/upgrade_owner_cleaning_checkpoints.sql`. It contains only migrations 047 and 048 in one transaction, checks the integrated Staging identity `myetpfavvwuevdcybdes`, and records migration history. Back up the destination before manual deployment. For a fresh database, install the original integrated baseline first, then this upgrade. Do not apply either integrated package to the old source databases.

Regenerate the upgrade after editing either new migration:

```powershell
python tools/build_cleaning_checkpoint_upgrade.py
```

The existing evidence-validate endpoint contract is unchanged. The SQL upgrade changes reservation/validation/attachment phase checks and the start/completion gates; it does not replace Tenant/Admin functions or grants.

## Verification

Use Flutter 3.44.2 / Dart 3.12.2 for this checkout, matching its existing dependency lock. The original rental_app_demo SDK can remain installed separately.

```powershell
flutter pub get
flutter test --no-pub
flutter analyze --no-pub --no-fatal-infos
python tools/verify_cleaning_checkpoints.py --postgres-bin "PATH_TO_TRUSTED_POSTGRES_BIN" --output "PATH_TO_LOCAL_TEST_OUTPUT"
```

Local results for this change:

- 39 Flutter tests passed, including the existing role-selection test, start-time boundaries, routing into Before evidence, retained-photo retries, start rejection, locked Before photos, completion confirmation and private-cache isolation.
- The complete integrated baseline and reviewed 046-to-048 upgrade passed on disposable PostgreSQL with both broad legacy default privileges and disabled default API grants.
- 706 existing public function/table/column ACL entries were unchanged in each profile. The intended Before-lock read grant and new authenticated completion RPC were verified separately.
- SQL cases cover future-time and direct-update rejection, missing/invalid phase evidence, Owner/unrelated Provider/Tenant/Admin denial, Before locking, missing After, confirmation, comment length, idempotent completion/history, and Owner evidence access.
- Analyzer reports existing informational style findings; no errors or warnings. No hosted Auth/Storage/Realtime end-to-end result is claimed. The local Storage validator fixture models server attestations and does not decode real files.

## Remaining integration work

Response-deadline UI/logic, location and alternative-time matching, the weekly-hours editor, calendar/reminders and the latest Profile/Settings polish are separate ports. This checkpoint does not mark them complete. Hosted backup/deployment and two-device UAT also remain outstanding.
