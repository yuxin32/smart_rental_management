create temporary table integration_tenant_functions on commit drop as select oid from pg_proc where pronamespace='public'::regnamespace;
-- Core Owner/Provider booking schema. Review in a disposable Supabase project
-- before deployment; this repository does not currently connect to a project.
-- Time-of-day rules use Asia/Kuala_Lumpur as specified by the FYP report.

create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;
set search_path = public, extensions;


create type public.booking_status_enum as enum
  ('Pending', 'Accepted', 'In Progress', 'Completed', 'Declined', 'Cancelled');



create table public.property (
  property_id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.user_account(user_id),
  unit_name text not null,
  building_name text not null,
  address text not null,
  cleaning_window_start time not null default time '08:00',
  cleaning_window_end time not null default time '18:00',
  created_at timestamptz not null default now(),
  constraint property_window_order
    check (cleaning_window_end > cleaning_window_start),
  constraint property_owner_unit_unique
    unique (owner_id, building_name, unit_name)
);

create table public.provider_profile (
  provider_id uuid primary key references public.user_account(user_id),
  bio text,
  service_area text not null,
  service_origin_address text not null,
  hourly_rate numeric(10,2),
  daily_rate numeric(10,2),
  approval_status text not null default 'pending',
  rating_average numeric(3,2),
  completed_job_count integer not null default 0,
  constraint provider_rate_nonnegative
    check ((hourly_rate is null or hourly_rate >= 0)
       and (daily_rate is null or daily_rate >= 0)),
  constraint provider_has_rate
    check (hourly_rate is not null or daily_rate is not null),
  constraint provider_rating_range
    check (rating_average is null or rating_average between 1 and 5),
  constraint provider_completed_count_nonnegative
    check (completed_job_count >= 0)
);

create table public.service_type (
  service_type_id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text
);

create table public.provider_capability (
  provider_id uuid not null references public.provider_profile(provider_id)
    on delete cascade,
  service_type_id uuid not null references public.service_type(service_type_id),
  primary key (provider_id, service_type_id)
);

-- Weekly slots and whole-day exceptions are the authoritative availability
-- inputs. Alternative cleaning windows are calculated, never stored.
create table public.provider_weekly_slot (
  slot_id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profile(provider_id)
    on delete cascade,
  weekday integer not null check (weekday between 1 and 7),
  start_time time not null,
  end_time time not null,
  constraint provider_slot_order check (end_time > start_time),
  constraint provider_slot_unique
    unique (provider_id, weekday, start_time, end_time)
);

create table public.provider_unavailable_date (
  provider_id uuid not null references public.provider_profile(provider_id)
    on delete cascade,
  unavailable_on date not null,
  primary key (provider_id, unavailable_on)
);

create table public.booking (
  booking_id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.user_account(user_id),
  provider_id uuid not null references public.provider_profile(provider_id),
  property_id uuid not null references public.property(property_id),
  service_type_id uuid not null references public.service_type(service_type_id),
  requested_start_at timestamptz not null,
  requested_end_at timestamptz not null,
  instructions text not null default '',
  current_status public.booking_status_enum not null default 'Pending',
  created_at timestamptz not null default now(),
  constraint booking_interval_order
    check (requested_end_at > requested_start_at)
);

-- Database backstop for half-open intervals. Pending does not block capacity.
alter table public.booking add constraint booking_no_confirmed_overlap
  exclude using gist (
    provider_id with =,
    tstzrange(requested_start_at, requested_end_at, '[)') with &&
  ) where (current_status in ('Accepted', 'In Progress'));

create index booking_owner_idx on public.booking(owner_id, created_at desc);
create index booking_provider_idx
  on public.booking(provider_id, requested_start_at);

create table public.booking_status_history (
  status_history_id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.booking(booking_id)
    on delete cascade,
  changed_by_user_id uuid not null references public.user_account(user_id),
  previous_status public.booking_status_enum,
  new_status public.booking_status_enum not null,
  change_reason text,
  changed_at timestamptz not null default now()
);
create index booking_status_history_booking_idx
  on public.booking_status_history(booking_id, changed_at);

alter table public.user_account enable row level security;
alter table public.property enable row level security;
alter table public.provider_profile enable row level security;
alter table public.service_type enable row level security;
alter table public.provider_capability enable row level security;
alter table public.provider_weekly_slot enable row level security;
alter table public.provider_unavailable_date enable row level security;
alter table public.booking enable row level security;
alter table public.booking_status_history enable row level security;

create policy account_self_read on public.user_account for select
  to authenticated using ((select auth.uid()) = user_id);
create policy account_self_insert on public.user_account for insert
  to authenticated with check (
    (select auth.uid()) = user_id and
    lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
create policy account_self_update on public.user_account for update
  to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy property_owner_read on public.property for select
  to authenticated using ((select auth.uid()) = owner_id);
create policy property_owner_insert on public.property for insert
  to authenticated with check (
    (select auth.uid()) = owner_id and
    exists (select 1 from public.user_account a
            where a.user_id = owner_id and a.role = 'owner')
  );
create policy property_owner_update on public.property for update
  to authenticated using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy provider_profile_read on public.provider_profile for select
  to authenticated using (true);
create policy provider_profile_insert on public.provider_profile for insert
  to authenticated with check (
    (select auth.uid()) = provider_id and
    exists (select 1 from public.user_account a
            where a.user_id = provider_id and a.role = 'provider')
  );
create policy provider_profile_update on public.provider_profile for update
  to authenticated using ((select auth.uid()) = provider_id)
  with check ((select auth.uid()) = provider_id);

create policy service_type_read on public.service_type for select
  to authenticated using (true);
create policy capability_read on public.provider_capability for select
  to authenticated using (true);
create policy capability_provider_insert on public.provider_capability for insert
  to authenticated with check ((select auth.uid()) = provider_id);
create policy capability_provider_delete on public.provider_capability for delete
  to authenticated using ((select auth.uid()) = provider_id);

create policy weekly_slot_read on public.provider_weekly_slot for select
  to authenticated using (true);
create policy weekly_slot_insert on public.provider_weekly_slot for insert
  to authenticated with check ((select auth.uid()) = provider_id);
create policy weekly_slot_update on public.provider_weekly_slot for update
  to authenticated using ((select auth.uid()) = provider_id)
  with check ((select auth.uid()) = provider_id);
create policy weekly_slot_delete on public.provider_weekly_slot for delete
  to authenticated using ((select auth.uid()) = provider_id);

create policy unavailable_date_read on public.provider_unavailable_date
  for select to authenticated using (true);
create policy unavailable_date_insert on public.provider_unavailable_date
  for insert to authenticated with check ((select auth.uid()) = provider_id);
create policy unavailable_date_delete on public.provider_unavailable_date
  for delete to authenticated using ((select auth.uid()) = provider_id);

create policy booking_participant_read on public.booking for select
  to authenticated using (
    (select auth.uid()) = owner_id or (select auth.uid()) = provider_id
  );
create policy booking_owner_insert on public.booking for insert
  to authenticated with check (
    (select auth.uid()) = owner_id and current_status = 'Pending' and
    exists (select 1 from public.property p
            where p.property_id = public.booking.property_id and
                  p.owner_id = public.booking.owner_id)
  );
create policy booking_owner_update on public.booking for update
  to authenticated using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy booking_history_participant_read
  on public.booking_status_history for select to authenticated
  using (exists (
    select 1 from public.booking b
    where b.booking_id = public.booking_status_history.booking_id and
      (b.owner_id = (select auth.uid()) or
       b.provider_id = (select auth.uid()))
  ));

-- The first Pending history row is inserted together with the request.
create function public.record_initial_booking_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.booking_status_history
    (booking_id, changed_by_user_id, previous_status, new_status)
  values (new.booking_id, new.owner_id, null, 'Pending');
  return new;
end;
$$;
create trigger record_initial_booking_status_after
after insert on public.booking for each row
execute function public.record_initial_booking_status();

-- Self-managed account/profile fields must not let a client change its role,
-- approve itself, or forge computed provider statistics.
create function public.guard_account_client_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    new.user_id is distinct from old.user_id or
    new.role is distinct from old.role or
    new.email is distinct from old.email
  ) then
    raise exception 'Account identity and role cannot be edited directly'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard_account_client_update_before
before update on public.user_account for each row
execute function public.guard_account_client_update();

create function public.guard_property_client_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    new.property_id is distinct from old.property_id or
    new.owner_id is distinct from old.owner_id or
    new.created_at is distinct from old.created_at
  ) then
    raise exception 'Property identity cannot be edited directly'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard_property_client_update_before
before update on public.property for each row
execute function public.guard_property_client_update();

create function public.guard_provider_profile_client_write()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    (tg_op = 'INSERT' and (
      new.approval_status <> 'pending' or
      new.rating_average is not null or
      new.completed_job_count <> 0
    )) or
    (tg_op = 'UPDATE' and (
      new.provider_id is distinct from old.provider_id or
      new.approval_status is distinct from old.approval_status or
      new.rating_average is distinct from old.rating_average or
      new.completed_job_count is distinct from old.completed_job_count
    ))
  ) then
    raise exception 'Provider approval and statistics are system-managed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard_provider_profile_client_write_before
before insert or update on public.provider_profile for each row
execute function public.guard_provider_profile_client_write();

-- Direct client updates may change instructions only. Transition and interval
-- changes must go through server functions with a protected lock order.
create function public.guard_booking_client_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    new.booking_id is distinct from old.booking_id or
    new.owner_id is distinct from old.owner_id or
    new.provider_id is distinct from old.provider_id or
    new.property_id is distinct from old.property_id or
    new.service_type_id is distinct from old.service_type_id or
    new.requested_start_at is distinct from old.requested_start_at or
    new.requested_end_at is distinct from old.requested_end_at or
    new.current_status is distinct from old.current_status or
    new.created_at is distinct from old.created_at
  ) then
    raise exception 'Use an authorised booking operation'
      using errcode = '42501';
  end if;
  if current_user <> 'postgres' and old.current_status <> 'Pending' then
    raise exception 'Only a Pending request can be edited'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger guard_booking_client_update_before
before update on public.booking for each row
execute function public.guard_booking_client_update();

-- Serialise provider availability changes with acceptance checks. For slot
-- edits, modifying provider_id itself is forbidden to preserve the lock key.
create function public.lock_provider_availability_change()
returns trigger language plpgsql set search_path = '' as $$
declare v_provider_id uuid;
begin
  if tg_op = 'DELETE' then
    v_provider_id := old.provider_id;
  else
    v_provider_id := new.provider_id;
  end if;
  if tg_op = 'UPDATE' and new.provider_id <> old.provider_id then
    raise exception 'Availability slot provider cannot change';
  end if;
  perform 1 from public.provider_profile
    where provider_id = v_provider_id for update;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger lock_weekly_slot_before
before insert or update or delete on public.provider_weekly_slot
for each row execute function public.lock_provider_availability_change();
create trigger lock_unavailable_date_before
before insert or delete on public.provider_unavailable_date
for each row execute function public.lock_provider_availability_change();

-- A provider may change future availability, but not in a way that invalidates
-- an already confirmed future booking. The preceding trigger holds the same
-- provider lock used by acceptance until the availability transaction ends.
create function public.check_confirmed_after_availability_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_provider_id uuid;
  v_booking record;
  v_start timestamp;
  v_end timestamp;
begin
  if tg_op = 'DELETE' then
    v_provider_id := old.provider_id;
  else
    v_provider_id := new.provider_id;
  end if;
  for v_booking in
    select b.requested_start_at, b.requested_end_at
    from public.booking b
    where b.provider_id = v_provider_id and
          b.current_status in ('Accepted', 'In Progress') and
          b.requested_end_at > now()
  loop
    v_start := v_booking.requested_start_at at time zone 'Asia/Kuala_Lumpur';
    v_end := v_booking.requested_end_at at time zone 'Asia/Kuala_Lumpur';
    if exists (
      select 1 from public.provider_unavailable_date d
      where d.provider_id = v_provider_id and
            d.unavailable_on = v_start::date
    ) or not exists (
      select 1 from public.provider_weekly_slot s
      where s.provider_id = v_provider_id and
            s.weekday = extract(isodow from v_start)::integer and
            s.start_time <= v_start::time and
            s.end_time >= v_end::time
    ) then
      raise exception 'Availability change conflicts with a confirmed booking'
        using errcode = '23514';
    end if;
  end loop;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger check_confirmed_weekly_slot_after
after insert or update or delete on public.provider_weekly_slot
for each row execute function public.check_confirmed_after_availability_change();
create trigger check_confirmed_unavailable_date_after
after insert or delete on public.provider_unavailable_date
for each row execute function public.check_confirmed_after_availability_change();

-- Property window edits must serialise with acceptance of requests for this
-- property. Provider locks are acquired in a stable order.
create function public.lock_property_window_change()
returns trigger language plpgsql set search_path = '' as $$
declare v_provider_id uuid;
begin
  if new.cleaning_window_start is distinct from old.cleaning_window_start or
     new.cleaning_window_end is distinct from old.cleaning_window_end then
    for v_provider_id in
      select distinct b.provider_id from public.booking b
      where b.property_id = old.property_id and
            b.current_status in ('Pending', 'Accepted', 'In Progress')
      order by b.provider_id
    loop
      perform 1 from public.provider_profile
      where provider_id = v_provider_id for update;
    end loop;
    if exists (
      select 1 from public.booking b
      where b.property_id = old.property_id and
            b.current_status in ('Accepted', 'In Progress') and
            b.requested_end_at > now() and
            (
              (b.requested_start_at at time zone 'Asia/Kuala_Lumpur')::time
                < new.cleaning_window_start or
              (b.requested_end_at at time zone 'Asia/Kuala_Lumpur')::time
                > new.cleaning_window_end
            )
    ) then
      raise exception 'Cleaning window change conflicts with a confirmed booking'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger lock_property_window_before
before update on public.property for each row
execute function public.lock_property_window_change();

-- Authenticated provider only. PostgreSQL executes the function call in one
-- transaction. Lock provider first, then booking, then re-read current data.
create function public.accept_pending_booking(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_provider_id uuid;
  v_booking public.booking%rowtype;
  v_property public.property%rowtype;
  v_local_start timestamp;
  v_local_end timestamp;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select b.provider_id into v_provider_id from public.booking b
  where b.booking_id = p_booking_id;
  if v_provider_id is null or v_provider_id <> v_actor then
    raise exception 'Booking is not assigned to this provider'
      using errcode = '42501';
  end if;

  perform 1 from public.provider_profile p
  where p.provider_id = v_provider_id for update;
  select * into v_booking from public.booking b
  where b.booking_id = p_booking_id for update;
  if not found or v_booking.provider_id <> v_actor or
     v_booking.current_status <> 'Pending' then
    return jsonb_build_object('accepted', false, 'reason', 'not_pending');
  end if;

  select * into v_property from public.property p
  where p.property_id = v_booking.property_id;
  if not found or v_property.owner_id <> v_booking.owner_id then
    return jsonb_build_object('accepted', false, 'reason', 'property');
  end if;

  v_local_start := v_booking.requested_start_at at time zone 'Asia/Kuala_Lumpur';
  v_local_end := v_booking.requested_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_booking.requested_start_at <= now() or
     v_local_start::date <> v_local_end::date or
     v_local_start::time < v_property.cleaning_window_start or
     v_local_end::time > v_property.cleaning_window_end then
    return jsonb_build_object('accepted', false, 'reason', 'rental_window');
  end if;

  if exists (
    select 1 from public.provider_unavailable_date d
    where d.provider_id = v_provider_id and
          d.unavailable_on = v_local_start::date
  ) or not exists (
    select 1 from public.provider_weekly_slot s
    where s.provider_id = v_provider_id and
          s.weekday = extract(isodow from v_local_start)::integer and
          s.start_time <= v_local_start::time and
          s.end_time >= v_local_end::time
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'availability');
  end if;

  if not exists (
    select 1 from public.provider_capability c
    where c.provider_id = v_provider_id and
          c.service_type_id = v_booking.service_type_id
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'service_type');
  end if;

  if exists (
    select 1 from public.booking other
    where other.provider_id = v_provider_id and
          other.booking_id <> p_booking_id and
          other.current_status in ('Accepted', 'In Progress') and
          other.requested_start_at < v_booking.requested_end_at and
          v_booking.requested_start_at < other.requested_end_at
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'slot_conflict');
  end if;

  update public.booking set current_status = 'Accepted'
  where booking_id = p_booking_id;
  insert into public.booking_status_history
    (booking_id, changed_by_user_id, previous_status, new_status)
  values (p_booking_id, v_actor, 'Pending', 'Accepted');
  return jsonb_build_object('accepted', true, 'status', 'Accepted');
end;
$$;

revoke execute on function public.accept_pending_booking(uuid)
  from public, anon;
grant execute on function public.accept_pending_booking(uuid)
  to authenticated;
revoke execute on function public.guard_booking_client_update()
  from public, anon, authenticated;
revoke execute on function public.lock_provider_availability_change()
  from public, anon, authenticated;
revoke execute on function public.lock_property_window_change()
  from public, anon, authenticated;
revoke execute on function public.guard_account_client_update()
  from public, anon, authenticated;
revoke execute on function public.guard_provider_profile_client_write()
  from public, anon, authenticated;
revoke execute on function public.guard_property_client_update()
  from public, anon, authenticated;
revoke execute on function public.record_initial_booking_status()
  from public, anon, authenticated;
revoke execute on function public.check_confirmed_after_availability_change()
  from public, anon, authenticated;
