-- Apply only to the shared integration project; independent of cleaning migration 053.
begin;
do $$ begin
if not exists(select 1 from public.app_deployment_environment where singleton and environment='staging' and project_ref='myetpfavvwuevdcybdes') then raise exception 'Wrong project'; end if;
if exists(select 1 from supabase_migrations.schema_migrations where version='20261126000054') then raise exception 'Occupancy migration already installed'; end if;
end;$$;
-- Registered Owner properties are the source of assignable physical units.
-- occupant_count is a headcount; occupancy_share remains a billing fraction.
alter table public.tenancy
  add column rental_type varchar(12) not null default 'whole_unit',
  add column room_number int,
  add column occupant_count int not null default 1,
  add constraint tenancy_rental_space check (
    (rental_type='whole_unit' and room_number is null and occupant_count between 1 and 8)
    or (rental_type='room' and room_number is not null and room_number between 1 and 4 and occupant_count between 1 and 2));
alter table public.tenant_registration
  add column rental_type varchar(12) not null default 'whole_unit',
  add column room_number int,
  add column occupant_count int not null default 1,
  add constraint registration_rental_space check (
    (rental_type='whole_unit' and room_number is null and occupant_count between 1 and 8)
    or (rental_type='room' and room_number is not null and room_number between 1 and 4 and occupant_count between 1 and 2));

create function app_private.unit_occupancy(p_unit uuid, p_start date, p_end date, p_exclude uuid)
returns jsonb language sql volatile set search_path='' as $$
  with bookings as (
    select * from public.tenancy t where t.unit_id=p_unit
      and t.tenancy_status in ('pending','active')
      and (p_exclude is null or t.tenancy_id<>p_exclude)
      and daterange(t.start_date,t.end_date,'[]') && daterange(p_start,p_end,'[]')
  ), points as (
    select p_start as day union select start_date from bookings where start_date>=p_start
  ), loads as (
    select d.day, coalesce(sum(t.occupant_count),0)::int as total,
      count(*) filter(where t.rental_type='whole_unit')::int as whole,
      coalesce(sum(t.occupant_count) filter(where t.room_number=1),0)::int as r1,
      coalesce(sum(t.occupant_count) filter(where t.room_number=2),0)::int as r2,
      coalesce(sum(t.occupant_count) filter(where t.room_number=3),0)::int as r3,
      coalesce(sum(t.occupant_count) filter(where t.room_number=4),0)::int as r4
    from points d left join bookings t on daterange(t.start_date,t.end_date,'[]') @> d.day
    group by d.day
  ) select jsonb_build_object('total',max(total),'whole',max(whole),
      'rooms',jsonb_build_array(max(r1),max(r2),max(r3),max(r4))) from loads;
$$;
revoke all on function app_private.unit_occupancy(uuid,date,date,uuid) from public,anon,authenticated;

create function public.list_tenancy_unit_options(p_registration_id uuid,p_start date,p_end date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare excluded uuid;
begin
  if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501'; end if;
  if p_start is null or (p_end is not null and p_end<p_start) then
    raise exception 'Invalid tenancy dates.' using errcode='22023'; end if;
  select t.tenancy_id into excluded from public.tenancy t
    join public.tenant_registration r on r.auth_user_id=t.tenant_id
    where r.registration_id=p_registration_id and t.tenancy_status in ('pending','active')
    order by t.start_date desc limit 1;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'unit_id',u.unit_id,'unit_number',u.unit_number,'building_name',p.building_name,
    'bedrooms',least(p.bedrooms,4),'occupancy',app_private.unit_occupancy(u.unit_id,p_start,p_end,excluded))
    order by p.building_name,u.unit_number)
    from public.rental_unit u join public.property p on p.property_id=u.property_id
    where u.unit_status in ('available','occupied')), '[]'::jsonb);
end;$$;
revoke all on function public.list_tenancy_unit_options(uuid,date,date) from public,anon;
grant execute on function public.list_tenancy_unit_options(uuid,date,date) to authenticated;

create function app_private.enforce_tenancy_capacity() returns trigger
language plpgsql security definer set search_path='' as $$
declare bedrooms int; usage jsonb;
begin
  -- Serialize assignments for both units in a consistent order during moves.
  perform 1 from public.rental_unit u
    where u.unit_id=new.unit_id or (tg_op='UPDATE' and u.unit_id=old.unit_id)
    order by u.unit_id for update;
  if new.tenancy_status not in ('pending','active') then return new; end if;
  select p.bedrooms into bedrooms from public.rental_unit u
    join public.property p on p.property_id=u.property_id
    where u.unit_id=new.unit_id and u.unit_status in ('available','occupied');
  if bedrooms is null then raise exception 'Select an Owner-registered rental unit.' using errcode='22023'; end if;
  if new.rental_type='room' and (new.room_number is null or new.room_number>least(bedrooms,4)) then
    raise exception 'This room does not exist in the registered property.' using errcode='22023'; end if;
  usage:=app_private.unit_occupancy(new.unit_id,new.start_date,new.end_date,new.tenancy_id);
  if (usage->>'whole')::int>0
     or (new.rental_type='whole_unit' and (usage->>'total')::int>0) then
    raise exception 'The unit is reserved for the selected tenancy dates.' using errcode='23514'; end if;
  if (usage->>'total')::int+new.occupant_count>8
     or (new.rental_type='room' and (usage->'rooms'->>(new.room_number-1))::int+new.occupant_count>2) then
    raise exception 'The room or unit has insufficient remaining capacity for these dates.' using errcode='23514'; end if;
  return new;
end;$$;
create trigger enforce_tenancy_capacity before insert or update of unit_id,start_date,end_date,
  tenancy_status,rental_type,room_number,occupant_count on public.tenancy
  for each row execute function app_private.enforce_tenancy_capacity();

-- A new RPC keeps old clients from bypassing the new rental-space choices.
create function public.assign_registered_tenant(p_registration_id uuid,p_unit_id uuid,
 p_start_date date,p_end_date date,p_monthly_rental_amount numeric,
 p_rental_type text,p_room_number int,p_occupant_count int)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target uuid; existing uuid; previous uuid; share numeric;
begin
  if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501'; end if;
  if p_start_date is null or p_monthly_rental_amount is null or p_monthly_rental_amount<0
    or (p_end_date is not null and p_end_date<p_start_date)
    or p_rental_type is null or p_occupant_count is null
    or not ((p_rental_type='whole_unit' and p_room_number is null and p_occupant_count between 1 and 8)
      or (p_rental_type='room' and p_room_number is not null and p_room_number between 1 and 4 and p_occupant_count between 1 and 2)) then
    raise exception 'Invalid tenancy details.' using errcode='22023'; end if;
  select auth_user_id,occupancy_share into target,share from public.tenant_registration
    where registration_id=p_registration_id and auth_user_id is not null
      and registration_status in ('accepted','assigned') for update;
  if target is null then raise exception 'The tenant must complete account setup before assignment.' using errcode='22023'; end if;
  -- Lock the tenant as well as the registration, then the old/new units.
  perform 1 from public.tenant where tenant_id=target for update;
  select tenancy_id,unit_id into existing,previous from public.tenancy
    where tenant_id=target and tenancy_status in ('pending','active') order by start_date desc limit 1;
  perform 1 from public.rental_unit where unit_id in (p_unit_id,previous) order by unit_id for update;
  if existing is null then
    insert into public.tenancy(tenant_id,unit_id,start_date,end_date,monthly_rental_amount,occupancy_share,
      tenancy_status,rental_type,room_number,occupant_count)
    values(target,p_unit_id,p_start_date,p_end_date,p_monthly_rental_amount,share,'active',p_rental_type,p_room_number,p_occupant_count)
    returning tenancy_id into existing;
  else
    update public.tenancy set unit_id=p_unit_id,start_date=p_start_date,end_date=p_end_date,
      monthly_rental_amount=p_monthly_rental_amount,rental_type=p_rental_type,room_number=p_room_number,
      occupant_count=p_occupant_count,tenancy_status='active' where tenancy_id=existing;
  end if;
  update public.rental_unit u set unit_status=case when exists(select 1 from public.tenancy t
    where t.unit_id=u.unit_id and t.tenancy_status in ('pending','active')
      and daterange(t.start_date,t.end_date,'[]') @> current_date) then 'occupied' else 'available' end
    where u.unit_id in (p_unit_id,previous) and u.unit_status in ('available','occupied');
  update public.tenant_registration set unit_id=p_unit_id,start_date=p_start_date,end_date=p_end_date,
    monthly_rental_amount=p_monthly_rental_amount,rental_type=p_rental_type,room_number=p_room_number,
    occupant_count=p_occupant_count,registration_status='assigned',updated_at=now()
    where registration_id=p_registration_id;
  update public.user_account set account_status='active',updated_at=now()
    where user_id=target and invitation_status='accepted';
  insert into public.conversation(tenancy_id,admin_id,conversation_status) values(existing,actor,'open')
    on conflict(tenancy_id,admin_id) do update set conversation_status='open';
  insert into public.audit_log(actor_user_id,action_type,entity_type,entity_id,outcome,metadata)
    values(actor,'TENANCY_OCCUPANCY_ASSIGNED','tenancy',existing,'success',
      jsonb_build_object('rental_type',p_rental_type,'room_number',p_room_number,'occupant_count',p_occupant_count));
  return true;
end;$$;
revoke all on function public.assign_registered_tenant(uuid,uuid,date,date,numeric,text,int,int) from public,anon;
grant execute on function public.assign_registered_tenant(uuid,uuid,date,date,numeric,text,int,int) to authenticated;
revoke execute on function public.assign_verified_tenant(uuid,uuid,date,date,numeric,numeric) from public,anon,authenticated;
notify pgrst,'reload schema';

insert into supabase_migrations.schema_migrations(version,name) values('20261126000054','registered_unit_occupancy');
commit;
