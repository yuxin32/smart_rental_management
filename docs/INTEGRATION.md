# Integrated Smart Rental Management

Source: yuxin32/smart_rental_management at eb0dee3; wanting0024/smart-rental-management at b812322.
Target backend: myetpfavvwuevdcybdes. No old tenant, owner, booking, meter or message records copied.

## Shared schema
- user_account.role uses public.account_type (tenant, admin, owner, provider).
- user_account.full_name, contact_number and account_status are shared.
- Owner/provider self registration is allowed; tenant invitation and admin provisioning remain controlled.
- property is the owner's apartment registration; rental_unit.property_id is a unique foreign key linking that record to the canonical physical apartment. tenancy links one tenant and one unit for a dated rental agreement. A tenancy never spans multiple apartments.
- Unit format A-01-01 through B-25-08; owner registration creates/links the rental_unit. No prior unit inventory was copied. Register an owner property before assigning its unit to a tenant.
- Existing tenant/admin SQL RPCs, RLS, Storage and Realtime are preserved; owner/provider privileges were scoped so they do not erase tenant/admin RPC grants.

## Project structure
lib/core: shared authentication/configuration and tenant/admin theme.
lib/features: tenant/admin functionality.
lib/owner_provider: imported owner/provider features, repositories and UI, with package imports namespaced and shared client injected.
lib/main.dart: single executable entry and one initialized Supabase client.
supabase/migrations: fresh integrated history, not intended to be applied to either old database.
supabase/deploy: fresh empty-project SQL bundle and evidence endpoint dashboard bundle.
supabase/source_history: archived tenant/admin migration sources; not executable by CLI.

## First test accounts
The new project intentionally has no old Auth users or application profiles. Create a new Auth user in the target project for the administrator, then use supabase/bootstrap_admin.sql with that user's UUID. Enter passwords yourself in Supabase; never commit passwords. Owners/providers can register through their workspace. Admin invites tenants.

## Emulator
Open the folder containing pubspec.yaml in Android Studio; select Flutter and lib/main.dart. APK application ID is com.smartrental.integrated so it can coexist with the original application.
The Pixel_10 image failed with software graphics; launch using host GPU with Vulkan disabled if needed.

## Verification and limits
Fresh schema installed in one transaction; account/property mapping check runs as authenticated and rolls back all synthetic records. Compile/build checks cover all imported Dart modules. Live invitation emails, complete booking/evidence submission, document review, billing and chat require newly created test accounts and end-to-end checks. No claim that existing prototype functions are now production-ready.

## Deployment
The three Edge Functions are invite-tenant, ingest-meter-reading, evidence-validate. They validate identity within their handlers (legacy-secret gateway validation is disabled for modern project keys). Secret keys are supplied by Supabase's server environment only.
Password recovery on Android uses smartrental://auth/recovery; add that exact redirect URL in Supabase Auth before testing recovery. A production verified HTTPS/app-link destination remains future deployment work.
