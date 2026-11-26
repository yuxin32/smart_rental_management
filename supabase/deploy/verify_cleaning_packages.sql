-- Read-only check in Integration SQL Editor after applying upgrade_cleaning_packages.sql.
select current_user as database_role,
       e.environment,
       e.project_ref,
       (select max(version) from supabase_migrations.schema_migrations) as latest_migration,
       pg_catalog.to_regclass('app_private.cleaning_package') is not null as package_table_exists,
       pg_catalog.to_regprocedure('public.my_cleaning_packages()') is not null as provider_packages_ready,
       pg_catalog.to_regprocedure('public.find_package_provider_matches(uuid,uuid,timestamp with time zone,timestamp with time zone,integer)') is not null as owner_package_search_ready,
       pg_catalog.to_regprocedure('public.create_pending_package_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid,numeric,bigint,text)') is not null as package_booking_ready
from public.app_deployment_environment e
where e.singleton;
