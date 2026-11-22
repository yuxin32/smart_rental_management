-- Apply only after 202609270001_core_booking.sql in a disposable project.
-- This remains unverified until PostgreSQL/RLS integration tests run.

alter table public.property
  add column bedrooms integer not null default 1 check (bedrooms > 0),
  add column size_sqft integer not null default 1 check (size_sqft > 0);

create table public.booking_evidence (
  booking_id uuid primary key references public.booking(booking_id)
    on delete cascade,
  before_path text,
  after_path text,
  completion_remarks text not null default '',
  updated_at timestamptz not null default now(),
  constraint evidence_before_in_booking_folder check (
    before_path is null or before_path like booking_id::text || '/%'
  ),
  constraint evidence_after_in_booking_folder check (
    after_path is null or after_path like booking_id::text || '/%'
  )
);

alter table public.booking_evidence enable row level security;
create policy evidence_participant_read on public.booking_evidence
  for select to authenticated using (exists (
    select 1 from public.booking b
    where b.booking_id = booking_evidence.booking_id and
      (b.owner_id = (select auth.uid()) or
       b.provider_id = (select auth.uid()))
  ));
create policy evidence_provider_insert on public.booking_evidence
  for insert to authenticated with check (exists (
    select 1 from public.booking b
    where b.booking_id = booking_evidence.booking_id and
      b.provider_id = (select auth.uid()) and
      b.current_status in ('Accepted', 'In Progress')
  ));
create policy evidence_provider_update on public.booking_evidence
  for update to authenticated
  using (exists (
    select 1 from public.booking b
    where b.booking_id = booking_evidence.booking_id and
      b.provider_id = (select auth.uid()) and
      b.current_status in ('Accepted', 'In Progress')
  ))
  with check (exists (
    select 1 from public.booking b
    where b.booking_id = booking_evidence.booking_id and
      b.provider_id = (select auth.uid()) and
      b.current_status in ('Accepted', 'In Progress')
  ));

insert into storage.buckets
  (id, name, public, file_size_limit, allowed_mime_types)
values
  ('cleaning-evidence', 'cleaning-evidence', false, 5242880,
   array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

-- Object names have the form booking_id/random_name.jpg or .png.
-- Only the assigned provider may upload while the booking is active.
create policy evidence_object_provider_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'cleaning-evidence' and
    lower(storage.extension(name)) in ('jpg', 'jpeg', 'png') and
    exists (
      select 1 from public.booking b
      where b.booking_id::text = (storage.foldername(name))[1] and
        b.provider_id = (select auth.uid()) and
        b.current_status in ('Accepted', 'In Progress')
    )
  );
create policy evidence_object_participant_read on storage.objects
  for select to authenticated using (
    bucket_id = 'cleaning-evidence' and
    exists (
      select 1 from public.booking b
      where b.booking_id::text = (storage.foldername(name))[1] and
        (b.owner_id = (select auth.uid()) or
         b.provider_id = (select auth.uid()))
    )
  );

-- The accepted transition is deliberately excluded: only
-- accept_pending_booking performs its atomic availability recheck.
create function public.transition_booking(
  p_booking_id uuid,
  p_new_status public.booking_status_enum,
  p_reason text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_provider_id uuid;
  v_booking public.booking%rowtype;
  v_evidence public.booking_evidence%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select b.provider_id into v_provider_id from public.booking b
  where b.booking_id = p_booking_id;
  if v_provider_id is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;

  -- Match the provider-then-booking lock order of acceptance.
  perform 1 from public.provider_profile p
    where p.provider_id = v_provider_id for update;
  select * into v_booking from public.booking b
    where b.booking_id = p_booking_id for update;

  if not (
    (v_booking.current_status = 'Pending' and
      p_new_status = 'Declined' and v_actor = v_booking.provider_id) or
    (v_booking.current_status = 'Pending' and
      p_new_status = 'Cancelled' and v_actor = v_booking.owner_id) or
    (v_booking.current_status = 'Accepted' and
      p_new_status = 'In Progress' and v_actor = v_booking.provider_id) or
    (v_booking.current_status = 'In Progress' and
      p_new_status = 'Completed' and v_actor = v_booking.provider_id)
  ) then
    raise exception 'Transition or actor is not permitted'
      using errcode = '42501';
  end if;

  if p_new_status = 'Completed' then
    select * into v_evidence from public.booking_evidence e
      where e.booking_id = p_booking_id for update;
    if not found or v_evidence.before_path is null or
       v_evidence.after_path is null or
       length(btrim(v_evidence.completion_remarks)) = 0 or
       not exists (
         select 1 from storage.objects o
         where o.bucket_id = 'cleaning-evidence' and
               o.name = v_evidence.before_path
       ) or not exists (
         select 1 from storage.objects o
         where o.bucket_id = 'cleaning-evidence' and
               o.name = v_evidence.after_path
       ) then
      raise exception 'Before/after images and remarks are required'
        using errcode = '23514';
    end if;
  end if;

  update public.booking set current_status = p_new_status
    where booking_id = p_booking_id;
  insert into public.booking_status_history
    (booking_id, changed_by_user_id, previous_status, new_status,
     change_reason)
  values (p_booking_id, v_actor, v_booking.current_status, p_new_status,
          nullif(btrim(p_reason), ''));
  return jsonb_build_object('status', p_new_status::text);
end;
$$;
revoke execute on function public.transition_booking(
  uuid, public.booking_status_enum, text) from public, anon;
grant execute on function public.transition_booking(
  uuid, public.booking_status_enum, text) to authenticated;

-- Revisions keep the state Pending and recheck the latest restrictions.
-- A failed revision leaves the original interval unchanged.
create function public.revise_pending_booking(
  p_booking_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_instructions text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_provider_id uuid;
  v_booking public.booking%rowtype;
  v_property public.property%rowtype;
  v_start timestamp;
  v_end timestamp;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select b.provider_id into v_provider_id from public.booking b
    where b.booking_id = p_booking_id;
  if v_provider_id is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  perform 1 from public.provider_profile p
    where p.provider_id = v_provider_id for update;
  select * into v_booking from public.booking b
    where b.booking_id = p_booking_id for update;
  if v_booking.owner_id <> v_actor or
     v_booking.current_status <> 'Pending' then
    raise exception 'Only the owner can revise a Pending booking'
      using errcode = '42501';
  end if;
  if p_start_at is null or p_end_at is null or
     p_start_at <= now() or p_end_at <= p_start_at then
    return jsonb_build_object('revised', false, 'reason', 'invalid_interval');
  end if;
  select * into v_property from public.property p
    where p.property_id = v_booking.property_id;
  v_start := p_start_at at time zone 'Asia/Kuala_Lumpur';
  v_end := p_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_start::date <> v_end::date or
     v_start::time < v_property.cleaning_window_start or
     v_end::time > v_property.cleaning_window_end then
    return jsonb_build_object('revised', false, 'reason', 'rental_window');
  end if;
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
    return jsonb_build_object('revised', false, 'reason', 'availability');
  end if;
  if not exists (
    select 1 from public.provider_capability c
    where c.provider_id = v_provider_id and
          c.service_type_id = v_booking.service_type_id
  ) then
    return jsonb_build_object('revised', false, 'reason', 'service_type');
  end if;
  if exists (
    select 1 from public.booking other
    where other.provider_id = v_provider_id and
          other.booking_id <> p_booking_id and
          other.current_status in ('Accepted', 'In Progress') and
          other.requested_start_at < p_end_at and
          p_start_at < other.requested_end_at
  ) then
    return jsonb_build_object('revised', false, 'reason', 'slot_conflict');
  end if;
  update public.booking
    set requested_start_at = p_start_at,
        requested_end_at = p_end_at,
        instructions = coalesce(p_instructions, '')
    where booking_id = p_booking_id;
  return jsonb_build_object('revised', true, 'status', 'Pending');
end;
$$;
revoke execute on function public.revise_pending_booking(
  uuid, timestamptz, timestamptz, text) from public, anon;
grant execute on function public.revise_pending_booking(
  uuid, timestamptz, timestamptz, text) to authenticated;

-- New tables are not automatically published for Realtime.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and
            schemaname = 'public' and tablename = 'booking'
    ) then
      alter publication supabase_realtime add table public.booking;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and
            schemaname = 'public' and tablename = 'booking_status_history'
    ) then
      alter publication supabase_realtime add table public.booking_status_history;
    end if;
  end if;
end;
$$;
