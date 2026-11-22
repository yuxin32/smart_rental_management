# Existing data migration

Date: 2026-11-23 (Asia/Kuala_Lumpur).
Sources: gwznscgganxegcpcpulm and gqtetdavmrautoojaqrk.
Destination: myetpfavvwuevdcybdes.

## Identity reconciliation
Seven distinct email addresses and UUIDs were found, so user IDs were preserved without merging unrelated people. Auth users and email identities were imported with existing encrypted password hashes. All seven hashes match the source and the target Auth admin API recognizes all seven users. Sessions, refresh tokens, recovery/confirmation tokens were not migrated; users sign in with their usual email and password against the new project.

Shared profile mapping: account_type -> role; phone -> contact_number; display_name -> full_name. Owner/provider accounts use active status; original tenant/admin lifecycle states are preserved. Missing shared fields use destination defaults. Provider profile display names use full_name.

## Records
- 7 Auth users, 7 email identities, 7 application profiles.
- 1 administrator, 2 tenants, 2 owners, 2 cleaning providers.
- 400 rental units, 2 tenancies, 2 tenant registrations.
- 5 meter devices, 100 readings.
- 38 cleaning bookings, 95 booking status-history rows.
- 3 tenant/admin messages, 20 booking messages.
- 2 announcements, 2 announcement recipients.
- 1 maintenance request and 1 update.
- 12 owner properties, 9 booking evidence records, 19 upload records, 18 server validation records.
- 18 Storage files transferred through Storage APIs and verified with SHA-256.
- Existing source tables for bills, tariff plans, rates and payment transactions contained no records.

## Other conflicts resolved
Five service catalogue entries already existed with different UUIDs. Matched them by exact name and rewrote dependent source service references to destination IDs.

The 12 historical owner properties use labels outside the A/B apartment inventory. Preserved their property IDs, unit labels, buildings, booking relationships and provenance in property.legacy_source_project. They are not arbitrarily assigned to the imported 400 apartments. Existing legacy property details can be edited without renaming the historical unit. New property registrations continue to enforce canonical unit codes.

Two fields present in the live source but missing from repository migrations were retained: booking_evidence.before_locked_at_start and completion_confirmed_at. Migration 20261123000046 adds the compatibility schema.

## Safety and verification
The source databases were read only. Data import was a single transaction. Application user triggers were suspended only inside the import transaction to avoid replaying historical notifications/audit events; all were restored before commit. Foreign keys stayed enforced and import order was derived from database foreign keys. Counts were asserted for every staged table. Auth password-preservation checks and authenticated role-access checks passed for all seven accounts. File bytes were verified after upload and original attachment ownership was restored.

Private exports, import SQL containing user data, and transfer credentials were kept outside the repository. Git contains only migration tools, schema changes, documentation and sanitized verification. Do not commit private exports or keys. Server keys are never placed in Flutter.

Interactive login using each existing password and full application workflows still require user testing. This migration does not implement additional functionality beyond the integrated application.
