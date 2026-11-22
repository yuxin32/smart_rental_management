-- Connected provider setup. Apply only after reviewing existing live rows.
-- The service catalogue follows the five names already used in the app.
insert into public.service_type (name, description) values
  ('Standard cleaning', 'Routine cleaning of a rental unit.'),
  ('Deep cleaning', 'Detailed cleaning of a rental unit.'),
  ('Move-in cleaning', 'Cleaning before a tenant moves in.'),
  ('Move-out cleaning', 'Cleaning after a tenant moves out.'),
  ('Window cleaning', 'Cleaning of accessible windows.')
on conflict (name) do nothing;

-- Existing short slots are left untouched for explicit review, while every
-- new or edited slot must cover at least two hours.
alter table public.provider_weekly_slot
  add constraint provider_slot_minimum_two_hours
  check (end_time - start_time >= interval '2 hours') not valid;

create function public.validate_provider_weekly_slot()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Serialise concurrent edits for one provider before checking overlap.
  perform 1 from public.provider_profile p
    where p.provider_id = new.provider_id for update;
  if exists (
    select 1 from public.provider_weekly_slot s
    where s.provider_id = new.provider_id and s.weekday = new.weekday and
          s.slot_id <> new.slot_id and
          s.start_time < new.end_time and new.start_time < s.end_time
  ) then
    raise exception 'Working slots for one day cannot overlap'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger z_validate_provider_weekly_slot_before
before insert or update on public.provider_weekly_slot
for each row execute function public.validate_provider_weekly_slot();
revoke execute on function public.validate_provider_weekly_slot()
  from public, anon, authenticated;

-- Replace the provider's service types in one transaction. Direct client
-- inserts/deletes are removed so a partial multi-request save cannot leave
-- an unintended capability set.
drop policy if exists capability_provider_insert on public.provider_capability;
drop policy if exists capability_provider_delete on public.provider_capability;
create function public.replace_provider_capabilities(p_service_type_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_count integer;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_service_type_ids is null or cardinality(p_service_type_ids) = 0 or
     array_position(p_service_type_ids, null) is not null then
    raise exception 'Select at least one valid service type'
      using errcode = '23514';
  end if;
  perform 1 from public.provider_profile p
    where p.provider_id = v_actor for update;
  if not found then
    raise exception 'Provider profile is required'
      using errcode = '42501';
  end if;
  select count(*) into v_count from public.service_type s
    where s.service_type_id = any(p_service_type_ids);
  if v_count <> (select count(distinct x.service_type_id)
                  from unnest(p_service_type_ids) as x(service_type_id))
  then
    raise exception 'Unknown service type' using errcode = '23514';
  end if;

  if exists (
    select 1 from public.booking b
    where b.provider_id = v_actor and
          b.current_status in ('Accepted', 'In Progress') and
          b.requested_end_at > now() and
          not (b.service_type_id = any(p_service_type_ids))
  ) then
    raise exception 'A confirmed job still requires this service type'
      using errcode = '23514';
  end if;

  delete from public.provider_capability c
    where c.provider_id = v_actor and
          not (c.service_type_id = any(p_service_type_ids));
  insert into public.provider_capability(provider_id, service_type_id)
    select v_actor, x.service_type_id
      from unnest(p_service_type_ids) as x(service_type_id)
    on conflict (provider_id, service_type_id) do nothing;
  return v_count;
end;
$$;
revoke execute on function public.replace_provider_capabilities(uuid[])
  from public, anon;
grant execute on function public.replace_provider_capabilities(uuid[])
  to authenticated;

-- Acceptance remains one protected transaction. Approval is a hard filter,
-- never a ranking score or a decision made only by the mobile client.
create or replace function public.accept_pending_booking(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_provider_id uuid;
  v_approval_status text;
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

  select p.approval_status into v_approval_status
    from public.provider_profile p
    where p.provider_id = v_provider_id for update;
  if v_approval_status is distinct from 'approved' then
    return jsonb_build_object('accepted', false,
                              'reason', 'provider_not_approved');
  end if;
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
          s.end_time - s.start_time >= interval '2 hours' and
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
