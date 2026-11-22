-- Request-specific hard filtering for Owner booking search. This is NOT the
-- distance/rating/workload ranking algorithm. Keep private origin addresses
-- and raw Provider availability out of the response.

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
  completed_job_count integer
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_property public.property%rowtype;
  v_start timestamp;
  v_end timestamp;
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
         p.daily_rate, p.rating_average, p.completed_job_count
  from public.provider_profile p
  where p.approval_status = 'approved'
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
