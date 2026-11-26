-- Synthetic assignments run inside a rollback transaction. Existing assignments
-- are ended temporarily inside this transaction only; all changes roll back.
begin;
do $$
declare owner_user uuid; tenants uuid[]; property uuid; unit uuid; test_tenancy uuid;
begin
  select user_id into owner_user from public.user_account where role='owner' limit 1;
  select array_agg(tenant_id) into tenants from (select tenant_id from public.tenant limit 2) t;
  if owner_user is null or coalesce(array_length(tenants,1),0)<2 then
    raise exception 'Occupancy tests require an Owner and two test Tenants'; end if;
  insert into public.property(owner_id,unit_name,building_name,address,bedrooms,size_sqft)
    values(owner_user,'B-25-08','Occupancy test fixture','Synthetic test',4,800) returning property_id into property;
  select unit_id into unit from public.rental_unit where property_id=property;
  update public.tenancy set tenancy_status='ended' where tenant_id=any(tenants);
  insert into public.tenancy(tenant_id,unit_id,start_date,end_date,monthly_rental_amount,
    rental_type,room_number,occupant_count) values(tenants[1],unit,'2090-01-01','2090-01-31',100,'room',1,2)
    returning tenancy_id into test_tenancy;
  begin
    insert into public.tenancy(tenant_id,unit_id,start_date,end_date,monthly_rental_amount,
      rental_type,room_number,occupant_count) values(tenants[2],unit,'2090-01-15','2090-01-20',100,'room',1,1);
    raise exception 'TEST FAILED: full room accepted';
  exception when check_violation then null; end;
  begin
    insert into public.tenancy(tenant_id,unit_id,start_date,end_date,monthly_rental_amount,
      rental_type,room_number,occupant_count) values(tenants[2],unit,'2090-01-15','2090-01-20',100,'whole_unit',null,8);
    raise exception 'TEST FAILED: conflicting whole unit accepted';
  exception when check_violation then null; end;
  -- Another room remains available.
  insert into public.tenancy(tenant_id,unit_id,start_date,end_date,monthly_rental_amount,
    rental_type,room_number,occupant_count) values(tenants[2],unit,'2090-01-01','2090-01-31',100,'room',2,2);
  if (app_private.unit_occupancy(unit,'2090-01-01','2090-01-31',null)->>'total')::int<>4 then
    raise exception 'TEST FAILED: wrong occupied count'; end if;
  if (app_private.unit_occupancy(unit,'2090-02-01',null,null)->>'total')::int<>0 then
    raise exception 'TEST FAILED: ended interval blocks future dates'; end if;
  if (app_private.unit_occupancy(unit,'2090-01-01','2090-01-31',test_tenancy)->>'total')::int<>2 then
    raise exception 'TEST FAILED: editing counts own tenancy'; end if;
  update public.tenancy set tenancy_status='ended' where tenant_id=any(tenants);
  insert into public.tenancy(tenant_id,unit_id,start_date,end_date,monthly_rental_amount,
    rental_type,room_number,occupant_count) values(tenants[1],unit,'2091-01-01',null,100,'whole_unit',null,8);
  begin
    insert into public.tenancy(tenant_id,unit_id,start_date,monthly_rental_amount,
      rental_type,room_number,occupant_count) values(tenants[2],unit,'2091-01-01',100,'room',1,1);
    raise exception 'TEST FAILED: room in reserved whole unit accepted';
  exception when check_violation then null; end;
end;$$;
select 'Registered-unit occupancy checks passed' as result;
rollback;
