-- Least-privilege closure after migrations 001-018. Staging first.
-- Do not apply to an unreconciled legacy/shared schema. No data is deleted.
-- Supabase-managed auth/storage/extension privileges are deliberately untouched.
-- Execute in a transaction (the staged bundle and local runner enforce this).
set local search_path = pg_catalog;

-- Default privileges belong to the role that CREATES the object, not roles
-- it inherits. Our migration runner must always create as postgres. Do not
-- impersonate the platform-internal supabase_admin role to change its defaults.
alter default privileges for role postgres
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres
  revoke all on sequences from public, anon, authenticated, service_role;
-- Global PUBLIC EXECUTE cannot be removed with a schema-only REVOKE.
alter default privileges for role postgres
  revoke all on functions from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from public, anon, authenticated, service_role;

revoke create on schema public from public, anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

do $privileges$
declare
  v_table text;
  v_columns text;
  v_function record;
  v_tables constant text[] := array[
    'admin','tenant','rental_unit','tenancy','electricity_device','electricity_reading','tariff_plan','tariff_rate','bill','bill_tariff_detail','payment_transaction','maintenance_request','maintenance_update','announcement','announcement_recipient','conversation','message','audit_log','tenant_registration','chat_attachment_cleanup_queue',
    'user_account','property','provider_profile','service_type',
    'provider_capability','provider_weekly_slot','provider_unavailable_date',
    'booking','booking_status_history','booking_evidence','booking_message',
    'booking_review','app_deployment_environment','evidence_upload','test_data_run'
  ];
begin
  if current_user <> 'postgres' then
    raise exception 'App migrations must run as postgres' using errcode='42501';
  end if;
  -- Fail closed on schema drift instead of changing unrelated tables.
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in ('r','p','v','m','f','S')
      and not (c.relname=any(v_tables))
      and not exists(select 1 from pg_depend d where d.classid='pg_class'::regclass
        and d.objid=c.oid and d.deptype='e')
  ) then
    raise exception 'Unexpected public relation: reconcile schema before migration 019';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proowner<>'postgres'::regrole
      and not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass
        and d.objid=p.oid and d.deptype='e')) then
    raise exception 'Unexpected application function owner: reconcile before migration 019';
  end if;
  foreach v_table in array v_tables loop
    if v_table=any(array['admin','tenant','rental_unit','tenancy','electricity_device','electricity_reading','tariff_plan','tariff_rate','bill','bill_tariff_detail','payment_transaction','maintenance_request','maintenance_update','announcement','announcement_recipient','conversation','message','audit_log','tenant_registration','chat_attachment_cleanup_queue']) then continue; end if;
    if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=v_table and c.relkind in ('r','p')
        and c.relowner='postgres'::regrole) then
      raise exception 'Expected postgres-owned application table: %',v_table;
    end if;
    execute format('alter table public.%I enable row level security',v_table);
    execute format('revoke all on table public.%I from public,anon,authenticated,service_role',v_table);
    -- Table REVOKE does not remove old column-level grants.
    select string_agg(format('%I',attname),',') into v_columns from pg_attribute
      where attrelid=format('public.%I',v_table)::regclass and attnum>0 and not attisdropped;
    execute format('revoke all (%s) on table public.%I from public,anon,authenticated,service_role',v_columns,v_table);
  end loop;

  -- Reset only migration-owned, non-extension functions. Internal helpers
  -- stay uncallable; exact RPC signatures are explicitly granted below.
  for v_function in
    select p.oid::regprocedure as signature from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proowner='postgres'::regrole and p.prokind='f'
      and p.oid not in (select oid from integration_tenant_functions)
      and not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass
        and d.objid=p.oid and d.deptype='e')
  loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',v_function.signature);
  end loop;
end;
$privileges$;

-- Private internal state/functions have no client or service-role table API.
revoke all on schema app_private from public,anon,authenticated,service_role;
revoke all on all tables in schema app_private from public,anon,authenticated,service_role;
revoke all on all functions in schema app_private from public,anon,authenticated,service_role;
alter default privileges for role postgres in schema app_private
  revoke all on tables from public,anon,authenticated,service_role;
alter default privileges for role postgres in schema app_private
  revoke all on sequences from public,anon,authenticated,service_role;
alter default privileges for role postgres in schema app_private
  revoke all on functions from public,anon,authenticated,service_role;

-- SELECT is needed by RLS, Realtime and current direct read repositories.
-- RLS still limits own rows/booking participants; catalogue is authenticated.
grant select on public.user_account,public.property,public.provider_profile,
  public.service_type,public.provider_capability,public.provider_weekly_slot,
  public.provider_unavailable_date,public.booking,public.booking_status_history,
  public.booking_evidence,public.booking_message,public.booking_review,
  public.evidence_upload to authenticated;

grant insert(user_id,email,contact_number,role) on public.user_account to authenticated;
grant update(contact_number) on public.user_account to authenticated;
grant insert(owner_id,unit_name,building_name,address,bedrooms,size_sqft,
  cleaning_window_start,cleaning_window_end) on public.property to authenticated;
grant update(unit_name,building_name,address,bedrooms,size_sqft,
  cleaning_window_start,cleaning_window_end) on public.property to authenticated;
grant insert(provider_id,bio,service_area,service_origin_address,hourly_rate,daily_rate)
  on public.provider_profile to authenticated;
grant update(bio,service_area,service_origin_address,hourly_rate,daily_rate)
  on public.provider_profile to authenticated;
grant insert(provider_id,weekday,start_time,end_time)
  on public.provider_weekly_slot to authenticated;
grant update(weekday,start_time,end_time) on public.provider_weekly_slot to authenticated;
grant delete on public.provider_weekly_slot to authenticated;
grant insert(provider_id,unavailable_on) on public.provider_unavailable_date to authenticated;
grant delete on public.provider_unavailable_date to authenticated;
-- Preserve Pending Owner instructions edits; interval/status/quote use RPCs.
grant update(instructions) on public.booking to authenticated;

-- Do not leave an obsolete permissive creation policy behind a denied grant.
drop policy if exists booking_owner_insert on public.booking;

grant execute on function
  public.accept_pending_booking(uuid),
  public.transition_booking(uuid,public.booking_status_enum,text),
  public.revise_pending_booking(uuid,timestamptz,timestamptz,text),
  public.replace_provider_capabilities(uuid[]),
  public.list_approved_provider_directory(),
  public.find_eligible_providers(uuid,uuid,timestamptz,timestamptz),
  public.create_pending_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,text,text),
  public.send_booking_message(uuid,uuid,text),
  public.save_booking_review(uuid,integer,text),
  public.list_booking_contexts(),
  public.page_my_bookings(integer,timestamptz,uuid),
  public.booking_cards_by_ids(uuid[]),
  public.page_booking_messages(uuid,integer,timestamptz,uuid),
  public.page_booking_history(uuid,integer,timestamptz,uuid),
  public.owner_dashboard_summary(),
  public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text),
  public.attach_evidence_upload(uuid,uuid),
  public.save_evidence_remarks(uuid,text),
  public.claim_evidence_cleanup(uuid),
  public.finish_evidence_cleanup(uuid,text),
  public.can_read_evidence_object(text),
  public.can_delete_evidence_object(text)
to authenticated;

-- Only non-sensitive deployment identity is readable before login.
grant execute on function public.get_app_environment() to anon,authenticated,service_role;

-- Server-only endpoint/maintenance tools; no broad direct business-table access.
grant execute on function
  public.claim_evidence_validation(uuid,uuid,uuid),
  public.finish_evidence_validation(uuid,uuid,text,text,integer,integer,integer,text),
  public.fail_evidence_validation(uuid,uuid,boolean),
  public.list_evidence_cleanup_batch(),
  public.claim_evidence_cleanup_batch(),
  public.finish_evidence_cleanup_batch(uuid,text),
  public.preview_test_fixture(text,uuid,uuid,uuid,date),
  public.seed_test_fixture(text,uuid,uuid,uuid,date),
  public.inspect_test_run(text,uuid)
to service_role;

-- App PKs are UUIDs, not sequences. Existing public sequences are not part of
-- this contract; the preflight must inventory any non-extension sequences.
