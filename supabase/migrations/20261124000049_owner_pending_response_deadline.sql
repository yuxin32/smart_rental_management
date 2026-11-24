-- Ported from 202610290031_pending_response_deadline.sql; shared integrated names/roles are preserved.
-- Distinguish a missed response deadline from a property-window mismatch.
-- Preserve locks, permissions, Pending status, and the original audit history.
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
  -- Recheck wall-clock time after acquiring locks, including any lock wait.
  if v_booking.requested_start_at <= clock_timestamp() then
    return jsonb_build_object('accepted', false, 'reason', 'request_expired');
  end if;
  if v_local_start::date <> v_local_end::date or
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
