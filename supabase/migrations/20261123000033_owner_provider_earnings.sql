-- Read-only earnings reporting. Quotes are NOT payments or net settlements.
-- No fee is invented and no historical quote is repriced/backfilled.
create index booking_provider_completed_report_idx on public.booking(provider_id)
  where current_status = 'Completed';
create index booking_completion_report_idx on public.booking_status_history(booking_id,changed_at)
  where new_status = 'Completed';

create function public.provider_earnings(
  p_period text default 'thisMonth',
  p_before_at timestamptz default null,
  p_before_id uuid default null,
  p_as_of timestamptz default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_as_of timestamptz := coalesce(p_as_of,statement_timestamp());
  v_today date;
  v_start date;
  v_result jsonb;
begin
  if v_actor is null or not exists(select 1 from public.user_account
    where user_id=v_actor and role='provider') then
    raise exception 'Provider authentication required' using errcode='42501';
  end if;
  if p_period is null or p_period not in ('last30','thisMonth','allTime') or
     (p_before_at is null) <> (p_before_id is null) or
     (p_before_at is not null and p_as_of is null) or
     not isfinite(v_as_of) or v_as_of > statement_timestamp() or
     (p_before_at is not null and (not isfinite(p_before_at) or p_before_at > v_as_of)) then
    raise exception 'Invalid earnings range or cursor' using errcode='22023';
  end if;
  v_today := (v_as_of at time zone 'Asia/Kuala_Lumpur')::date;
  v_start := case p_period when 'last30' then v_today-29
    when 'thisMonth' then date_trunc('month',v_today)::date else null end;
  with completed as materialized (
    select b.booking_id,b.quoted_amount,b.quote_basis,b.quoted_rate,
      b.quoted_duration_minutes,b.requested_start_at,b.requested_end_at,
      p.unit_name,p.building_name,s.name as service_name,h.completed_at
    from public.booking b
    join public.property p on p.property_id=b.property_id
    join public.service_type s on s.service_type_id=b.service_type_id
    left join lateral (
      select min(changed_at) as completed_at from public.booking_status_history
      where booking_id=b.booking_id and new_status='Completed'
    ) h on true
    where b.provider_id=v_actor and b.current_status='Completed'
  ), scoped as materialized (
    select * from completed where completed_at<=v_as_of and
      (v_start is null or completed_at >= (v_start::timestamp at time zone 'Asia/Kuala_Lumpur'))
  ), settings as (
    select coalesce(v_start,(min(completed_at) at time zone 'Asia/Kuala_Lumpur')::date,v_today) as first_day,
      case when p_period='allTime' and
        min(completed_at) < ((v_today-interval '10 years')::timestamp at time zone 'Asia/Kuala_Lumpur')
        then 'year' else 'month' end as long_unit
    from scoped
  ), bucket_settings as (
    select case when p_period='allTime' then date_trunc(long_unit,first_day)::date else first_day end as first_day,
      long_unit from settings
  ), bucket_days as (
    select distinct case p_period when 'last30' then first_day+((day::date-first_day)/7)*7
      when 'thisMonth' then greatest(first_day,date_trunc('week',day)::date)
      else date_trunc(long_unit,day)::date end as bucket_start
    from bucket_settings, lateral generate_series(first_day::timestamp,v_today::timestamp,
      case when p_period='allTime' and long_unit='year' then interval '1 year'
        when p_period='allTime' then interval '1 month' else interval '1 day' end) day
  ), bucket_ranges as (
    select bucket_start,coalesce(lead(bucket_start) over(order by bucket_start),v_today+1) as bucket_end
    from bucket_days
  ), buckets as (
    select r.bucket_start,r.bucket_end,count(s.booking_id) as jobs,
      count(s.booking_id) filter(where s.quoted_amount is null) as unpriced_jobs,
      coalesce(sum(s.quoted_amount),0) as gross
    from bucket_ranges r left join scoped s on
      s.completed_at >= (r.bucket_start::timestamp at time zone 'Asia/Kuala_Lumpur') and
      s.completed_at < (r.bucket_end::timestamp at time zone 'Asia/Kuala_Lumpur')
    group by r.bucket_start,r.bucket_end
  ), candidates as materialized (
    select * from scoped where p_before_at is null or
      (completed_at,booking_id)<(p_before_at,p_before_id)
    order by completed_at desc,booking_id desc limit 21
  ), page as materialized (
    select * from candidates order by completed_at desc,booking_id desc limit 20
  )
  select jsonb_build_object(
    'provider_id',v_actor,'currency','MYR','period',p_period,'as_of',v_as_of,
    'start_day',(select first_day from settings),'end_day',v_today,
    'bucket_unit',case p_period when 'last30' then 'sevenDays' when 'thisMonth' then 'week'
      else (select long_unit from settings) end,
    'jobs', (select count(*) from scoped),
    'unpriced_jobs',(select count(*) from scoped where quoted_amount is null),
    'undated_jobs',(select count(*) from completed where completed_at is null),
    'gross',(select coalesce(sum(quoted_amount),0) from scoped),
    'buckets',coalesce((select jsonb_agg(to_jsonb(buckets) order by bucket_start) from buckets),'[]'::jsonb),
    'items',coalesce((select jsonb_agg(to_jsonb(page) order by completed_at desc,booking_id desc) from page),'[]'::jsonb),
    'next_cursor',case when (select count(*) from candidates)>20 then
      (select jsonb_build_object('timestamp',completed_at,'id',booking_id)
       from page order by completed_at,booking_id limit 1) else null end
  ) into v_result;
  return v_result;
end;
$$;
revoke all on function public.provider_earnings(text,timestamptz,uuid,timestamptz)
  from public,anon,authenticated,service_role;
grant execute on function public.provider_earnings(text,timestamptz,uuid,timestamptz) to authenticated;
