# Registered unit assignment

Admin selects a building and unit from Owner properties linked through
`rental_unit.property_id`. Migration 055 links existing Owner properties and
automatically synchronizes future property registrations and unit/building edits.
Unit labels follow each Owner property's number without an imposed A/B format.
The same unit label can exist in different buildings. The 400 generated inventory
records are inactive; their IDs remain for historical meter and billing references.

Whole-unit rental reserves the entire unit for one tenancy household,
with 1–8 occupants. The Admin form's “Rent single room” checkbox switches
from whole-unit rental to room rental and enables the room selector. Room numbers strictly follow the Owner's
registered bedroom count, with no four-room cap. Each room supports
1–2 occupants across overlapping tenancies, and the unit supports at most 8.
The count is the number of people covered by that tenancy record; companions
are counted without creating additional login accounts.

`rental_type`, `room_number`, and `occupant_count` are stored in both `tenancy`
and its onboarding `tenant_registration`. The existing `occupancy_share` remains
a billing fraction, and is preserved rather than repurposed as a headcount.
Monthly rent remains the total amount entered for this tenancy.

The backend checks inclusive tenancy dates, excludes the current tenancy when
editing, calculates peak simultaneous occupancy, and locks old/new unit rows
in a consistent order during assignment. A tenancy trigger also checks direct
writes. The old assignment RPC is no longer available to app roles.

Apply `supabase/deploy/upgrade_registered_unit_occupancy.sql` once to Integration.
It is transactional, checks the deployment identity, and records migration 054.
It relies on the integrated property linkage and is independent of migration 053.
Migration 054 was applied to `myetpfavvwuevdcybdes` on 26 November 2026.

Database regression checks cover full-room rejection, whole-unit/room conflicts,
different-room sharing, date expiry, and editing without double counting.
All synthetic assignments were rolled back. Concurrent hosted sessions and the
complete interactive UI flow still require user testing. Existing tenancy rows
default to whole-unit/one occupant and should be reviewed for actual arrangements.
