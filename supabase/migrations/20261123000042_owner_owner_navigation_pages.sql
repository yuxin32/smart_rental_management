-- Owner navigation reads. Filter before paging; expose only approved directory
-- profile fields. No new table grants or changes to booking write operations.
create function public.page_owner_booking_search(
 p_query text default '', p_group text default 'all', p_limit integer default 20,
 p_before_at timestamptz default null, p_before_id uuid default null,
 p_oldest boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); rows jsonb; term text:=lower(btrim(coalesce(p_query,'')));
begin
 if actor is null or not exists(select 1 from public.user_account where user_id=actor and role='owner') then
  raise exception 'Owner authentication required' using errcode='42501'; end if;
 if length(term)>80 or p_group is null or p_group not in ('all','pending','ongoing','history','completed','cancelled','declined')
  or p_limit is null or p_limit not between 1 and 50 or p_oldest is null
  or (p_before_at is null)<>(p_before_id is null) then
  raise exception 'Invalid search request' using errcode='22023'; end if;
 select coalesce(jsonb_agg(card order by
  case when p_oldest then created_at end asc,case when not p_oldest then created_at end desc,
  case when p_oldest then booking_id end asc,case when not p_oldest then booking_id end desc),'[]'::jsonb)
 into rows from (
  select b.created_at,b.booking_id,to_jsonb(b)||jsonb_build_object('unit_name',p.unit_name,
   'building_name',p.building_name,'property_address',p.address,'service_name',s.name) card
  from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
  where b.owner_id=actor and (p_group='all'
   or (p_group='pending' and b.current_status='Pending')
   or (p_group='ongoing' and b.current_status in ('Accepted','In Progress'))
   or (p_group='history' and b.current_status in ('Completed','Cancelled','Declined'))
   or (p_group='completed' and b.current_status='Completed')
   or (p_group='cancelled' and b.current_status='Cancelled')
   or (p_group='declined' and b.current_status='Declined'))
  and (term='' or strpos(lower(p.unit_name||' '||p.building_name||' '||s.name),term)>0)
  and (p_before_at is null or (not p_oldest and (b.created_at,b.booking_id)<(p_before_at,p_before_id))
    or (p_oldest and (b.created_at,b.booking_id)>(p_before_at,p_before_id)))
  order by case when p_oldest then b.created_at end asc,case when not p_oldest then b.created_at end desc,
   case when p_oldest then b.booking_id end asc,case when not p_oldest then b.booking_id end desc
  limit p_limit+1
 ) bounded;
 return public.pack_cursor_page(rows,p_limit,'created_at','booking_id')||jsonb_build_object('actor_id',actor);
end;$$;

create function public.page_approved_provider_directory(
 p_query text default '', p_limit integer default 20,
 p_before_at timestamptz default null, p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); rows jsonb; term text:=lower(btrim(coalesce(p_query,'')));
begin
 if actor is null or not exists(select 1 from public.user_account where user_id=actor and role='owner') then
  raise exception 'Owner authentication required' using errcode='42501'; end if;
 if length(term)>80 or p_limit is null or p_limit not between 1 and 50
  or (p_before_at is null)<>(p_before_id is null) then
  raise exception 'Invalid directory request' using errcode='22023'; end if;
 select coalesce(jsonb_agg(card order by listed_at desc,provider_id desc),'[]'::jsonb) into rows from (
  select a.created_at listed_at,p.provider_id,jsonb_build_object(
   'provider_id',p.provider_id,'listed_at',a.created_at,'full_name',p.full_name,
   'bio',p.bio,'service_area',p.service_area,'hourly_rate',p.hourly_rate,'daily_rate',p.daily_rate,
   'rating_average',p.rating_average,'completed_job_count',p.completed_job_count,
   'services',coalesce((select jsonb_agg(jsonb_build_object('name',s.name,'description',s.description) order by s.name)
    from public.provider_capability c join public.service_type s using(service_type_id)
    where c.provider_id=p.provider_id),'[]'::jsonb)) card
  from public.provider_profile p join public.user_account a on a.user_id=p.provider_id
  where p.approval_status='approved' and (term=''
   or strpos(lower(coalesce(p.full_name,'')||' '||p.service_area),term)>0
   or exists(select 1 from public.provider_capability c join public.service_type s using(service_type_id)
    where c.provider_id=p.provider_id and strpos(lower(s.name),term)>0))
  and (p_before_at is null or (a.created_at,p.provider_id)<(p_before_at,p_before_id))
  order by a.created_at desc,p.provider_id desc limit p_limit+1
 ) bounded;
 return public.pack_cursor_page(rows,p_limit,'listed_at','provider_id')||jsonb_build_object('actor_id',actor);
end;$$;
revoke all on function public.page_owner_booking_search(text,text,integer,timestamptz,uuid,boolean),
 public.page_approved_provider_directory(text,integer,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.page_owner_booking_search(text,text,integer,timestamptz,uuid,boolean),
 public.page_approved_provider_directory(text,integer,timestamptz,uuid) to authenticated;
