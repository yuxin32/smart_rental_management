-- Ported from 202610290032_location_matching_alternatives.sql; shared integrated names/roles are preserved.
-- V1 service-area coverage and optional user-confirmed map pins. Coordinates
-- stay private; Owner matching returns only rounded approximate distances.
create table app_private.service_area (
 id text primary key, name text not null, parent_id text references app_private.service_area(id)
);
insert into app_private.service_area values
 ('my-kl','Kuala Lumpur',null),('my-selangor','Selangor',null),
 ('my-kl-setapak','Setapak, Kuala Lumpur','my-kl'),
 ('my-kl-wangsa-maju','Wangsa Maju, Kuala Lumpur','my-kl'),
 ('my-kl-sentul','Sentul, Kuala Lumpur','my-kl'),
 ('my-kl-kepong','Kepong, Kuala Lumpur','my-kl'),
 ('my-kl-cheras','Cheras, Kuala Lumpur','my-kl'),
 ('my-sgr-pj','Petaling Jaya, Selangor','my-selangor'),
 ('my-sgr-subang','Subang Jaya, Selangor','my-selangor'),
 ('my-sgr-shah-alam','Shah Alam, Selangor','my-selangor'),
 ('my-sgr-puchong','Puchong, Selangor','my-selangor'),
 ('my-sgr-cheras','Cheras, Selangor','my-selangor');
create table app_private.property_location (
 property_id uuid primary key references public.property(property_id) on delete cascade,
 area_id text not null references app_private.service_area(id),
 address_snapshot text not null, pin_link text,
 latitude double precision, longitude double precision,
 check ((latitude is null and longitude is null) or
        (latitude is not null and longitude is not null and latitude between -90 and 90 and longitude between -180 and 180))
);
create table app_private.provider_location (
 provider_id uuid primary key references public.provider_profile(provider_id) on delete cascade,
 area_ids text[] not null, origin_snapshot text not null, pin_link text,
 latitude double precision, longitude double precision,
 check (cardinality(area_ids) between 1 and 20),
 check ((latitude is null and longitude is null) or
        (latitude is not null and longitude is not null and latitude between -90 and 90 and longitude between -180 and 180))
);
alter table app_private.service_area enable row level security;
alter table app_private.property_location enable row level security;
alter table app_private.provider_location enable row level security;
revoke all on app_private.service_area,app_private.property_location,app_private.provider_location
 from public,anon,authenticated,service_role;

create function app_private.read_map_pin(p_link text) returns jsonb
language plpgsql immutable set search_path='' as $$
declare v text:=nullif(btrim(p_link),'');m text[];lat double precision;lon double precision;
begin
 if v is null then return jsonb_build_object('latitude',null,'longitude',null,'pin_link',null);end if;
 if length(v)>2048 or v !~ '^https://(www\.google\.com|google\.com|maps\.google\.com|www\.google\.com\.my)/' then
  raise exception 'Use a full Google Maps pin link' using errcode='22023';end if;
 -- A map viewport (@lat,lon) is deliberately not treated as a property pin.
 m:=regexp_match(v,'!3d(-?[0-9]+\.[0-9]+)!4d(-?[0-9]+\.[0-9]+)');
 if m is null then
  m:=regexp_match(v,'[?&](?:q|query)=(-?[0-9]+(?:\.[0-9]+)?)(?:,|%2[Cc])\s*(-?[0-9]+(?:\.[0-9]+)?)(?:&|$)');
 end if;
 if m is null then raise exception 'The map link needs a selected pin, not just a map view' using errcode='22023';end if;
 lat:=m[1]::double precision;lon:=m[2]::double precision;
 if not(lat between -90 and 90 and lon between -180 and 180) then
  raise exception 'Invalid map pin' using errcode='22023';end if;
 return jsonb_build_object('latitude',lat,'longitude',lon,'pin_link',v);
end;$$;
revoke all on function app_private.read_map_pin(text) from public,anon,authenticated,service_role;

create function public.list_service_areas() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501';end if;
 return (select jsonb_agg(jsonb_build_object('id',id,'name',name,'parent_id',parent_id) order by name)
  from app_private.service_area);
end;$$;
revoke all on function public.list_service_areas() from public,anon,authenticated,service_role;
grant execute on function public.list_service_areas() to authenticated;

create function app_private.area_covered(p_area text,p_coverage text[]) returns boolean
language sql stable set search_path='' as $$
 with recursive ancestors as (
  select id,parent_id from app_private.service_area where id=p_area
  union all select a.id,a.parent_id from app_private.service_area a join ancestors b on a.id=b.parent_id
 ) select exists(select 1 from ancestors where id=any(p_coverage));
$$;
revoke all on function app_private.area_covered(text,text[]) from public,anon,authenticated,service_role;

create function app_private.location_gate(p_property uuid,p_provider uuid) returns text
language sql stable set search_path='' as $$
 select case when l.property_id is null or l.address_snapshot<>p.address then 'rental_location_missing'
  when v.provider_id is null or not app_private.area_covered(l.area_id,v.area_ids) then 'provider_area'
  else null end from public.property p
 left join app_private.property_location l on l.property_id=p.property_id
 left join app_private.provider_location v on v.provider_id=p_provider
 where p.property_id=p_property;
$$;
revoke all on function app_private.location_gate(uuid,uuid) from public,anon,authenticated,service_role;

create function public.my_property_location(p_property_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r jsonb;
begin
 if not exists(select 1 from public.property p join public.user_account a on a.user_id=p.owner_id
  where p.property_id=p_property_id and p.owner_id=auth.uid() and a.role='owner') then
  raise exception 'Property unavailable' using errcode='42501';end if;
 select jsonb_build_object('area_id',l.area_id,'area_name',a.name,'pin_link',l.pin_link)
 into r from app_private.property_location l join app_private.service_area a on a.id=l.area_id
 join public.property p using(property_id)
 where l.property_id=p_property_id and l.address_snapshot=p.address;
 return coalesce(r,'{}'::jsonb);
end;$$;
revoke all on function public.my_property_location(uuid) from public,anon,authenticated,service_role;
grant execute on function public.my_property_location(uuid) to authenticated;

create function public.list_my_property_locations() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.user_account where user_id=auth.uid() and role='owner') then
  raise exception 'Owner required' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('property_id',p.property_id,
  'location',public.my_property_location(p.property_id))) from public.property p where p.owner_id=auth.uid()),'[]'::jsonb);
end;$$;
revoke all on function public.list_my_property_locations() from public,anon,authenticated,service_role;
grant execute on function public.list_my_property_locations() to authenticated;

create function app_private.put_property_location(p_property uuid,p_area text,p_pin text) returns void
language plpgsql set search_path='' as $$
declare addr text;pin jsonb;
begin
 select address into addr from public.property where property_id=p_property and owner_id=auth.uid();
 if addr is null then raise exception 'Property unavailable' using errcode='42501';end if;
 if p_area is null or not exists(select 1 from app_private.service_area where id=p_area) then
  raise exception 'Choose a supported rental service area' using errcode='22023';end if;
 pin:=app_private.read_map_pin(p_pin);
 if exists(select 1 from public.booking where property_id=p_property and current_status in('Accepted','In Progress')
  and requested_end_at>clock_timestamp()) and exists(
   select 1 from app_private.property_location l where l.property_id=p_property and
    (l.area_id is distinct from p_area or l.pin_link is distinct from pin->>'pin_link' or l.address_snapshot<>addr)) then
  raise exception 'A confirmed booking still uses this rental location' using errcode='23514';end if;
 insert into app_private.property_location values(p_property,p_area,addr,pin->>'pin_link',
  (pin->>'latitude')::double precision,(pin->>'longitude')::double precision)
 on conflict(property_id) do update set area_id=excluded.area_id,address_snapshot=excluded.address_snapshot,
  pin_link=excluded.pin_link,latitude=excluded.latitude,longitude=excluded.longitude;
end;$$;
revoke all on function app_private.put_property_location(uuid,text,text) from public,anon,authenticated,service_role;

create function public.save_property_location(p_property_id uuid,p_revision bigint,p_area_id text,p_pin_link text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r bigint;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('property-location:'||p_property_id,0));
 select property_revision into r from public.property where property_id=p_property_id and owner_id=auth.uid() for update;
 if r is null then raise exception 'Property unavailable' using errcode='42501';end if;
 if p_revision is null or r<>p_revision then raise exception 'Property changed. Reload before saving' using errcode='40001';end if;
 perform app_private.put_property_location(p_property_id,p_area_id,p_pin_link);
 update public.property set unit_name=unit_name where property_id=p_property_id;
 return public.my_property_location(p_property_id);
end;$$;
revoke all on function public.save_property_location(uuid,bigint,text,text) from public,anon,authenticated,service_role;
grant execute on function public.save_property_location(uuid,bigint,text,text) to authenticated;

create function public.save_located_property(p_property_id uuid,p_revision bigint,p_input jsonb,p_area_id text,p_pin_link text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('property-location:'||p_property_id,0));
 r:=public.save_my_property(p_property_id,p_revision,p_input);
 perform app_private.put_property_location(p_property_id,p_area_id,p_pin_link);
 return r||jsonb_build_object('location',public.my_property_location(p_property_id));
end;$$;
revoke all on function public.save_located_property(uuid,bigint,jsonb,text,text) from public,anon,authenticated,service_role;
grant execute on function public.save_located_property(uuid,bigint,jsonb,text,text) to authenticated;

create function public.create_located_property(p_input jsonb,p_area_id text,p_pin_link text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_revision bigint;r jsonb;
begin
 if not exists(select 1 from public.user_account where user_id=auth.uid() and role='owner') then
  raise exception 'Owner required' using errcode='42501';end if;
 -- Existing strict property validator runs in the same transaction. Bad input
 -- or location rolls this temporary insert back, including its identity.
 insert into public.property(owner_id,unit_name,building_name,address,bedrooms,size_sqft)
 values(auth.uid(),'New unit','New building','New address',1,1) returning property_id,property_revision into v_id,v_revision;
 r:=public.save_my_property(v_id,v_revision,p_input);
 perform app_private.put_property_location(v_id,p_area_id,p_pin_link);
 return r||jsonb_build_object('location',public.my_property_location(v_id));
end;$$;
revoke all on function public.create_located_property(jsonb,text,text) from public,anon,authenticated,service_role;
grant execute on function public.create_located_property(jsonb,text,text) to authenticated;

create function public.my_service_location() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r jsonb;
begin
 if not exists(select 1 from public.user_account where user_id=auth.uid() and role='provider') then
  raise exception 'Provider required' using errcode='42501';end if;
 select jsonb_build_object('area_ids',l.area_ids,'pin_link',case when l.origin_snapshot=p.service_origin_address then l.pin_link end,
  'area_names',(select jsonb_agg(a.name order by a.name) from app_private.service_area a where a.id=any(l.area_ids)))
 into r from app_private.provider_location l join public.provider_profile p using(provider_id) where provider_id=auth.uid();
 return coalesce(r,jsonb_build_object('area_ids','[]'::jsonb,'area_names','[]'::jsonb,'pin_link',null));
end;$$;
revoke all on function public.my_service_location() from public,anon,authenticated,service_role;
grant execute on function public.my_service_location() to authenticated;

create function public.my_provider_profile_with_location() returns jsonb
language sql stable security definer set search_path='' as $$
 select public.my_provider_profile()||jsonb_build_object('location',public.my_service_location());
$$;
revoke all on function public.my_provider_profile_with_location() from public,anon,authenticated,service_role;
grant execute on function public.my_provider_profile_with_location() to authenticated;

create function public.save_located_provider_profile(p_input jsonb,p_expected_revision bigint,p_expected_contact text,
 p_area_ids text[],p_pin_link text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb;pin jsonb;origin text;
begin
 if p_area_ids is null or cardinality(p_area_ids) not between 1 and 20 or
  exists(select 1 from unnest(p_area_ids)x where x is null or not exists(select 1 from app_private.service_area where id=x)) then
  raise exception 'Select supported service areas' using errcode='22023';end if;
 pin:=app_private.read_map_pin(p_pin_link);
 r:=public.save_my_provider_profile(p_input,p_expected_revision,p_expected_contact);
 if exists(select 1 from public.booking b join app_private.property_location l using(property_id)
  where b.provider_id=auth.uid() and b.current_status in('Accepted','In Progress') and b.requested_end_at>clock_timestamp()
   and not app_private.area_covered(l.area_id,p_area_ids)) then
  raise exception 'Confirmed bookings still require this service area' using errcode='23514';end if;
 select service_origin_address into origin from public.provider_profile where provider_id=auth.uid();
 insert into app_private.provider_location values(auth.uid(),p_area_ids,origin,pin->>'pin_link',
  (pin->>'latitude')::double precision,(pin->>'longitude')::double precision)
 on conflict(provider_id) do update set area_ids=excluded.area_ids,origin_snapshot=excluded.origin_snapshot,
  pin_link=excluded.pin_link,latitude=excluded.latitude,longitude=excluded.longitude;
 return r||jsonb_build_object('location',public.my_service_location());
end;$$;
revoke all on function public.save_located_provider_profile(jsonb,bigint,text,text[],text) from public,anon,authenticated,service_role;
grant execute on function public.save_located_provider_profile(jsonb,bigint,text,text[],text) to authenticated;

create function app_private.provider_distance(p_property uuid,p_provider uuid) returns numeric
language sql stable set search_path='' as $$
 select case when l.address_snapshot=p.address and o.origin_snapshot=v.service_origin_address
 and l.latitude is not null and o.latitude is not null then
 round((6371.0088*acos(least(1.0,greatest(-1.0,
  sin(radians(l.latitude))*sin(radians(o.latitude))+
  cos(radians(l.latitude))*cos(radians(o.latitude))*cos(radians(l.longitude-o.longitude))))))::numeric,1) end
 from app_private.property_location l join public.property p using(property_id)
 cross join app_private.provider_location o join public.provider_profile v using(provider_id)
 where l.property_id=p_property and o.provider_id=p_provider;
$$;
revoke all on function app_private.provider_distance(uuid,uuid) from public,anon,authenticated,service_role;

create function public.find_provider_matches(p_property_id uuid,p_service_type_id uuid,p_start_at timestamptz,p_end_at timestamptz)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare prop public.property%rowtype;loc jsonb;current_rows jsonb;alternatives jsonb;duration interval;current_ids uuid[];
begin
 -- Run the original validation even when location has not been supplied.
 select coalesce(array_agg(e.provider_id),'{}'::uuid[]) into current_ids
 from public.find_eligible_providers(p_property_id,p_service_type_id,p_start_at,p_end_at)e
 where app_private.location_gate(p_property_id,e.provider_id) is null;
 select * into prop from public.property where property_id=p_property_id and owner_id=auth.uid();
 if not found then raise exception 'Property unavailable' using errcode='42501';end if;
 loc:=public.my_property_location(p_property_id);
 if not(loc?'area_id') then return jsonb_build_object('location_required',true,'current','[]'::jsonb,'alternatives','[]'::jsonb);end if;
 duration:=p_end_at-p_start_at;
 with candidates as (
  select to_jsonb(e)||jsonb_build_object('full_name',p.full_name,
    'distance_km',app_private.provider_distance(p_property_id,p.provider_id),
    'active_job_count',(select count(*) from public.booking b where b.provider_id=p.provider_id
     and b.current_status in('Accepted','In Progress') and b.requested_start_at<p_start_at+interval '7 days'
     and b.requested_end_at>p_start_at)) as item
  from public.find_eligible_providers(p_property_id,p_service_type_id,p_start_at,p_end_at)e
  join public.provider_profile p using(provider_id)
  where app_private.location_gate(p_property_id,p.provider_id) is null
  order by p.rating_average desc nulls last,p.provider_id limit 250
 ), scored as (
  select item,
   (case when item->>'distance_km' is null then .5
    when max((item->>'distance_km')::numeric)over()=min((item->>'distance_km')::numeric)over() then .5
    else 1-((item->>'distance_km')::numeric-min((item->>'distance_km')::numeric)over())/
      nullif(max((item->>'distance_km')::numeric)over()-min((item->>'distance_km')::numeric)over(),0) end
   +case when max(coalesce((item->>'rating_average')::numeric,3))over()=min(coalesce((item->>'rating_average')::numeric,3))over() then .5
    else (coalesce((item->>'rating_average')::numeric,3)-min(coalesce((item->>'rating_average')::numeric,3))over())/
      nullif(max(coalesce((item->>'rating_average')::numeric,3))over()-min(coalesce((item->>'rating_average')::numeric,3))over(),0) end
   +case when max((item->>'active_job_count')::numeric)over()=min((item->>'active_job_count')::numeric)over() then .5
    else 1-((item->>'active_job_count')::numeric-min((item->>'active_job_count')::numeric)over())/
      nullif(max((item->>'active_job_count')::numeric)over()-min((item->>'active_job_count')::numeric)over(),0) end)/3 as score
  from candidates
 ) select coalesce(jsonb_agg(item order by score desc,item->>'provider_id'),'[]'::jsonb) into current_rows
 from (select * from scored order by score desc,item->>'provider_id' limit 20)x;

 with providers as (
  select p.* from public.provider_profile p
  where p.approval_status='approved' and app_private.location_gate(p_property_id,p.provider_id) is null
   and not(p.provider_id=any(current_ids))
   and exists(select 1 from public.provider_capability c where c.provider_id=p.provider_id and c.service_type_id=p_service_type_id)
   and ((duration=interval '8 hours' and (p.daily_rate>0 or p.hourly_rate>0)) or (duration<interval '8 hours' and p.hourly_rate>0))
  order by p.rating_average desc nulls last,p.provider_id limit 250
 ), offers as (
  select p.*,w.start_at,w.start_at+duration as end_at,
    case when duration=interval '8 hours' and p.daily_rate>0 then 'daily' else 'hourly' end as basis,
    case when duration=interval '8 hours' and p.daily_rate>0 then p.daily_rate
     else round(p.hourly_rate*(extract(epoch from duration)/3600),2) end as amount
  from providers p cross join lateral (
   select t at time zone 'Asia/Kuala_Lumpur' as start_at
   from public.provider_weekly_slot s cross join generate_series(0,6)d
   cross join lateral generate_series(
    greatest(((p_start_at at time zone 'Asia/Kuala_Lumpur')::date+d)+s.start_time,
             ((p_start_at at time zone 'Asia/Kuala_Lumpur')::date+d)+prop.cleaning_window_start),
    least(((p_start_at at time zone 'Asia/Kuala_Lumpur')::date+d)+s.end_time,
          ((p_start_at at time zone 'Asia/Kuala_Lumpur')::date+d)+prop.cleaning_window_end)-duration,
    interval '30 minutes')t
   where s.provider_id=p.provider_id and s.end_time-s.start_time>=interval '2 hours'
    and s.weekday=extract(isodow from t)::integer
    and t at time zone 'Asia/Kuala_Lumpur'>now()
    and t at time zone 'Asia/Kuala_Lumpur'<>p_start_at
    and t::date=(t+duration)::date
    and not exists(select 1 from public.provider_unavailable_date u where u.provider_id=p.provider_id and u.unavailable_on=t::date)
    and not exists(select 1 from public.booking b where b.provider_id=p.provider_id
      and b.current_status in('Accepted','In Progress') and b.requested_start_at<(t at time zone 'Asia/Kuala_Lumpur')+duration
      and (t at time zone 'Asia/Kuala_Lumpur')<b.requested_end_at)
   order by abs(extract(epoch from ((t at time zone 'Asia/Kuala_Lumpur')-p_start_at))),t limit 1
  )w
 ) select coalesce(jsonb_agg(item order by difference,item->>'provider_id'),'[]'::jsonb) into alternatives from (
  select jsonb_build_object('provider_id',p.provider_id,'full_name',p.full_name,'bio',p.bio,
   'service_area',(select name from app_private.service_area where id=loc->>'area_id'),
   'hourly_rate',p.hourly_rate,'daily_rate',p.daily_rate,'rating_average',p.rating_average,
   'completed_job_count',p.completed_job_count,'quote_basis',p.basis,'quoted_amount',p.amount,
   'distance_km',app_private.provider_distance(p_property_id,p.provider_id),
   'start_at',p.start_at,'end_at',p.end_at) as item,
   abs(extract(epoch from (p.start_at-p_start_at))) as difference
  from offers p where p.amount>0 order by difference,p.rating_average desc nulls last,p.provider_id limit 3
 )x;
 return jsonb_build_object('location_required',false,'area_name',loc->>'area_name','current',current_rows,'alternatives',alternatives);
end;$$;
revoke all on function public.find_provider_matches(uuid,uuid,timestamptz,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.find_provider_matches(uuid,uuid,timestamptz,timestamptz) to authenticated;

-- Keep the original idempotent quote/availability implementation behind a
-- mandatory coverage gate. Old clients cannot bypass geography through the RPC.
alter function public.create_pending_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,text,text) set schema app_private;
revoke all on function app_private.create_pending_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,text,text)
 from public,anon,authenticated,service_role;
create function public.create_pending_booking(p_client_request_id uuid,p_provider_id uuid,p_property_id uuid,p_service_type_id uuid,
 p_start_at timestamptz,p_end_at timestamptz,p_expected_amount numeric,p_expected_basis text,p_instructions text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare reason text;
begin
 if not exists(select 1 from public.user_account where user_id=auth.uid() and role='owner') then
  raise exception 'Owner required' using errcode='42501';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('property-location:'||p_property_id,0));
 if exists(select 1 from public.booking where owner_id=auth.uid() and client_request_id=p_client_request_id) then
  return app_private.create_pending_booking(p_client_request_id,p_provider_id,p_property_id,p_service_type_id,p_start_at,p_end_at,p_expected_amount,p_expected_basis,p_instructions);
 end if;
 if not exists(select 1 from public.property where property_id=p_property_id and owner_id=auth.uid()) then
  raise exception 'Property unavailable' using errcode='42501';end if;
 perform 1 from public.provider_profile where provider_id=p_provider_id for update;
 reason:=app_private.location_gate(p_property_id,p_provider_id);
 if reason is not null then return jsonb_build_object('created',false,'reason',reason);end if;
 return app_private.create_pending_booking(p_client_request_id,p_provider_id,p_property_id,p_service_type_id,p_start_at,p_end_at,p_expected_amount,p_expected_basis,p_instructions);
end;$$;
revoke all on function public.create_pending_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,text,text)
 from public,anon,authenticated,service_role;
grant execute on function public.create_pending_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,text,text) to authenticated;

alter function public.accept_pending_booking(uuid) set schema app_private;
revoke all on function app_private.accept_pending_booking(uuid) from public,anon,authenticated,service_role;
create function public.accept_pending_booking(p_booking_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b public.booking%rowtype;reason text;
begin
 select * into b from public.booking where booking_id=p_booking_id;
 if auth.uid() is null or b.provider_id is null or b.provider_id<>auth.uid() then
  raise exception 'Booking is not assigned to this provider' using errcode='42501';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('property-location:'||b.property_id,0));
 perform 1 from public.provider_profile where provider_id=b.provider_id for update;
 if b.current_status='Pending' and b.requested_start_at>clock_timestamp()
  and exists(select 1 from public.provider_profile where provider_id=b.provider_id and approval_status='approved') then
  reason:=app_private.location_gate(b.property_id,b.provider_id);
  if reason is not null then return jsonb_build_object('accepted',false,'reason',reason);end if;
 end if;
 return app_private.accept_pending_booking(p_booking_id);
end;$$;
revoke all on function public.accept_pending_booking(uuid) from public,anon,authenticated,service_role;
grant execute on function public.accept_pending_booking(uuid) to authenticated;
