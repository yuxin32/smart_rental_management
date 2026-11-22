-- Owner profile and property management: explicit actor scope + revision checks.
alter table public.user_account add column account_revision bigint not null default 1;
alter table public.property add column property_revision bigint not null default 1;

create function app_private.bump_workspace_revision() returns trigger
language plpgsql set search_path='' as $$
begin
 if tg_table_name='user_account' then new.account_revision:=old.account_revision+1;
 else new.property_revision:=old.property_revision+1;end if;
 return new;
end;$$;
revoke all on function app_private.bump_workspace_revision() from public,anon,authenticated,service_role;
create trigger bump_account_revision before update on public.user_account
 for each row execute function app_private.bump_workspace_revision();
create trigger bump_property_revision before update on public.property
 for each row execute function app_private.bump_workspace_revision();

create function public.my_owner_profile() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_result jsonb;
begin
 select jsonb_build_object('actor_id',a.user_id,'full_name',a.full_name,
  'email',u.email,'contact_number',a.contact_number,'revision',a.account_revision,
  'property_count',(select count(*) from public.property where owner_id=v_actor))
 into v_result from public.user_account a join auth.users u on u.id=a.user_id
 where a.user_id=v_actor and a.role='owner';
 if v_result is null then raise exception 'Owner authentication required' using errcode='42501';end if;
 return v_result;
end;$$;
revoke all on function public.my_owner_profile() from public,anon,authenticated,service_role;
grant execute on function public.my_owner_profile() to authenticated;

create function public.save_my_owner_profile(p_input jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_revision bigint;v_name text;v_phone text;
begin
 if jsonb_typeof(p_input) is distinct from 'object' or p_revision is null or p_revision<1 or
  not(p_input ?& array['full_name','contact_number']) or
  exists(select 1 from jsonb_object_keys(p_input) k where k not in ('full_name','contact_number')) or
  jsonb_typeof(p_input->'full_name') is distinct from 'string' or
  jsonb_typeof(p_input->'contact_number') not in ('string','null') then
  raise exception 'Invalid owner profile fields' using errcode='22023';end if;
 v_name:=btrim(p_input->>'full_name');v_phone:=nullif(btrim(p_input->>'contact_number'),'');
 if length(v_name) not between 2 and 60 or
  (v_phone is not null and (length(v_phone)>25 or v_phone !~ '^\+?[0-9 ()-]{7,25}$')) then
  raise exception 'Invalid name or contact number' using errcode='22023';end if;
 select account_revision into v_revision from public.user_account
 where user_id=v_actor and role='owner' for update;
 if not found then raise exception 'Owner authentication required' using errcode='42501';end if;
 if v_revision<>p_revision then raise exception 'Profile changed. Reload before saving' using errcode='40001';end if;
 update public.user_account set full_name=v_name,contact_number=v_phone where user_id=v_actor;
 return public.my_owner_profile();
end;$$;
revoke all on function public.save_my_owner_profile(jsonb,bigint) from public,anon,authenticated,service_role;
grant execute on function public.save_my_owner_profile(jsonb,bigint) to authenticated;

create function public.page_my_properties(p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_result jsonb;
begin
 if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor and role='owner') then
  raise exception 'Owner authentication required' using errcode='42501';end if;
 if (p_before_at is null)<>(p_before_id is null) then raise exception 'Invalid property cursor' using errcode='22023';end if;
 with candidates as materialized (
  select p.*, (select count(*) from public.booking b where b.property_id=p.property_id and b.owner_id=v_actor) as total,
   (select count(*) from public.booking b where b.property_id=p.property_id and b.owner_id=v_actor and b.current_status in ('Pending','Accepted','In Progress')) as open,
   (select count(*) from public.booking b where b.property_id=p.property_id and b.owner_id=v_actor and b.current_status='Completed') as done
  from public.property p where owner_id=v_actor and
   (p_before_at is null or (p.created_at,p.property_id)<(p_before_at,p_before_id))
  order by created_at desc,property_id desc limit 21
 ), page as materialized (select * from candidates order by created_at desc,property_id desc limit 20)
 select jsonb_build_object('actor_id',v_actor,
  'total_count',(select count(*) from public.property where owner_id=v_actor),
  'items',coalesce((select jsonb_agg(to_jsonb(page)-'owner_id' order by created_at desc,property_id desc) from page),'[]'::jsonb),
  'next_cursor',case when (select count(*) from candidates)>20 then
   (select jsonb_build_object('timestamp',created_at,'id',property_id) from page order by created_at,property_id limit 1) else null end)
 into v_result;
 return v_result;
end;$$;
revoke all on function public.page_my_properties(timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.page_my_properties(timestamptz,uuid) to authenticated;

create function public.my_property(p_property_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_result jsonb;
begin
 select to_jsonb(p)-'owner_id'||jsonb_build_object('actor_id',v_actor,
  'total',(select count(*) from public.booking where property_id=p.property_id and owner_id=v_actor))
 into v_result from public.property p join public.user_account a on a.user_id=p.owner_id
 where p.property_id=p_property_id and p.owner_id=v_actor and a.role='owner';
 if v_result is null then raise exception 'Property unavailable' using errcode='42501';end if;
 return v_result;
end;$$;
revoke all on function public.my_property(uuid) from public,anon,authenticated,service_role;
grant execute on function public.my_property(uuid) to authenticated;

create function public.save_my_property(p_property_id uuid,p_revision bigint,p_input jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_revision bigint;
begin
 if p_revision is null or p_revision<1 or jsonb_typeof(p_input) is distinct from 'object' or
  not(p_input ?& array['unit_name','building_name','address','bedrooms','size_sqft','cleaning_window_start','cleaning_window_end']) or
  exists(select 1 from jsonb_object_keys(p_input) k where k not in
    ('unit_name','building_name','address','bedrooms','size_sqft','cleaning_window_start','cleaning_window_end')) then
   raise exception 'Invalid property fields' using errcode='22023';end if;
 if jsonb_typeof(p_input->'unit_name') is distinct from 'string' or
  jsonb_typeof(p_input->'building_name') is distinct from 'string' or
  jsonb_typeof(p_input->'address') is distinct from 'string' or
  jsonb_typeof(p_input->'bedrooms') is distinct from 'number' or
  jsonb_typeof(p_input->'size_sqft') is distinct from 'number' or
  jsonb_typeof(p_input->'cleaning_window_start') is distinct from 'string' or
  jsonb_typeof(p_input->'cleaning_window_end') is distinct from 'string' or
  length(btrim(p_input->>'unit_name')) not between 1 and 100 or
  length(btrim(p_input->>'building_name')) not between 1 and 150 or
  length(btrim(p_input->>'address')) not between 1 and 500 or
  (p_input->>'bedrooms') !~ '^[0-9]+$' or (p_input->>'size_sqft') !~ '^[0-9]+$' or
  (p_input->>'bedrooms')::numeric not between 1 and 100 or
  (p_input->>'size_sqft')::numeric not between 1 and 1000000 or
  (p_input->>'cleaning_window_start') !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:00)?$' or
  (p_input->>'cleaning_window_end') !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:00)?$' then
   raise exception 'Invalid property values' using errcode='22023';end if;
 if (p_input->>'cleaning_window_start')::time>=(p_input->>'cleaning_window_end')::time then
  raise exception 'Invalid cleaning window' using errcode='22023';end if;
 select property_revision into v_revision from public.property where property_id=p_property_id and owner_id=v_actor
  and exists(select 1 from public.user_account where user_id=v_actor and role='owner') for update;
 if not found then raise exception 'Property unavailable' using errcode='42501';end if;
 if v_revision<>p_revision then raise exception 'Property changed. Reload before saving' using errcode='40001';end if;
 update public.property set unit_name=btrim(p_input->>'unit_name'),building_name=btrim(p_input->>'building_name'),
  address=btrim(p_input->>'address'),bedrooms=(p_input->>'bedrooms')::integer,size_sqft=(p_input->>'size_sqft')::integer,
  cleaning_window_start=(p_input->>'cleaning_window_start')::time,cleaning_window_end=(p_input->>'cleaning_window_end')::time
  where property_id=p_property_id and owner_id=v_actor;
 -- Existing property-window lock/confirmed-booking guard still applies.
 return public.my_property(p_property_id);
end;$$;
revoke all on function public.save_my_property(uuid,bigint,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.save_my_property(uuid,bigint,jsonb) to authenticated;

create index property_owner_cursor_idx on public.property(owner_id,created_at desc,property_id desc);
create index booking_owner_property_cursor_idx on public.booking(owner_id,property_id,created_at desc,booking_id desc);
create function public.page_my_property_bookings(p_property_id uuid,p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_rows jsonb;
begin
 if not exists(select 1 from public.property where property_id=p_property_id and owner_id=v_actor) then
  raise exception 'Property unavailable' using errcode='42501';end if;
 if (p_before_at is null)<>(p_before_id is null) then raise exception 'Invalid booking cursor' using errcode='22023';end if;
 select coalesce(jsonb_agg(card order by created_at desc,booking_id desc),'[]'::jsonb) into v_rows from (
  select b.created_at,b.booking_id,to_jsonb(b)||jsonb_build_object('unit_name',p.unit_name,
   'building_name',p.building_name,'service_name',s.name) as card
  from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
  where b.property_id=p_property_id and b.owner_id=v_actor and
   (p_before_at is null or (b.created_at,b.booking_id)<(p_before_at,p_before_id))
  order by b.created_at desc,b.booking_id desc limit 21) bounded;
 return public.pack_cursor_page(v_rows,20,'created_at','booking_id')||jsonb_build_object('actor_id',v_actor);
end;$$;
revoke all on function public.page_my_property_bookings(uuid,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.page_my_property_bookings(uuid,timestamptz,uuid) to authenticated;
