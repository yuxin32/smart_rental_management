-- Read-only, participant-scoped keyset pages. Timestamps retain PostgreSQL
-- precision; UUID is the tie breaker. A page never returns more than 50 rows.
create index booking_owner_cursor_idx on public.booking(owner_id,created_at desc,booking_id desc);
create index booking_provider_cursor_idx on public.booking(provider_id,created_at desc,booking_id desc);
create index booking_history_cursor_idx on public.booking_status_history(booking_id,changed_at desc,status_history_id desc);

create function public.pack_cursor_page(p_rows jsonb,p_limit integer,p_time_field text,p_id_field text)
returns jsonb language sql immutable set search_path='' as $$
  select jsonb_build_object('items',coalesce((select jsonb_agg(value order by ordinal)
    from jsonb_array_elements(p_rows) with ordinality as r(value,ordinal) where ordinal<=p_limit),'[]'::jsonb),
    'has_more',jsonb_array_length(p_rows)>p_limit,
    'next_cursor',case when jsonb_array_length(p_rows)>p_limit then
      jsonb_build_object('timestamp',p_rows->(p_limit-1)->p_time_field,'id',p_rows->(p_limit-1)->p_id_field) else null end);
$$;
revoke all on function public.pack_cursor_page(jsonb,integer,text,text) from public,anon,authenticated;

create function public.page_my_bookings(p_limit integer default 20,p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_limit is null or p_limit not between 1 and 50 or (p_before_at is null)<>(p_before_id is null) then
    raise exception 'Invalid pagination request' using errcode='22023'; end if;
  select coalesce(jsonb_agg(card order by created_at desc,booking_id desc),'[]'::jsonb) into rows from (
    select b.created_at,b.booking_id,to_jsonb(b)||jsonb_build_object(
      'unit_name',p.unit_name,'building_name',p.building_name,'property_address',p.address,'service_name',s.name) as card
    from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
    where (b.owner_id=auth.uid() or b.provider_id=auth.uid()) and
      (p_before_at is null or (b.created_at,b.booking_id)<(p_before_at,p_before_id))
    order by b.created_at desc,b.booking_id desc limit p_limit+1
  ) bounded;
  return public.pack_cursor_page(rows,p_limit,'created_at','booking_id');
end $$;

create function public.booking_cards_by_ids(p_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_ids is null or cardinality(p_ids) not between 1 and 50 then
    raise exception 'Request 1 to 50 IDs' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('unit_name',p.unit_name,
    'building_name',p.building_name,'property_address',p.address,'service_name',s.name)),'[]'::jsonb) into rows
  from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
  where b.booking_id=any(p_ids) and (b.owner_id=auth.uid() or b.provider_id=auth.uid());
  return rows;
end $$;

create function public.page_booking_messages(p_booking_id uuid,p_limit integer default 20,
  p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
  if auth.uid() is null or not exists(select 1 from public.booking where booking_id=p_booking_id
    and auth.uid() in (owner_id,provider_id)) then
    raise exception 'Booking participant required' using errcode='42501'; end if;
  if p_limit is null or p_limit not between 1 and 50 or (p_before_at is null)<>(p_before_id is null) then
    raise exception 'Invalid pagination request' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at desc,m.message_id desc),'[]'::jsonb) into rows from (
    select message_id,booking_id,sender_user_id,body,created_at from public.booking_message
    where booking_id=p_booking_id and (p_before_at is null or (created_at,message_id)<(p_before_at,p_before_id))
    order by created_at desc,message_id desc limit p_limit+1
  ) m;
  return public.pack_cursor_page(rows,p_limit,'created_at','message_id');
end $$;

create function public.page_booking_history(p_booking_id uuid,p_limit integer default 20,
  p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
  if auth.uid() is null or not exists(select 1 from public.booking where booking_id=p_booking_id
    and auth.uid() in (owner_id,provider_id)) then
    raise exception 'Booking participant required' using errcode='42501'; end if;
  if p_limit is null or p_limit not between 1 and 50 or (p_before_at is null)<>(p_before_id is null) then
    raise exception 'Invalid pagination request' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(h) order by h.changed_at desc,h.status_history_id desc),'[]'::jsonb) into rows from (
    select * from public.booking_status_history where booking_id=p_booking_id and
      (p_before_at is null or (changed_at,status_history_id)<(p_before_at,p_before_id))
    order by changed_at desc,status_history_id desc limit p_limit+1
  ) h;
  return public.pack_cursor_page(rows,p_limit,'changed_at','status_history_id');
end $$;

create function public.owner_dashboard_summary()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if auth.uid() is null or not exists(select 1 from public.user_account where user_id=auth.uid() and role='owner') then
    raise exception 'Owner required' using errcode='42501'; end if;
  select jsonb_build_object('property_count',(select count(*) from public.property where owner_id=auth.uid()),
    'pending_count',count(*) filter(where current_status='Pending'),
    'active_count',count(*) filter(where current_status in ('Accepted','In Progress')),
    'completed_count',count(*) filter(where current_status='Completed')) into result
  from public.booking where owner_id=auth.uid();
  return result;
end $$;

revoke all on function public.page_my_bookings(integer,timestamptz,uuid) from public,anon;
revoke all on function public.booking_cards_by_ids(uuid[]) from public,anon;
revoke all on function public.page_booking_messages(uuid,integer,timestamptz,uuid) from public,anon;
revoke all on function public.page_booking_history(uuid,integer,timestamptz,uuid) from public,anon;
revoke all on function public.owner_dashboard_summary() from public,anon;
grant execute on function public.page_my_bookings(integer,timestamptz,uuid),public.booking_cards_by_ids(uuid[]),
  public.page_booking_messages(uuid,integer,timestamptz,uuid),public.page_booking_history(uuid,integer,timestamptz,uuid),
  public.owner_dashboard_summary() to authenticated;
