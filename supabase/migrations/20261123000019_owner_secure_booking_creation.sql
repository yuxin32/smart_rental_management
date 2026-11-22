-- Server-authoritative creation of Pending cleaning requests.
-- Apply after 202610220005_provider_data_visibility.sql in a backed-up
-- staging project, then exercise RLS and concurrency with distinct accounts.

-- Existing rows remain null. New RPC-created requests carry a stable token
-- so a network retry cannot produce a second booking.
alter table public.booking add column client_request_id uuid;
alter table public.booking add constraint booking_owner_request_id_unique
  unique (owner_id, client_request_id);

-- The existing direct-update guard predates this column. A client may still
-- edit Pending instructions, but cannot replace the request's identity key.
create function public.guard_booking_request_id_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and
     new.client_request_id is distinct from old.client_request_id then
    raise exception 'Booking request identity cannot be edited directly'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard_booking_request_id_change_before
before update on public.booking for each row
execute function public.guard_booking_request_id_change();
revoke execute on function public.guard_booking_request_id_change()
  from public, anon, authenticated;

-- RLS alone previously allowed an Owner to insert any provider/service/time
-- combination. All new requests must go through the validated RPC below.
drop policy if exists booking_owner_insert on public.booking;
revoke insert on public.booking from public, anon, authenticated;

create function public.create_pending_booking(
  p_client_request_id uuid,
  p_provider_id uuid,
  p_property_id uuid,
  p_service_type_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_instructions text default ''
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_existing public.booking%rowtype;
  v_property public.property%rowtype;
  v_provider_status text;
  v_local_start timestamp;
  v_local_end timestamp;
  v_instructions text := coalesce(p_instructions, '');
  v_booking_id uuid;
begin
  if v_actor is null or not exists (
    select 1 from public.user_account a
    where a.user_id = v_actor and a.role = 'owner'
  ) then
    raise exception 'Property Owner authentication is required'
      using errcode = '42501';
  end if;
  if p_client_request_id is null or p_provider_id is null or
     p_property_id is null or p_service_type_id is null or
     p_start_at is null or p_end_at is null then
    raise exception 'Required booking fields are missing'
      using errcode = '23514';
  end if;

  -- An already committed request wins even if availability or approval has
  -- changed since submission. A reused token with a different payload fails.
  select * into v_existing from public.booking b
  where b.owner_id = v_actor and
        b.client_request_id = p_client_request_id;
  if found then
    if v_existing.provider_id <> p_provider_id or
       v_existing.property_id <> p_property_id or
       v_existing.service_type_id <> p_service_type_id or
       v_existing.requested_start_at <> p_start_at or
       v_existing.requested_end_at <> p_end_at or
       v_existing.instructions <> v_instructions then
      raise exception 'Request token was reused with different details'
        using errcode = '23514';
    end if;
    return jsonb_build_object('created', true,
                              'booking_id', v_existing.booking_id,
                              'reused', true);
  end if;

  if p_start_at <= now() or p_end_at <= p_start_at then
    return jsonb_build_object('created', false,
                              'reason', 'invalid_interval');
  end if;

  -- The provider lock serialises this initial check with capability and
  -- availability edits. Pending still does not reserve capacity; acceptance
  -- performs the authoritative recheck in its own protected transaction.
  select p.approval_status into v_provider_status
  from public.provider_profile p
  where p.provider_id = p_provider_id for update;
  if v_provider_status is distinct from 'approved' then
    return jsonb_build_object('created', false,
                              'reason', 'provider_not_approved');
  end if;

  select * into v_property from public.property p
  where p.property_id = p_property_id and p.owner_id = v_actor;
  if not found then
    return jsonb_build_object('created', false, 'reason', 'property');
  end if;

  v_local_start := p_start_at at time zone 'Asia/Kuala_Lumpur';
  v_local_end := p_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_local_start::date <> v_local_end::date or
     v_local_start::time < v_property.cleaning_window_start or
     v_local_end::time > v_property.cleaning_window_end then
    return jsonb_build_object('created', false,
                              'reason', 'rental_window');
  end if;

  if not exists (
    select 1 from public.provider_capability c
    where c.provider_id = p_provider_id and
          c.service_type_id = p_service_type_id
  ) then
    return jsonb_build_object('created', false, 'reason', 'service_type');
  end if;
  if exists (
    select 1 from public.provider_unavailable_date d
    where d.provider_id = p_provider_id and
          d.unavailable_on = v_local_start::date
  ) or not exists (
    select 1 from public.provider_weekly_slot s
    where s.provider_id = p_provider_id and
          s.weekday = extract(isodow from v_local_start)::integer and
          s.end_time - s.start_time >= interval '2 hours' and
          s.start_time <= v_local_start::time and
          s.end_time >= v_local_end::time
  ) then
    return jsonb_build_object('created', false, 'reason', 'availability');
  end if;
  if exists (
    select 1 from public.booking other
    where other.provider_id = p_provider_id and
          other.current_status in ('Accepted', 'In Progress') and
          other.requested_start_at < p_end_at and
          p_start_at < other.requested_end_at
  ) then
    return jsonb_build_object('created', false, 'reason', 'slot_conflict');
  end if;

  insert into public.booking (
    owner_id, provider_id, property_id, service_type_id,
    requested_start_at, requested_end_at, instructions,
    current_status, client_request_id
  ) values (
    v_actor, p_provider_id, p_property_id, p_service_type_id,
    p_start_at, p_end_at, v_instructions,
    'Pending', p_client_request_id
  ) on conflict (owner_id, client_request_id) do nothing
  returning booking_id into v_booking_id;

  if v_booking_id is null then
    -- A concurrent call with the same token committed first. Reject a
    -- mismatched payload; otherwise return that one original request.
    select * into v_existing from public.booking b
    where b.owner_id = v_actor and
          b.client_request_id = p_client_request_id;
    if not found or v_existing.provider_id <> p_provider_id or
       v_existing.property_id <> p_property_id or
       v_existing.service_type_id <> p_service_type_id or
       v_existing.requested_start_at <> p_start_at or
       v_existing.requested_end_at <> p_end_at or
       v_existing.instructions <> v_instructions then
      raise exception 'Request token was reused with different details'
        using errcode = '23514';
    end if;
    return jsonb_build_object('created', true,
                              'booking_id', v_existing.booking_id,
                              'reused', true);
  end if;
  return jsonb_build_object('created', true,
                            'booking_id', v_booking_id,
                            'reused', false);
end;
$$;
revoke execute on function public.create_pending_booking(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, text
) from public, anon;
grant execute on function public.create_pending_booking(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, text
) to authenticated;
