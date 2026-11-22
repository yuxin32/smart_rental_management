-- Staging-only, administrator-invoked fixtures. No Auth accounts, mail, files,
-- payment events or Completed bookings are fabricated by this migration.
-- Do not rely on hosted default function ACLs for the admin tool's probe.
grant execute on function public.get_app_environment() to service_role;

create table public.test_data_run (
  run_id uuid primary key,
  project_ref text not null check (project_ref ~ '^[a-z]{20}$'),
  data_source text not null default 'SYNTHETIC TEST DATA - NOT A REAL USER'
    check (data_source = 'SYNTHETIC TEST DATA - NOT A REAL USER'),
  owner_id uuid not null unique references auth.users(id),
  provider_id uuid not null unique references auth.users(id),
  fixture_date date not null,
  created_at timestamptz not null default now(),
  review_after timestamptz not null default now() + interval '14 days',
  check (owner_id <> provider_id)
);
alter table public.test_data_run enable row level security;
revoke all on public.test_data_run from public, anon, authenticated, service_role;

-- Holds a shared marker lock for the calling transaction: an administrator's
-- environment reassignment cannot race an already-validated fixture write.
create function public.require_test_environment(p_project_ref text)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.app_deployment_environment%rowtype;
begin
  select * into v from public.app_deployment_environment where singleton for share;
  if v.environment is distinct from 'staging' or
     p_project_ref is null or v.project_ref is distinct from p_project_ref then
    raise exception 'Verified staging project required' using errcode = '42501';
  end if;
end;
$$;
revoke all on function public.require_test_environment(text)
  from public, anon, authenticated, service_role;

-- Used for BOTH dry run and creation; ordinary app accounts cannot call it.
-- New fixture accounts must be explicitly provisioned by the administrator in
-- Auth first, with these reserved, undeliverable addresses and no business data.
create function public.preview_test_fixture(
  p_project_ref text, p_run_id uuid, p_owner_id uuid, p_provider_id uuid,
  p_fixture_date date
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_run public.test_data_run%rowtype; v_owner_email text; v_provider_email text;
begin
  perform public.require_test_environment(p_project_ref);
  if p_run_id is null or p_owner_id is null or p_provider_id is null or
     p_owner_id = p_provider_id or p_fixture_date is null then
    raise exception 'Distinct test accounts and complete run parameters required'
      using errcode = '22023';
  end if;
  select * into v_run from public.test_data_run where run_id = p_run_id;
  if found then
    if v_run.owner_id <> p_owner_id or v_run.provider_id <> p_provider_id or
       v_run.fixture_date <> p_fixture_date or v_run.project_ref <> p_project_ref then
      raise exception 'Existing run parameters cannot be changed' using errcode = '22023';
    end if;
    return jsonb_build_object('run_id', p_run_id, 'already_seeded', true);
  end if;
  if p_fixture_date < (now() at time zone 'Asia/Kuala_Lumpur')::date + 1 or
     p_fixture_date > (now() at time zone 'Asia/Kuala_Lumpur')::date + 90 then
    raise exception 'Fixture date must be 1 to 90 Malaysian calendar days ahead'
      using errcode = '22023';
  end if;
  -- Lock Auth rows so deletion/reassignment cannot race creation. Auth itself
  -- is managed through its admin service, never inserted/updated by this RPC.
  select lower(email) into v_owner_email from auth.users where id = p_owner_id for share;
  select lower(email) into v_provider_email from auth.users where id = p_provider_id for share;
  if v_owner_email is distinct from 'owner.' || p_run_id::text || '@rental-test.invalid' or
     v_provider_email is distinct from 'provider.' || p_run_id::text || '@rental-test.invalid' then
    raise exception 'Use only the exact reserved test account emails for this run'
      using errcode = '42501';
  end if;
  if exists (select 1 from public.user_account where user_id in (p_owner_id, p_provider_id)) or
     exists (select 1 from public.test_data_run where
       owner_id in (p_owner_id, p_provider_id) or provider_id in (p_owner_id, p_provider_id)) then
    raise exception 'Test accounts must not already own business data or another run'
      using errcode = '42501';
  end if;
  if (select count(*) from public.service_type
      where name in ('Standard cleaning', 'Deep cleaning')) <> 2 then
    raise exception 'Required service catalogue missing' using errcode = '23514';
  end if;
  return jsonb_build_object('run_id', p_run_id, 'already_seeded', false,
    'planned_accounts', 2, 'planned_properties', 2, 'planned_pending_bookings', 1,
    'planned_weekly_slots', 7, 'deletion_supported', false);
end;
$$;
revoke all on function public.preview_test_fixture(text,uuid,uuid,uuid,date)
  from public, anon, authenticated;
grant execute on function public.preview_test_fixture(text,uuid,uuid,uuid,date) to service_role;

create function public.seed_test_fixture(
  p_project_ref text, p_run_id uuid, p_owner_id uuid, p_provider_id uuid,
  p_fixture_date date
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_plan jsonb; v_property uuid; v_service uuid; v_booking uuid;
begin
  -- Concurrent retries of one run serialize. Account PK/FKs protect other runs.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_run_id::text, 16));
  v_plan := public.preview_test_fixture(p_project_ref, p_run_id, p_owner_id,
    p_provider_id, p_fixture_date);
  if (v_plan->>'already_seeded')::boolean then return v_plan; end if;
  insert into public.test_data_run(run_id,project_ref,owner_id,provider_id,fixture_date)
    values (p_run_id,p_project_ref,p_owner_id,p_provider_id,p_fixture_date);
  insert into public.user_account(user_id,email,role) values
    (p_owner_id,'owner.' || p_run_id::text || '@rental-test.invalid','owner'),
    (p_provider_id,'provider.' || p_run_id::text || '@rental-test.invalid','provider');
  insert into public.provider_profile(provider_id,bio,service_area,service_origin_address,
    hourly_rate,daily_rate,approval_status) values
    (p_provider_id,'[TEST] Synthetic provider - not a real service business',
     'Kuala Lumpur','[TEST] No real origin configured',40,280,'approved');
  insert into public.provider_capability(provider_id,service_type_id)
    select p_provider_id,service_type_id from public.service_type
      where name in ('Standard cleaning','Deep cleaning');
  insert into public.provider_weekly_slot(provider_id,weekday,start_time,end_time)
    select p_provider_id,d,time '08:00',time '18:00' from generate_series(1,7) as d;
  insert into public.property(owner_id,unit_name,building_name,address,bedrooms,size_sqft)
    values (p_owner_id,'[TEST] Unit A','[TEST] Fixture Building',
      '[TEST] Synthetic address - not a real rental unit',2,750)
    returning property_id into v_property;
  insert into public.property(owner_id,unit_name,building_name,address,bedrooms,size_sqft)
    values (p_owner_id,'[TEST] Unit B','[TEST] Fixture Building',
      '[TEST] Synthetic address - not a real rental unit',3,1000);
  select service_type_id into v_service from public.service_type where name = 'Standard cleaning';
  insert into public.booking(owner_id,provider_id,property_id,service_type_id,
    requested_start_at,requested_end_at,instructions,client_request_id,
    quote_basis,quoted_rate,quoted_duration_minutes,quoted_amount)
    values (p_owner_id,p_provider_id,v_property,v_service,
      (p_fixture_date + time '10:00') at time zone 'Asia/Kuala_Lumpur',
      (p_fixture_date + time '12:00') at time zone 'Asia/Kuala_Lumpur',
      '[TEST] Synthetic cleaning request. No real service or payment.',p_run_id,
      'hourly',40,120,80) returning booking_id into v_booking;
  -- Existing initial-status trigger records Pending. Never invent evidence,
  -- Completed histories, ratings, payments or successful external operations.
  return v_plan || jsonb_build_object('created',true,'booking_id',v_booking);
end;
$$;
revoke all on function public.seed_test_fixture(text,uuid,uuid,uuid,date)
  from public, anon, authenticated;
grant execute on function public.seed_test_fixture(text,uuid,uuid,uuid,date) to service_role;

-- Read-only review, NOT a deletion authorization/plan. Includes later manual
-- activity for either registered actor. Mixed-account dependencies are flagged;
-- prefix labels alone are NEVER evidence that a record is safe to delete.
create function public.inspect_test_run(p_project_ref text, p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_run public.test_data_run%rowtype; v_counts jsonb; v_samples jsonb; v_mixed bigint;
begin
  perform public.require_test_environment(p_project_ref);
  select * into v_run from public.test_data_run where run_id = p_run_id;
  if not found then raise exception 'Unknown test run' using errcode = '22023'; end if;
  with related as (select b.* from public.booking b where
      b.owner_id in (v_run.owner_id,v_run.provider_id) or
      b.provider_id in (v_run.owner_id,v_run.provider_id) or
      b.property_id in (select property_id from public.property where owner_id = v_run.owner_id))
  select jsonb_build_object(
    'accounts',(select count(*) from public.user_account where user_id in (v_run.owner_id,v_run.provider_id)),
    'properties',(select count(*) from public.property where owner_id = v_run.owner_id),
    'weekly_slots',(select count(*) from public.provider_weekly_slot where provider_id = v_run.provider_id),
    'unavailable_dates',(select count(*) from public.provider_unavailable_date where provider_id = v_run.provider_id),
    'capabilities',(select count(*) from public.provider_capability where provider_id = v_run.provider_id),
    'bookings',(select count(*) from related),
    'status_history',(select count(*) from public.booking_status_history where booking_id in (select booking_id from related)),
    'messages',(select count(*) from public.booking_message where booking_id in (select booking_id from related)),
    'reviews',(select count(*) from public.booking_review where booking_id in (select booking_id from related)),
    'evidence',(select count(*) from public.booking_evidence where booking_id in (select booking_id from related)),
    'upload_tickets',(select count(*) from public.evidence_upload where booking_id in (select booking_id from related)),
    'storage_metadata_objects',(select count(*) from storage.objects s where
       s.bucket_id = 'cleaning-evidence' and split_part(s.name,'/',1) in
         (select booking_id::text from related))) into v_counts;
  select count(*) into v_mixed from public.booking b left join public.property p using(property_id)
    where (b.owner_id in (v_run.owner_id,v_run.provider_id) or
      b.provider_id in (v_run.owner_id,v_run.provider_id) or p.owner_id = v_run.owner_id)
    and (b.owner_id <> v_run.owner_id or b.provider_id <> v_run.provider_id or
      p.owner_id is distinct from v_run.owner_id);
  select coalesce(jsonb_agg(booking_id),'[]'::jsonb) into v_samples from
    (select booking_id from public.booking where owner_id = v_run.owner_id or
      provider_id = v_run.provider_id order by created_at,booking_id limit 20) as sample;
  return jsonb_build_object('run_id',p_run_id,'data_source',v_run.data_source,
    'fixture_date',v_run.fixture_date,'review_after',v_run.review_after,
    'review_due',now() >= v_run.review_after,'counts',v_counts,'booking_id_sample',v_samples,
    'mixed_account_bookings',v_mixed,'deletion_supported',false,
    'requires_manual_review',true);
end;
$$;
revoke all on function public.inspect_test_run(text,uuid) from public, anon, authenticated;
grant execute on function public.inspect_test_run(text,uuid) to service_role;
