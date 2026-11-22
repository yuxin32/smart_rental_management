-- Authoritative MYR quote for cleaning requests. Apply after migration 008.
-- The quote is fixed when Pending is created; paying is still permitted only
-- after Completed and requires a separate trusted payment implementation.
-- Existing pre-migration bookings remain unpriced for explicit review.

alter table public.booking
  add column quote_currency text not null default 'MYR'
    check (quote_currency = 'MYR'),
  add column quote_basis text check (quote_basis in ('hourly', 'daily')),
  add column quoted_rate numeric(10,2),
  add column quoted_duration_minutes integer,
  add column quoted_amount numeric(12,2),
  add constraint booking_quote_complete check (
    (quote_basis is null and quoted_rate is null and
     quoted_duration_minutes is null and quoted_amount is null) or
    (quote_basis is not null and quoted_rate is not null and
     quoted_duration_minutes is not null and quoted_amount is not null and
     quoted_rate > 0 and quoted_amount > 0 and
     quoted_duration_minutes between 1 and 480 and
     extract(epoch from (requested_end_at - requested_start_at)) =
       quoted_duration_minutes * 60 and
     (quote_basis <> 'daily' or quoted_duration_minutes = 480))
  );

-- Invoker updates may still edit Pending instructions but cannot forge a
-- quoted price. The duration invariant applies even to protected RPCs:
-- changing duration requires a newly priced request, not a silent revision.
create function public.guard_booking_quote_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    new.quote_currency is distinct from old.quote_currency or
    new.quote_basis is distinct from old.quote_basis or
    new.quoted_rate is distinct from old.quoted_rate or
    new.quoted_duration_minutes is distinct from old.quoted_duration_minutes or
    new.quoted_amount is distinct from old.quoted_amount
  ) then
    raise exception 'Booking quote cannot be edited directly'
      using errcode = '42501';
  end if;
  if new.quoted_duration_minutes is not null and
     extract(epoch from (new.requested_end_at - new.requested_start_at))
       <> new.quoted_duration_minutes * 60 then
    raise exception 'Changing duration requires a new priced request'
      using errcode = '23514';
  end if;
  if old.current_status = 'Pending' and new.current_status = 'Accepted' and
     new.quoted_amount is null then
    raise exception 'Unpriced legacy request cannot be accepted'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger guard_booking_quote_change_before
before update on public.booking for each row
execute function public.guard_booking_quote_change();
revoke execute on function public.guard_booking_quote_change()
  from public, anon, authenticated;

-- No old seven-argument creation endpoint may remain callable: it could
-- otherwise create a Pending request without displaying a price to Owner.
drop function public.create_pending_booking(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, text
);

create function public.create_pending_booking(
  p_client_request_id uuid,
  p_provider_id uuid,
  p_property_id uuid,
  p_service_type_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_expected_amount numeric,
  p_expected_basis text,
  p_instructions text default ''
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_existing public.booking%rowtype;
  v_property public.property%rowtype;
  v_provider_status text;
  v_hourly_rate numeric;
  v_daily_rate numeric;
  v_rate numeric;
  v_basis text;
  v_amount numeric(12,2);
  v_seconds numeric;
  v_minutes integer;
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
     p_start_at is null or p_end_at is null or
     p_expected_amount is null or p_expected_basis is null then
    raise exception 'Required booking fields are missing'
      using errcode = '23514';
  end if;

  select * into v_existing from public.booking b
  where b.owner_id = v_actor and
        b.client_request_id = p_client_request_id;
  if found then
    if v_existing.provider_id <> p_provider_id or
       v_existing.property_id <> p_property_id or
       v_existing.service_type_id <> p_service_type_id or
       v_existing.requested_start_at <> p_start_at or
       v_existing.requested_end_at <> p_end_at or
       v_existing.instructions <> v_instructions or
       v_existing.quoted_amount is distinct from p_expected_amount or
       v_existing.quote_basis is distinct from p_expected_basis then
      raise exception 'Request token was reused with different details'
        using errcode = '23514';
    end if;
    return jsonb_build_object('created', true,
      'booking_id', v_existing.booking_id, 'reused', true,
      'quoted_amount', v_existing.quoted_amount,
      'quote_basis', v_existing.quote_basis,
      'quote_currency', v_existing.quote_currency);
  end if;

  if p_start_at <= now() or p_end_at <= p_start_at then
    return jsonb_build_object('created', false, 'reason', 'invalid_interval');
  end if;
  v_seconds := extract(epoch from (p_end_at - p_start_at));
  if mod(v_seconds, 60) <> 0 or v_seconds < 60 or v_seconds > 28800 then
    return jsonb_build_object('created', false, 'reason', 'invalid_duration');
  end if;
  v_minutes := (v_seconds / 60)::integer;

  -- Lock the Provider before reading their current rate and operational data.
  -- A later provider-rate edit does not alter this Booking's snapshot.
  select p.approval_status, p.hourly_rate, p.daily_rate
    into v_provider_status, v_hourly_rate, v_daily_rate
  from public.provider_profile p
  where p.provider_id = p_provider_id for update;
  if v_provider_status is distinct from 'approved' then
    return jsonb_build_object('created', false,
                              'reason', 'provider_not_approved');
  end if;

  if v_minutes = 480 and v_daily_rate > 0 then
    v_basis := 'daily';
    v_rate := v_daily_rate;
    v_amount := v_daily_rate;
  elsif v_hourly_rate > 0 then
    v_basis := 'hourly';
    v_rate := v_hourly_rate;
    v_amount := round(v_hourly_rate * v_minutes / 60, 2);
  else
    return jsonb_build_object('created', false,
                              'reason', 'rate_unavailable');
  end if;
  if v_amount <= 0 or p_expected_amount <> v_amount or
     p_expected_basis <> v_basis then
    return jsonb_build_object('created', false, 'reason', 'price_changed');
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
    return jsonb_build_object('created', false, 'reason', 'rental_window');
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
    current_status, client_request_id, quote_basis, quoted_rate,
    quoted_duration_minutes, quoted_amount
  ) values (
    v_actor, p_provider_id, p_property_id, p_service_type_id,
    p_start_at, p_end_at, v_instructions,
    'Pending', p_client_request_id, v_basis, v_rate,
    v_minutes, v_amount
  ) on conflict (owner_id, client_request_id) do nothing
  returning booking_id into v_booking_id;

  if v_booking_id is null then
    select * into v_existing from public.booking b
    where b.owner_id = v_actor and
          b.client_request_id = p_client_request_id;
    if not found or v_existing.provider_id <> p_provider_id or
       v_existing.property_id <> p_property_id or
       v_existing.service_type_id <> p_service_type_id or
       v_existing.requested_start_at <> p_start_at or
       v_existing.requested_end_at <> p_end_at or
       v_existing.instructions <> v_instructions or
       v_existing.quoted_amount is distinct from p_expected_amount or
       v_existing.quote_basis is distinct from p_expected_basis then
      raise exception 'Request token was reused with different details'
        using errcode = '23514';
    end if;
    return jsonb_build_object('created', true,
      'booking_id', v_existing.booking_id, 'reused', true,
      'quoted_amount', v_existing.quoted_amount,
      'quote_basis', v_existing.quote_basis,
      'quote_currency', v_existing.quote_currency);
  end if;
  return jsonb_build_object('created', true,
    'booking_id', v_booking_id, 'reused', false,
    'quoted_amount', v_amount, 'quote_basis', v_basis,
    'quote_currency', 'MYR');
end;
$$;
revoke execute on function public.create_pending_booking(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, numeric, text, text
) from public, anon;
grant execute on function public.create_pending_booking(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, numeric, text, text
) to authenticated;

-- The old search return type cannot be changed in-place. Replace it with a
-- version that includes the server-calculated quote displayed before Submit.
drop function public.find_eligible_providers(
  uuid, uuid, timestamptz, timestamptz
);
create function public.find_eligible_providers(
  p_property_id uuid,
  p_service_type_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns table (
  provider_id uuid,
  bio text,
  service_area text,
  hourly_rate numeric,
  daily_rate numeric,
  rating_average numeric,
  completed_job_count integer,
  quote_basis text,
  quoted_amount numeric
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_property public.property%rowtype;
  v_start timestamp;
  v_end timestamp;
  v_seconds numeric;
  v_minutes integer;
begin
  if v_actor is null or not exists (
    select 1 from public.user_account a
    where a.user_id = v_actor and a.role = 'owner'
  ) then
    raise exception 'Property Owner authentication is required'
      using errcode = '42501';
  end if;
  if p_property_id is null or p_service_type_id is null or
     p_start_at is null or p_end_at is null or
     p_start_at <= now() or p_end_at <= p_start_at then
    raise exception 'Select a valid future cleaning interval'
      using errcode = '23514';
  end if;
  v_seconds := extract(epoch from (p_end_at - p_start_at));
  if mod(v_seconds, 60) <> 0 or v_seconds < 60 or v_seconds > 28800 then
    raise exception 'Select a service duration up to eight hours'
      using errcode = '23514';
  end if;
  v_minutes := (v_seconds / 60)::integer;
  select * into v_property from public.property p
  where p.property_id = p_property_id and p.owner_id = v_actor;
  if not found then
    raise exception 'Rental unit is not owned by this account'
      using errcode = '42501';
  end if;
  v_start := p_start_at at time zone 'Asia/Kuala_Lumpur';
  v_end := p_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_start::date <> v_end::date or
     v_start::time < v_property.cleaning_window_start or
     v_end::time > v_property.cleaning_window_end then
    return;
  end if;

  return query
  select p.provider_id, p.bio, p.service_area, p.hourly_rate,
         p.daily_rate, p.rating_average, p.completed_job_count,
         case when v_minutes = 480 and p.daily_rate > 0
           then 'daily' else 'hourly' end,
         case when v_minutes = 480 and p.daily_rate > 0
           then p.daily_rate
           else round(p.hourly_rate * v_minutes / 60, 2) end
  from public.provider_profile p
  where p.approval_status = 'approved'
    and (
      (v_minutes = 480 and (p.daily_rate > 0 or p.hourly_rate > 0)) or
      (v_minutes < 480 and p.hourly_rate > 0 and
        round(p.hourly_rate * v_minutes / 60, 2) > 0)
    )
    and exists (
      select 1 from public.provider_capability c
      where c.provider_id = p.provider_id and
            c.service_type_id = p_service_type_id
    )
    and not exists (
      select 1 from public.provider_unavailable_date d
      where d.provider_id = p.provider_id and
            d.unavailable_on = v_start::date
    )
    and exists (
      select 1 from public.provider_weekly_slot s
      where s.provider_id = p.provider_id and
            s.weekday = extract(isodow from v_start)::integer and
            s.end_time - s.start_time >= interval '2 hours' and
            s.start_time <= v_start::time and s.end_time >= v_end::time
    )
    and not exists (
      select 1 from public.booking b
      where b.provider_id = p.provider_id and
            b.current_status in ('Accepted', 'In Progress') and
            b.requested_start_at < p_end_at and
            p_start_at < b.requested_end_at
    )
  order by p.provider_id;
end;
$$;
revoke execute on function public.find_eligible_providers(
  uuid, uuid, timestamptz, timestamptz
) from public, anon;
grant execute on function public.find_eligible_providers(
  uuid, uuid, timestamptz, timestamptz
) to authenticated;
