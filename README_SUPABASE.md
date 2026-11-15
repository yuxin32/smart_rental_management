# Supabase setup

The Flutter project is configured for the `smart_rental_management` Supabase
project and can also be overridden for another environment with build-time
values. To reproduce the database setup:

1. Sign in to the Supabase dashboard and open the project for
   `smart_rental_management`.
2. Run `supabase/migrations/202610190001_initial_schema.sql` once in the SQL
   Editor. This creates the application tables and Row-Level Security policies.
3. Copy the project URL and the public publishable key from **Project Settings → API**.
   The legacy anon key is also accepted by the app.
4. Run Flutter with build-time values when changing environments. Do not place
   the service-role key in the Flutter application:

   ```text
   flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
   ```

The app initializes Supabase at startup and all sign-in and password-reset
requests are handled by Supabase Auth. The Flutter project does not contain a
demo email or password. The DDSU666/ESP32 ingestion should be implemented
through a protected backend endpoint or Edge Function; the service-role key
must remain server-side.

## Tenant account lifecycle

The tenant onboarding workflow is intentionally separated into three administrator
steps to reduce incomplete records and assignment errors:

1. **Enter tenant information** — create a registration containing the tenant's
   name, IC number, email, contact number, verification status, and document
   references.
2. **Assign a unit** — search the registration by name or IC number and save the
   rental unit, tenancy dates, monthly rental amount, and occupancy share.
3. **Send invitation** — after the information is verified and the assignment is
   complete, call the deployed `invite-tenant` Edge Function. The function sends a
   Supabase Auth invitation, creates the pending tenant account, creates the
   pending tenancy, and records the invitation status. The administrator can
   resend an invitation only while the original tenant account is still pending;
   an accepted account is never replaced.

The Admin Module provides a **Tenant Audit Log** for the onboarding events
`TENANT_INFORMATION_ADDED`, `TENANT_UNIT_ASSIGNED`, `TENANT_INVITATION_SENT`,
and `TENANT_INVITATION_RESENT`. The first two events are recorded by a database
trigger, while invitation events are recorded by the server-side Edge Function.
Only active administrators can read these records.

The database migration for this workflow is
`supabase/migrations/202610240001_tenant_account_lifecycle.sql`. It has been
applied to the configured Supabase project. The onboarding audit migration is
`supabase/migrations/202610250001_tenant_onboarding_audit.sql`. It has also been
applied to the configured project. The `invite-tenant` Edge Function is
deployed in the same project and uses the service-role key only on the server.
The Flutter application never receives that key.

When the invited tenant follows the email link and sets a password, the app calls
the `activate_current_tenant` RPC. The pending account becomes active, the
pending tenancy becomes active, and the tenant can then view the rental details
for the unit assigned by the administrator. Configure Supabase SMTP before real
tenant onboarding. The invitation uses the mobile callback
`io.smartrental.app://auth-callback`.
Android and iOS are configured to open this callback in the application, and
Supabase Auth exchanges the returned invitation code for a session. The same
callback must be registered under **Authentication → URL Configuration →
Additional Redirect URLs** in Supabase. Configure Supabase SMTP before real
tenant onboarding.

## Role-specific login and routing

The application provides separate Tenant Login and Administrator Login entry
points. Both interfaces use Supabase Auth to verify the email and password.
After authentication, the app reads `public.user_account.account_type` and
checks that it matches the selected login area. Use `tenant` for the Tenant
Module and `admin` for the Admin Module. The account must also have
`account_status = 'active'`.

If a user selects the wrong login area, the application signs out the session
and asks the user to use the correct interface. This keeps the role-specific
entry points clear while retaining database-backed role enforcement.

An administrator must additionally have a matching row in `public.admin` with
`is_active = true`. The role is checked by the application after login and by
the database policies before protected records are returned.
