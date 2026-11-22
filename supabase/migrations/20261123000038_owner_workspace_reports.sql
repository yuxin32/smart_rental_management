-- Read-only reports. Saved completed quote value is not a paid transaction.
create function public.owner_spending(p_period text default 'allTime',p_before_at timestamptz default null,
 p_before_id uuid default null,p_as_of timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_as_of timestamptz:=coalesce(p_as_of,statement_timestamp());v_start date;v_month date;v_result jsonb;
begin
 if not exists(select 1 from public.user_account where user_id=v_actor and role='owner') then
  raise exception 'Owner authentication required' using errcode='42501';end if;
 if p_period is null or p_period not in ('last30','thisMonth','allTime') or
  (p_before_at is null)<>(p_before_id is null) or (p_before_at is not null and p_as_of is null) or
  not isfinite(v_as_of) or v_as_of>statement_timestamp() or p_before_at>v_as_of then
  raise exception 'Invalid spending range' using errcode='22023';end if;
 v_month:=date_trunc('month',v_as_of at time zone 'Asia/Kuala_Lumpur')::date;
 v_start:=case p_period when 'thisMonth' then v_month when 'last30' then (v_as_of at time zone 'Asia/Kuala_Lumpur')::date-29 else null end;
 with completed as materialized (
  select b.booking_id,b.provider_id,b.quoted_amount,p.unit_name,p.building_name,s.name as service_name,
   coalesce(nullif(btrim(pp.full_name),''),'Cleaning Service Provider') as provider_name,h.completed_at
  from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
   left join public.provider_profile pp on pp.provider_id=b.provider_id
   left join lateral (select min(changed_at) as completed_at from public.booking_status_history
    where booking_id=b.booking_id and new_status='Completed') h on true
  where b.owner_id=v_actor and b.current_status='Completed'
 ), dated as materialized (select * from completed where completed_at<=v_as_of),
 scoped as materialized (select * from dated where v_start is null or completed_at>=(v_start::timestamp at time zone 'Asia/Kuala_Lumpur')),
 candidates as materialized (select * from scoped where p_before_at is null or (completed_at,booking_id)<(p_before_at,p_before_id)
  order by completed_at desc,booking_id desc limit 21),
 page as materialized (select * from candidates order by completed_at desc,booking_id desc limit 20),
 providers as (select provider_id,provider_name,count(*) as jobs,coalesce(sum(quoted_amount),0) as gross
  from scoped group by provider_id,provider_name order by gross desc,provider_id limit 10)
 select jsonb_build_object('actor_id',v_actor,'as_of',v_as_of,'period',p_period,'currency','MYR',
  'gross',(select coalesce(sum(quoted_amount),0) from scoped),'jobs',(select count(*) from scoped),
  'unpriced',(select count(*) from scoped where quoted_amount is null),'undated',(select count(*) from completed where completed_at is null),
  'this_month',(select coalesce(sum(quoted_amount),0) from dated where completed_at>=(v_month::timestamp at time zone 'Asia/Kuala_Lumpur')),
  'last_month',(select coalesce(sum(quoted_amount),0) from dated where completed_at>=((v_month-interval '1 month')::timestamp at time zone 'Asia/Kuala_Lumpur')
   and completed_at<(v_month::timestamp at time zone 'Asia/Kuala_Lumpur')),
  'providers',coalesce((select jsonb_agg(to_jsonb(providers) order by gross desc,provider_id) from providers),'[]'::jsonb),
  'items',coalesce((select jsonb_agg(to_jsonb(page) order by completed_at desc,booking_id desc) from page),'[]'::jsonb),
  'next_cursor',case when (select count(*) from candidates)>20 then
   (select jsonb_build_object('timestamp',completed_at,'id',booking_id) from page order by completed_at,booking_id limit 1) else null end)
 into v_result;return v_result;
end;$$;
revoke all on function public.owner_spending(text,timestamptz,uuid,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.owner_spending(text,timestamptz,uuid,timestamptz) to authenticated;

create function public.my_provider_statistics() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_as_of timestamptz:=statement_timestamp();v_week date;v_result jsonb;
begin
 if not exists(select 1 from public.user_account where user_id=v_actor and role='provider') then
  raise exception 'Provider authentication required' using errcode='42501';end if;
 v_week:=date_trunc('week',v_as_of at time zone 'Asia/Kuala_Lumpur')::date;
 with jobs as materialized (
  select b.booking_id,b.owner_id,b.current_status,b.created_at,
   (select min(changed_at) from public.booking_status_history where booking_id=b.booking_id and new_status='Completed' and changed_at<=v_as_of) as completed_at,
   exists(select 1 from public.booking_status_history where booking_id=b.booking_id and new_status='Accepted' and changed_at<=v_as_of) as ever_accepted,
   d.new_status as decision,d.changed_at as decided_at
  from public.booking b left join lateral (
   select new_status,changed_at from public.booking_status_history where booking_id=b.booking_id and
    changed_by_user_id=v_actor and new_status in ('Accepted','Declined') and changed_at<=v_as_of
   order by changed_at,status_history_id limit 1) d on true
  where b.provider_id=v_actor and b.created_at<=v_as_of
 ), weeks as (
  select (v_week-n*7)::date as week_start,(select count(*) from jobs where current_status='Completed' and
    completed_at>=((v_week-n*7)::timestamp at time zone 'Asia/Kuala_Lumpur') and
    completed_at<((v_week-n*7+7)::timestamp at time zone 'Asia/Kuala_Lumpur')) as jobs
  from generate_series(7,0,-1) n
 ), ratings as (select rating,count(*) as count from public.booking_review where provider_id=v_actor group by rating)
 select jsonb_build_object('actor_id',v_actor,'as_of',v_as_of,'total',(select count(*) from jobs),
  'accepted',(select count(*) from jobs where ever_accepted),'completed',(select count(*) from jobs where current_status='Completed'),
  'closed_other',(select count(*) from jobs where current_status in ('Cancelled','Declined')),
  'decisions',(select count(*) from jobs where decision is not null),'accepted_decisions',(select count(*) from jobs where decision='Accepted'),
  'response_minutes',(select round(avg(extract(epoch from(decided_at-created_at))/60),1) from jobs where decided_at>=created_at),
  'repeat_jobs',(select coalesce(sum(greatest(n-1,0)),0) from (select count(*) as n from jobs where current_status='Completed' group by owner_id) r),
  'weeks',(select jsonb_agg(to_jsonb(weeks) order by week_start) from weeks),
  'ratings',coalesce((select jsonb_object_agg(rating,count) from ratings),'{}'::jsonb),
  'undated_completions',(select count(*) from jobs where current_status='Completed' and completed_at is null)) into v_result;
 return v_result;
end;$$;
revoke all on function public.my_provider_statistics() from public,anon,authenticated,service_role;
grant execute on function public.my_provider_statistics() to authenticated;
