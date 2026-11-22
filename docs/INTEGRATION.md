# Integrated Smart Rental Management

Source: yuxin32/smart_rental_management at eb0dee3; wanting0024/smart-rental-management at b812322.
Target backend: myetpfavvwuevdcybdes. The schemas were installed first, followed by the authorized migration of both source projects' existing test data. See DATA_MIGRATION.md.

## Shared schema
- user_account.role uses public.account_type (tenant, admin, owner, provider).
- user_account.full_name, contact_number and account_status are shared.
- Owner/provider self registration is allowed; tenant invitation and admin provisioning remain controlled.
- property is the owner's apartment registration; rental_unit.property_id is a unique foreign key linking that record to the canonical physical apartment. tenancy links one tenant and one unit for a dated rental agreement. A tenancy never spans multiple apartments.
- Unit format A-01-01 through B-25-08; owner registration creates/links the rental_unit. The 400 source rental units and their existing tenant assignments were imported. New owner registrations use the canonical format. Imported properties with different historical labels retain those labels; no unrelated apartment ownership is inferred.
- Existing tenant/admin SQL RPCs, RLS, Storage and Realtime are preserved; owner/provider privileges were scoped so they do not erase tenant/admin RPC grants.

## Project structure
lib/core: shared authentication/configuration and tenant/admin theme.
lib/features: tenant/admin functionality.
lib/owner_provider: imported owner/provider features, repositories and UI, with package imports namespaced and shared client injected.
lib/main.dart: single executable entry and one initialized Supabase client.
supabase/migrations: fresh integrated history, not intended to be applied to either old database.
supabase/deploy: fresh empty-project SQL bundle and evidence endpoint dashboard bundle.
supabase/source_history: archived tenant/admin migration sources; not executable by CLI.

## Test accounts
The seven existing Auth users and application profiles were imported with their original IDs and password hashes: one admin, two tenants, two owners and two providers. Use existing login credentials. No new password setup is required for those accounts. Fresh tenants continue to use the administrator invitation workflow. The bootstrap_admin.sql helper remains available for a future empty environment.

## Emulator
Open the folder containing pubspec.yaml in Android Studio; select Flutter and lib/main.dart. APK application ID is com.smartrental.integrated so it can coexist with the original application.
The Pixel_10 image failed with software graphics; launch using host GPU with Vulkan disabled if needed.

## Verification and limits
Schema and data imports completed transactionally with foreign keys checked. All seven password hashes match their sources, the Auth API recognizes all seven users, and authenticated database checks pass for every role. All 18 transferred Storage files were downloaded from the target and compared with their source SHA-256 hashes. The APK builds and the existing login navigation test passes. Existing accounts are ready for emulator testing; full interactive workflow and email delivery tests are still required.

## Deployment
The three Edge Functions are invite-tenant, ingest-meter-reading, evidence-validate. They validate identity within their handlers (legacy-secret gateway validation is disabled for modern project keys). Secret keys are supplied by Supabase's server environment only.
Password recovery on Android uses smartrental://auth/recovery; add that exact redirect URL in Supabase Auth before testing recovery. A production verified HTTPS/app-link destination remains future deployment work.
