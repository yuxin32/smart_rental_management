-- Own-account receipts only. No peer read-status disclosure or new table grants.
create table app_private.message_read_receipt (
 recipient_id uuid not null references public.user_account(user_id) on delete cascade,
 message_id uuid not null references public.booking_message(message_id) on delete cascade,
 read_at timestamptz not null default clock_timestamp(),
 primary key(recipient_id,message_id)
);
alter table app_private.message_read_receipt enable row level security;
revoke all on app_private.message_read_receipt from public,anon,authenticated,service_role;
create index booking_message_thread_inbound on public.booking_message(booking_id,sender_user_id,created_at,message_id);

create function public.read_booking_messages(p_booking_id uuid,p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); n integer;
begin
 if actor is null or not exists(select 1 from public.booking where booking_id=p_booking_id
  and actor in(owner_id,provider_id)) then
  raise exception 'Booking participant required' using errcode='42501';end if;
 if p_ids is null or cardinality(p_ids) not between 1 and 50 or array_position(p_ids,null) is not null or
  cardinality(p_ids)<>(select count(distinct id) from unnest(p_ids) id) then
  raise exception 'Select up to 50 distinct received messages' using errcode='22023';end if;
 select count(*) into n from public.booking_message where booking_id=p_booking_id
  and message_id=any(p_ids) and sender_user_id<>actor;
 if n<>cardinality(p_ids) then
  raise exception 'Only received messages in this booking can be read' using errcode='42501';end if;
 insert into app_private.message_read_receipt(recipient_id,message_id)
  select actor,message_id from public.booking_message where booking_id=p_booking_id and message_id=any(p_ids)
  on conflict do nothing;
 return jsonb_build_object('recipient_id',actor,'booking_id',p_booking_id,'acknowledged',n);
end;$$;
revoke all on function public.read_booking_messages(uuid,uuid[]) from public,anon,authenticated,service_role;
grant execute on function public.read_booking_messages(uuid,uuid[]) to authenticated;

create function public.my_message_unread()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 if actor is null or not exists(select 1 from public.user_account where user_id=actor) then
  raise exception 'Authentication required' using errcode='42501';end if;
 select jsonb_build_object('recipient_id',actor,'messages',count(*),'threads',count(distinct m.booking_id)) into result
 from public.booking_message m join public.booking b using(booking_id)
 where actor in(b.owner_id,b.provider_id) and m.sender_user_id<>actor
  and not exists(select 1 from app_private.message_read_receipt r where r.recipient_id=actor and r.message_id=m.message_id);
 return result;
end;$$;
revoke all on function public.my_message_unread() from public,anon,authenticated,service_role;
grant execute on function public.my_message_unread() to authenticated;

-- Retain the original five-argument RPC contract. A separate unread endpoint
-- avoids ambiguous defaulted overloads; both use the same private projection.
alter function public.page_my_conversations(integer,timestamptz,uuid,timestamptz,text) set schema app_private;
alter function app_private.page_my_conversations(integer,timestamptz,uuid,timestamptz,text) rename to page_conversations_v23;
revoke all on function app_private.page_conversations_v23(integer,timestamptz,uuid,timestamptz,text)
 from public,anon,authenticated,service_role;
create function app_private.page_conversations_with_reads(p_limit integer,p_before_at timestamptz,p_before_id uuid,
 p_as_of timestamptz,p_search text,p_unread_only boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); boundary timestamptz; term text; result jsonb;
begin
 if actor is null or not exists(select 1 from public.user_account where user_id=actor) then
  raise exception 'Authentication required' using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 50 or p_search is null or length(p_search)>80 or
  ((p_before_at is null)<>(p_before_id is null)) or (p_before_at is not null and p_as_of is null) or
  (p_as_of is not null and (not isfinite(p_as_of) or p_as_of>statement_timestamp())) then
  raise exception 'Invalid conversation page' using errcode='22023';end if;
 boundary:=coalesce(p_as_of,statement_timestamp()); term:=lower(btrim(p_search));
 if p_before_at>boundary then raise exception 'Invalid cursor' using errcode='22023';end if;
 with eligible as (
  select b.booking_id,b.current_status::text as status,
   case when b.owner_id=actor then coalesce(nullif(btrim(pp.full_name),''),'Cleaning Service Provider')
    else 'Property Owner' end as counterpart_name,p.unit_name,p.building_name,s.name as service_name,
   left(coalesce(last.body,''),160) as last_message,coalesce(last.created_at,b.created_at) as last_at,
   (select count(*) from public.booking_message m where m.booking_id=b.booking_id and m.sender_user_id<>actor
     and m.created_at<=boundary and not exists(select 1 from app_private.message_read_receipt r
      where r.recipient_id=actor and r.message_id=m.message_id and r.read_at<=boundary)) as unread_count
  from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
   left join public.provider_profile pp on pp.provider_id=b.provider_id
   left join lateral(select body,created_at from public.booking_message where booking_id=b.booking_id
    and created_at<=boundary order by created_at desc,message_id desc limit 1) last on true
  where actor in(b.owner_id,b.provider_id) and b.created_at<=boundary
   and (b.current_status in('Accepted','In Progress') or last.created_at is not null)
 ), candidates as materialized (
  select * from eligible where (p_before_at is null or (last_at,booking_id)<(p_before_at,p_before_id))
   and (not p_unread_only or unread_count>0)
   and (term='' or position(term in lower(counterpart_name||' '||unit_name||' '||building_name||' '||service_name))>0)
  order by last_at desc,booking_id desc limit p_limit+1
 ), visible as materialized(select * from candidates order by last_at desc,booking_id desc limit p_limit)
 select jsonb_build_object('recipient_id',actor,'as_of',boundary,'search',btrim(p_search),'unread_only',p_unread_only,
  'items',coalesce((select jsonb_agg(to_jsonb(v) order by last_at desc,booking_id desc) from visible v),'[]'::jsonb),
  'has_more',(select count(*) from candidates)>p_limit,
  'next_cursor',case when (select count(*) from candidates)>p_limit then
    (select jsonb_build_object('timestamp',last_at,'id',booking_id) from visible order by last_at,booking_id limit 1) else null end,
  'unread_total',(select coalesce(sum(unread_count),0) from eligible)) into result;
 return result;
end;$$;
revoke all on function app_private.page_conversations_with_reads(integer,timestamptz,uuid,timestamptz,text,boolean)
 from public,anon,authenticated,service_role;
create function public.page_my_conversations(p_limit integer default 20,p_before_at timestamptz default null,
 p_before_id uuid default null,p_as_of timestamptz default null,p_search text default '')
returns jsonb language sql stable security definer set search_path='' as $$
 select app_private.page_conversations_with_reads(p_limit,p_before_at,p_before_id,p_as_of,p_search,false);
$$;
create function public.page_my_unread_conversations(p_limit integer default 20,p_before_at timestamptz default null,
 p_before_id uuid default null,p_as_of timestamptz default null,p_search text default '')
returns jsonb language sql stable security definer set search_path='' as $$
 select app_private.page_conversations_with_reads(p_limit,p_before_at,p_before_id,p_as_of,p_search,true);
$$;
revoke all on function public.page_my_conversations(integer,timestamptz,uuid,timestamptz,text),
 public.page_my_unread_conversations(integer,timestamptz,uuid,timestamptz,text) from public,anon,authenticated,service_role;
grant execute on function public.page_my_conversations(integer,timestamptz,uuid,timestamptz,text),
 public.page_my_unread_conversations(integer,timestamptz,uuid,timestamptz,text) to authenticated;
