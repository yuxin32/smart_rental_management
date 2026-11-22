-- One thread per booking, not per display name. No contact/email/address leaks.
-- Active bookings can start an empty chat; closed bookings retain existing chat.
create function public.page_my_conversations(p_limit integer default 20,
  p_before_at timestamptz default null,p_before_id uuid default null,
  p_as_of timestamptz default null,p_search text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_as_of timestamptz;v_search text;v_result jsonb;
begin
  if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor) then
    raise exception 'Authentication required' using errcode='42501';end if;
  if p_limit is null or p_limit not between 1 and 50 or p_search is null or
     length(p_search)>80 or ((p_before_at is null)<>(p_before_id is null)) or
     (p_before_at is not null and p_as_of is null) then
    raise exception 'Invalid conversation page' using errcode='22023';end if;
  v_search:=lower(btrim(p_search));
  v_as_of:=least(coalesce(p_as_of,statement_timestamp()),statement_timestamp());
  if p_before_at>v_as_of then raise exception 'Invalid cursor' using errcode='22023';end if;
  with eligible as (
    select b.booking_id,b.current_status::text as status,
      case when b.owner_id=v_actor then coalesce(nullif(btrim(pp.full_name),''),'Cleaning Service Provider')
        else 'Property Owner' end as counterpart_name,
      p.unit_name,p.building_name,s.name as service_name,
      left(coalesce(m.body,''),160) as last_message,
      coalesce(m.created_at,b.created_at) as last_at
    from public.booking b join public.property p on p.property_id=b.property_id
      join public.service_type s on s.service_type_id=b.service_type_id
      left join public.provider_profile pp on pp.provider_id=b.provider_id
      left join lateral (
        select body,created_at from public.booking_message
        where booking_id=b.booking_id and created_at<=v_as_of
        order by created_at desc,message_id desc limit 1
      ) m on true
    where (b.owner_id=v_actor or b.provider_id=v_actor) and b.created_at<=v_as_of
      and (b.current_status in ('Accepted','In Progress') or m.created_at is not null)
  ), candidates as materialized (
    select * from eligible where (p_before_at is null or (last_at,booking_id)<(p_before_at,p_before_id))
      and (v_search='' or position(v_search in lower(counterpart_name||' '||unit_name||' '||building_name||' '||service_name))>0)
    order by last_at desc,booking_id desc limit p_limit+1
  ), visible as materialized (
    select * from candidates order by last_at desc,booking_id desc limit p_limit
  ) select jsonb_build_object('recipient_id',v_actor,'as_of',v_as_of,'search',btrim(p_search),
    'items',coalesce((select jsonb_agg(to_jsonb(v) order by last_at desc,booking_id desc) from visible v),'[]'::jsonb),
    'has_more',(select count(*) from candidates)>p_limit,
    'next_cursor',case when (select count(*) from candidates)>p_limit then
      (select jsonb_build_object('timestamp',last_at,'id',booking_id) from visible order by last_at,booking_id limit 1)
      else null end) into v_result;
  return v_result;
end;
$$;
revoke all on function public.page_my_conversations(integer,timestamptz,uuid,timestamptz,text)
  from public,anon,authenticated,service_role;
grant execute on function public.page_my_conversations(integer,timestamptz,uuid,timestamptz,text) to authenticated;
