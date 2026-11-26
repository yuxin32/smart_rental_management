# Cleaning packages and compact availability

The approved Owner duration selector and Provider Packages / Working hours are
implemented on `integration-owner-provider-latest`. No APK is needed to review
or run the source. Existing bookings retain their original time, quote and scope.

## Deployment

Apply migration **053** after integrated migrations 047–052. For the Supabase SQL
Editor use the complete generated file
`supabase/deploy/upgrade_cleaning_packages.sql`; it verifies the Integration
Staging identity `myetpfavvwuevdcybdes`, checks 052, runs transactionally and records
053. Do not run the raw migration a second time after applying the wrapper.
For CLI migration workflows, the raw migration is
`supabase/migrations/20261125000053_owner_cleaning_packages.sql` and the CLI owns
migration history. Do not apply these changes to either source project's backend.

The code and local database verification do not prove that the hosted upgrade or
two-device UAT has been completed. Apply the reviewed upgrade before trying new
package bookings. Refresh / restart the running App after changing the source.

No prices or packages are invented or seeded. Each Provider enables the cleaning
service in **Services offered**, then creates real packages in **Packages**.
An empty package list produces no package matches; hourly rates do not silently
become a package quote. Legacy clients and existing hourly/day bookings retain
their previous server checks and prices.

## Rules

- Standard cleaning: 2, 3 or 4 hours. Deep cleaning: 4, 6 or 8 hours.
- Each package specifies 1–4 cleaners, included tasks and a **total session price**.
  The total is not multiplied again by hours or cleaner count.
- Owner chooses service, crew, duration, date and start time. End time is derived
  and must fit the rental unit's cleaning window. Provider availability is checked
  by the server after search and again before creation / acceptance.
- Search and alternative times require a matching enabled package, approved
  Provider, offered service, service-area coverage, weekly availability, no day
  off and no overlapping confirmed job. Alternatives keep the selected duration
  and crew. Choosing an alternative requires confirmation and a fresh check.
- A Provider account still represents **one scheduling resource**. Setting two
  cleaners does not enable two overlapping jobs or model independent teams.
- Saved quotes include package identity, revision, crew, duration, scope and
  total. Editing / pausing a package does not alter saved bookings. Changed
  quotes require a new search; network retries reuse the request token.
- Working hours remain independent of packages. Each day has compact rows and
  separate `+N more` / `Show less`. Pencil opens the day editor; changes are
  checked against fresh confirmed bookings and a revision before saving.
- Confirmed intervals cannot be removed or made unavailable. Other hours may
  change. Dates containing confirmed bookings cannot become days off.

## Verify locally

```powershell
python tools/build_cleaning_packages_upgrade.py
flutter test --no-pub
flutter analyze --no-pub --no-fatal-infos
python supabase/tests/verify_cleaning_packages.py --postgres-bin "PATH_TO_TRUSTED_POSTGRES_BIN" --output "PATH_TO_LOCAL_TEST_OUTPUT"
```

The database harness uses disposable loopback PostgreSQL with synthetic Auth /
Storage and cron, with both broad legacy and disabled default grants. Hosted
Auth, Realtime, and actual phone behaviour still need Integration UAT.

Verified locally on 25 November 2026: all **399 Flutter tests** passed; the new
package repository, domain and UI files have no analysis findings. Full-project
analysis has no errors or warnings (existing informational style findings remain).
Web debug compilation and its Wasm compatibility dry run passed. All 53
migrations, seven SQL regression suites, and three concurrency scenarios passed
in four combinations: source migrations / generated deployment bundles under
broad legacy / disabled default grants. All 704 existing public ACL entries were
preserved. The 053 wrapper rejects a missing 052 prerequisite and duplicate
application. No hosted deployment or APK generation was performed.

## Two-role UAT

1. Provider: enable Standard cleaning, add a 1-cleaner / 3-hour package with a
   chosen total and scope, and declare a free working range on a future day.
2. Owner: choose a unit in that Provider's coverage, 1 cleaner / 3 hours, and a
   start that fits both windows. Verify the derived end and the exact package total.
3. Request the package; Provider accepts. Verify the saved crew, duration and
   total in the booking flow, and that income uses the saved quote.
4. Provider changes the package price / scope. Confirm the existing booking keeps
   its quote; a newly searched request uses the updated package.
5. Attempt to remove the accepted job's availability or block its date: the
   conflicting choice / write must be rejected. Edit unrelated hours successfully.
6. Check empty results, alternative-time confirmation, Cancel without saving,
   offline retry and editing the same package from two sessions.
