-- In-app notifications are real, existing booking events, not fabricated alerts.
-- Receipts are private per user; no direct client table grants or write events.
create table app_private.notification_read (
  user_id uuid not null references public.user_account(user_id) on delete cascade,
  event_id uuid not null references public.booking_status_history(status_history_id) on delete cascade,
  read_at timestamptz not null default statement_timestamp(),
  primary key(user_id,event_id)
);
alter table app_private.notification_read enable row level security;
revoke all on table app_private.notification_read from public,anon,authenticated,service_role;

create function app_private.notification_events(p_actor uuid)
returns table(id uuid,booking_id uuid,event_status text,happened_at timestamptz,
  unit_name text,building_name text,service_name text,is_read boolean,actionable boolean)
language sql stable set search_path='' as $$
  select h.status_history_id,b.booking_id,h.new_status::text,h.changed_at,
    p.unit_name,p.building_name,s.name,(r.event_id is not null),
    ((b.provider_id=p_actor and b.current_status='Pending' and h.new_status='Pending') or
     (b.owner_id=p_actor and b.current_status='Completed' and h.new_status='Completed' and
      not exists(select 1 from public.booking_review v where v.booking_id=b.booking_id)))
  from public.booking_status_history h join public.booking b on b.booking_id=h.booking_id
  join public.property p on p.property_id=b.property_id
  join public.service_type s on s.service_type_id=b.service_type_id
  left join app_private.notification_read r on r.user_id=p_actor and r.event_id=h.status_history_id
  where (b.owner_id=p_actor or b.provider_id=p_actor) and h.changed_by_user_id<>p_actor;
$$;
revoke all on function app_private.notification_events(uuid) from public,anon,authenticated,service_role;

create function public.page_my_notifications(p_filter text default 'all',p_limit integer default 20,
  p_before_at timestamptz default null,p_before_id uuid default null,p_as_of timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_as_of timestamptz;v_result jsonb;
begin
  if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor) then
    raise exception 'Authentication required' using errcode='42501';end if;
  if p_filter is null or p_filter not in ('all','unread','action') or p_limit is null or p_limit not between 1 and 50 or
     ((p_before_at is null)<>(p_before_id is null)) then
    raise exception 'Invalid notification page' using errcode='22023';end if;
  v_as_of:=least(coalesce(p_as_of,statement_timestamp()),statement_timestamp());
  with eligible as materialized (
    select * from app_private.notification_events(v_actor) where happened_at<=v_as_of
  ), candidates as materialized (
    select * from eligible where (p_filter='all' or (p_filter='unread' and not is_read) or
      (p_filter='action' and actionable)) and
      (p_before_at is null or (happened_at,id)<(p_before_at,p_before_id))
    order by happened_at desc,id desc limit p_limit+1
  ), visible as materialized (
    select * from candidates order by happened_at desc,id desc limit p_limit
  ) select jsonb_build_object('recipient_id',v_actor,'as_of',v_as_of,'filter',p_filter,
    'total_count',(select count(*) from eligible),
    'unread_count',(select count(*) from eligible where not is_read),
    'action_count',(select count(*) from eligible where actionable),
    'items',coalesce((select jsonb_agg(to_jsonb(v) order by happened_at desc,id desc) from visible v),'[]'::jsonb),
    'next_cursor',case when (select count(*) from candidates)>p_limit then
      (select jsonb_build_object('timestamp',happened_at,'id',id) from visible order by happened_at,id limit 1)
      else null end) into v_result;
  return v_result;
end;
$$;
revoke all on function public.page_my_notifications(text,integer,timestamptz,uuid,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.page_my_notifications(text,integer,timestamptz,uuid,timestamptz) to authenticated;

create function public.read_my_notifications(p_ids uuid[] default null,p_through_at timestamptz default null)
returns integer language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_count integer;
begin
  if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor) then
    raise exception 'Authentication required' using errcode='42501';end if;
  -- Explicit IDs OR a server-snapshot boundary; never a recipient supplied by App.
  if (p_ids is null)=(p_through_at is null) or
     (p_ids is not null and (cardinality(p_ids) not between 1 and 100 or array_position(p_ids,null) is not null)) then
    raise exception 'Specify notification IDs or a snapshot boundary' using errcode='22023';end if;
  if p_ids is not null and exists(select 1 from unnest(p_ids) i where
    not exists(select 1 from app_private.notification_events(v_actor) e where e.id=i)) then
    raise exception 'Notification unavailable' using errcode='42501';end if;
  insert into app_private.notification_read(user_id,event_id)
    select v_actor,id from app_private.notification_events(v_actor)
    where not is_read and ((p_ids is not null and id=any(p_ids)) or
      (p_through_at is not null and happened_at<=least(p_through_at,statement_timestamp())))
    on conflict do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function public.read_my_notifications(uuid[],timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.read_my_notifications(uuid[],timestamptz) to authenticated;
