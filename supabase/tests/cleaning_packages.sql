-- Rollback-only synthetic regressions. Run after migrations001-053 as postgres.
-- No catalogue fixtures escape this transaction; no hosted service is contacted.
begin;
insert into auth.users(id,email) values
 ('53000000-0000-4000-8000-000000000001','owner@packages.invalid'),
 ('53000000-0000-4000-8000-000000000002','provider@packages.invalid'),
 ('53000000-0000-4000-8000-000000000003','other@packages.invalid'),
 ('53000000-0000-4000-8000-000000000004','pending@packages.invalid'),
 ('53000000-0000-4000-8000-000000000005','outside@packages.invalid'),
 ('53000000-0000-4000-8000-000000000006','foreign-owner@packages.invalid');
insert into public.user_account(user_id,email,role) select id,email,
 case when id in('53000000-0000-4000-8000-000000000001','53000000-0000-4000-8000-000000000006') then 'owner' else 'provider' end::public.account_type
 from auth.users where email like '%@packages.invalid';
-- A daily-only Provider proves packages do not require an hourly rate.
insert into public.provider_profile(provider_id,service_area,service_origin_address,daily_rate,approval_status,full_name)
 select user_id,'Synthetic coverage','PRIVATE ORIGIN',400,
 case when user_id='53000000-0000-4000-8000-000000000004' then 'pending' else 'approved' end,'Synthetic Cleaner'
 from public.user_account where email like '%@packages.invalid' and role='provider';
insert into public.service_type(service_type_id,name) values
 ('53000000-0000-4000-8000-000000000010','  sTaNdArD-CLEANING  '),
 ('53000000-0000-4000-8000-000000000011','DEEP_Cleaning'),
 ('53000000-0000-4000-8000-000000000012','Window fixture cleaning');
insert into public.provider_capability(provider_id,service_type_id)
 select p.provider_id,s.service_type_id from public.provider_profile p cross join public.service_type s
 where p.provider_id::text like '53000000-%' and s.service_type_id::text like '53000000-%';
insert into public.provider_weekly_slot(provider_id,weekday,start_time,end_time)
 select provider_id,n,'08:00','18:00' from public.provider_profile cross join generate_series(1,7)n where provider_id::text like '53000000-%';
insert into public.property(property_id,owner_id,unit_name,building_name,address) values
 ('53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000001','A-24-08','Synthetic','PRIVATE RENTAL'),
 ('53000000-0000-4000-8000-000000000021','53000000-0000-4000-8000-000000000006','B-24-08','Synthetic','OTHER PRIVATE');
insert into app_private.property_location(property_id,area_id,address_snapshot) values
 ('53000000-0000-4000-8000-000000000020','my-kl-setapak','PRIVATE RENTAL'),
 ('53000000-0000-4000-8000-000000000021','my-kl-setapak','OTHER PRIVATE');
insert into app_private.provider_location(provider_id,area_ids,origin_snapshot)
 select provider_id,case when provider_id='53000000-0000-4000-8000-000000000005' then array['my-sgr-pj'] else array['my-kl'] end,'PRIVATE ORIGIN'
 from public.provider_profile where provider_id::text like '53000000-%';
select set_config('test.pkg.start',((((now() at time zone 'Asia/Kuala_Lumpur')::date+7)+time '10:00') at time zone 'Asia/Kuala_Lumpur')::text,true);

-- Ensure privilege defaults cannot accidentally expose any new object.
do $$ declare r record;begin
 assert (select count(*) from app_private.cleaning_package)=0,'Migration must not seed prices';
 assert (select relrowsecurity from pg_class where oid='app_private.cleaning_package'::regclass);
 assert not has_any_column_privilege('authenticated','app_private.cleaning_package','SELECT,INSERT,UPDATE,REFERENCES');
 assert not has_table_privilege('authenticated','app_private.cleaning_package','DELETE,TRUNCATE,TRIGGER');
 assert not has_table_privilege('service_role','app_private.cleaning_package','SELECT,INSERT,UPDATE,DELETE');
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='app_private' and p.proname in('cleaning_service_kind','create_pending_booking_core',
  'find_eligible_providers_core','find_provider_matches_core','guard_booking_package_snapshot') loop
  assert not has_function_privilege('authenticated',r.oid,'EXECUTE');
  assert not has_function_privilege('anon',r.oid,'EXECUTE');
  assert not has_function_privilege('service_role',r.oid,'EXECUTE');
 end loop;
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in('my_cleaning_packages','save_my_cleaning_package',
  'create_pending_package_booking','find_package_provider_matches') loop
  assert has_function_privilege('authenticated',r.oid,'EXECUTE');
  assert not has_function_privilege('anon',r.oid,'EXECUTE');
  assert not has_function_privilege('service_role',r.oid,'EXECUTE');
 end loop;
 assert app_private.cleaning_service_kind('Standard Cleaning')='standard';
 assert app_private.cleaning_service_kind('Regular-cleaning')='standard';
 assert app_private.cleaning_service_kind('deep CLEAN')='deep';
 assert app_private.cleaning_service_kind('window cleaning') is null;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
do $$begin
 begin perform public.my_cleaning_packages();raise exception 'Unauthenticated read';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000001',true);
do $$begin
 begin perform public.my_cleaning_packages();raise exception 'Owner read private packages';exception when insufficient_privilege then null;end;
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,1,120,'Scope',true,0);
  raise exception 'Owner wrote provider package';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000002',true);
do $$ declare k jsonb;r jsonb;d integer;c integer;price numeric;begin
 assert public.my_cleaning_packages()='[]'::jsonb;
 -- All six duration choices and all crew bounds are accepted.
 foreach d in array array[120,180,240] loop
  for c in 1..4 loop
   k:=public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',d,c,123.45,'  Floors and bathrooms  ',true,0);
   assert (k->>'revision')::bigint=1 and (k->>'duration_minutes')::integer=d and (k->>'cleaner_count')::integer=c;
   assert k->>'provider_id'=auth.uid()::text and k->>'package_scope'='Floors and bathrooms';
   if d=120 and c=2 then perform set_config('test.pkg.id',k->>'package_id',true);end if;
  end loop;
 end loop;
 foreach d in array array[240,360,480] loop
  k:=public.save_my_cleaning_package('53000000-0000-4000-8000-000000000011',d,4,345.67,'Deep scope',true,0);
 end loop;
 assert jsonb_array_length(public.my_cleaning_packages())=15;
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,2,99,'Duplicate',true,0);
  raise exception 'Duplicate option saved';exception when unique_violation then null;end;
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000011',120,2,99,'Bad deep duration',true,0);
  raise exception 'Short deep saved';exception when invalid_parameter_value then null;end;
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',360,2,99,'Bad standard duration',true,0);
  raise exception 'Long standard saved';exception when invalid_parameter_value then null;end;
 foreach c in array array[0,5] loop
  begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,c,99,'Bad crew',true,0);
   raise exception 'Invalid crew saved';exception when invalid_parameter_value then null;end;
 end loop;
 foreach price in array array[0,-1,0.001,100000000,'NaN'::numeric,'Infinity'::numeric] loop
  begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,1,price,'Bad price',true,0);
   raise exception 'Invalid total saved';exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000012',120,1,99,'Unsupported',true,0);
  raise exception 'Unsupported service saved';exception when invalid_parameter_value then null;end;
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,1,99,'  ',true,0);
  raise exception 'Blank scope saved';exception when invalid_parameter_value then null;end;
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,1,99,repeat('x',2001),true,0);
  raise exception 'Overlong scope saved';exception when invalid_parameter_value then null;end;
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,1,99,'Scope',true,1);
  raise exception 'Create with edit revision';exception when sqlstate 'PT409' then null;end;
 -- A temporary draft can change service/duration/crew, preserving its ID.
 k:=public.save_my_cleaning_package('53000000-0000-4000-8000-000000000011',360,1,250,'Draft',false,0);
 r:=public.save_my_cleaning_package('53000000-0000-4000-8000-000000000011',480,2,251,'Edited draft',true,1,(k->>'package_id')::uuid);
 assert r->>'package_id'=k->>'package_id' and r->>'revision'='2' and r->>'duration_minutes'='480' and r->>'cleaner_count'='2';
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000011',240,4,251,'Duplicate edit',true,2,(k->>'package_id')::uuid);
  raise exception 'Edit collided silently';exception when unique_violation then null;end;
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000011',360,1,250,'Stale draft',true,1,(k->>'package_id')::uuid);
  raise exception 'Stale edit saved';exception when sqlstate 'PT409' then null;end;
 assert public.my_cleaning_packages() @> jsonb_build_array(r),'Failed update partly committed';
 begin perform 1 from app_private.cleaning_package;raise exception 'Raw read exposed';exception when insufficient_privilege then null;end;
 begin delete from app_private.cleaning_package;raise exception 'Raw delete allowed';exception when insufficient_privilege then null;end;
end $$;
-- Other Providers have isolated lists and cannot update an ID from another user.
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000003',true);
do $$declare k jsonb;begin
 assert public.my_cleaning_packages()='[]'::jsonb;
 begin perform public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,2,1,'Spoof',true,1,current_setting('test.pkg.id')::uuid);
  raise exception 'Foreign package edited';exception when insufficient_privilege then null;end;
 k:=public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,2,150,'Other crew scope',true,0);
 perform set_config('test.pkg.other',k->>'package_id',true);
end $$;
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000004',true);
select public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,2,90,'Pending provider',true,0);
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000005',true);
select public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,2,90,'Outside area',true,0);
reset role;
-- The other covered Provider is busy, so only a valid alternative may be shown.
insert into public.booking(owner_id,provider_id,property_id,service_type_id,requested_start_at,requested_end_at,current_status,
 quote_basis,quoted_rate,quoted_duration_minutes,quoted_amount)
 values('53000000-0000-4000-8000-000000000001','53000000-0000-4000-8000-000000000003',
 '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',
 current_setting('test.pkg.start')::timestamptz,current_setting('test.pkg.start')::timestamptz+interval '2 hours','Accepted','hourly',50,120,100);
set local role authenticated;
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000001',true);
do $$declare r jsonb;x jsonb;t timestamptz:=current_setting('test.pkg.start')::timestamptz;alt jsonb;begin
 r:=public.find_package_provider_matches('53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',2);
 assert r->>'location_required'='false' and jsonb_array_length(r->'current')=1;
 x:=r->'current'->0;
 assert x->>'provider_id'='53000000-0000-4000-8000-000000000002' and x->>'quote_basis'='package';
 assert x->>'package_id'=current_setting('test.pkg.id') and x->>'package_revision'='1';
 assert x->>'cleaner_count'='2' and x->>'duration_minutes'='120' and (x->>'quoted_amount')::numeric=123.45;
 assert x->>'package_scope'='Floors and bathrooms' and x->>'hourly_rate' is null;
 assert jsonb_array_length(r->'alternatives')=1;
 alt:=r->'alternatives'->0;
 assert alt->>'provider_id'='53000000-0000-4000-8000-000000000003' and alt->>'package_id'=current_setting('test.pkg.other');
 assert alt->>'quote_basis'='package' and (alt->>'quoted_amount')::numeric=150 and alt->>'cleaner_count'='2';
 assert (alt->>'end_at')::timestamptz-(alt->>'start_at')::timestamptz=interval '2 hours';
 assert (alt->>'end_at')::timestamptz<=t or (alt->>'start_at')::timestamptz>=t+interval '2 hours';
 assert not r::text like '%PRIVATE%','Private location leaked';
 -- Existing legacy search does not promote a daily-only provider for two hours.
 assert not exists(select 1 from public.find_eligible_providers('53000000-0000-4000-8000-000000000020',
  '53000000-0000-4000-8000-000000000010',t,t+interval '2 hours') where provider_id='53000000-0000-4000-8000-000000000002');
 begin perform public.find_package_provider_matches('53000000-0000-4000-8000-000000000021','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',2);
  raise exception 'Foreign property searched';exception when insufficient_privilege then null;end;
 begin perform public.find_package_provider_matches('53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',5);
  raise exception 'Invalid crew searched';exception when invalid_parameter_value then null;end;
 -- Neither a guessed price nor a guessed revision can create a booking.
 x:=public.create_pending_package_booking(gen_random_uuid(),'53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',current_setting('test.pkg.id')::uuid,1,1);
 assert x->>'created'='false' and x->>'reason'='price_changed';
 x:=public.create_pending_package_booking(gen_random_uuid(),'53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',current_setting('test.pkg.id')::uuid,123.45,2);
 assert x->>'created'='false' and x->>'reason'='package_changed';
 x:=public.create_pending_package_booking(gen_random_uuid(),'53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',current_setting('test.pkg.other')::uuid,150,1);
 assert x->>'created'='false' and x->>'reason'='package_unavailable';
 x:=public.create_pending_package_booking(gen_random_uuid(),'53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '3 hours',current_setting('test.pkg.id')::uuid,123.45,1);
 assert x->>'created'='false' and x->>'reason'='package_unavailable';
 x:=public.create_pending_package_booking(gen_random_uuid(),'53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000011',t,t+interval '2 hours',current_setting('test.pkg.id')::uuid,123.45,1);
 assert x->>'created'='false' and x->>'reason'='package_unavailable';
 x:=public.create_pending_package_booking('53000000-0000-4000-8000-000000000030','53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',current_setting('test.pkg.id')::uuid,123.45,1,'Booking scope');
 assert x->>'created'='true' and x->>'reused'='false' and x->>'quote_basis'='package' and (x->>'quoted_amount')::numeric=123.45;
 perform set_config('test.pkg.booking',x->>'booking_id',true);
 assert (select quoted_rate=123.45 and quoted_amount=123.45 and quoted_duration_minutes=120 and cleaner_count=2
  and package_revision=1 and package_scope='Floors and bathrooms' from public.booking where booking_id=(x->>'booking_id')::uuid);
 -- Idempotency never crosses between the new package API and legacy quote API.
 begin perform public.create_pending_booking('53000000-0000-4000-8000-000000000030','53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',123.45,'package','Booking scope');
  raise exception 'Legacy endpoint replayed package';exception when check_violation then null;end;
 -- Existing duration-preserving revision works; duration change cannot reprice.
 x:=public.revise_pending_booking(current_setting('test.pkg.booking')::uuid,t+interval '1 day',t+interval '1 day 2 hours','Booking scope');
 assert x->>'revised'='true';
 begin perform public.revise_pending_booking(current_setting('test.pkg.booking')::uuid,t+interval '1 day',t+interval '1 day 3 hours','Booking scope');
  raise exception 'Package duration changed';exception when check_violation then null;end;
 -- Put it back for stable retry and later acceptance checks.
 perform public.revise_pending_booking(current_setting('test.pkg.booking')::uuid,t,t+interval '2 hours','Booking scope');
 begin update public.booking set package_scope='Forged' where booking_id=current_setting('test.pkg.booking')::uuid;
  raise exception 'Snapshot forged';exception when insufficient_privilege then null;end;
end $$;
-- Provider edits the original ID, including duration/crew and same-price scope.
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000002',true);
select public.save_my_cleaning_package('53000000-0000-4000-8000-000000000011',360,3,123.45,'New deep scope',false,1,current_setting('test.pkg.id')::uuid);
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000001',true);
do $$declare x jsonb;t timestamptz:=current_setting('test.pkg.start')::timestamptz;begin
 x:=public.create_pending_package_booking('53000000-0000-4000-8000-000000000030','53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',current_setting('test.pkg.id')::uuid,123.45,1,'Booking scope');
 assert x->>'created'='true' and x->>'reused'='true' and x->>'package_revision'='1' and x->>'duration_minutes'='120' and x->>'cleaner_count'='2';
 assert x->>'package_scope'='Floors and bathrooms';
 begin perform public.create_pending_package_booking('53000000-0000-4000-8000-000000000030','53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',current_setting('test.pkg.id')::uuid,123.45,2,'Booking scope');
  raise exception 'Token reused with changed revision';exception when check_violation then null;end;
 x:=public.create_pending_package_booking(gen_random_uuid(),'53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',current_setting('test.pkg.id')::uuid,123.45,1);
 assert x->>'created'='false' and x->>'reason'='package_unavailable';
end $$;
-- Recheck each authoritative eligibility input at submission, after search.
reset role;
select set_config('test.pkg.guard',(select package_id::text from app_private.cleaning_package where provider_id='53000000-0000-4000-8000-000000000002'
 and service_type_id='53000000-0000-4000-8000-000000000010' and duration_minutes=120 and cleaner_count=1),true);
select set_config('test.pkg.guard_revision','1',true);
create function pg_temp.assert_package_failure(p_reason text,
 p_provider uuid default '53000000-0000-4000-8000-000000000002',p_start timestamptz default null,p_package uuid default null)
returns void language plpgsql as $$
declare x jsonb;t timestamptz:=coalesce(p_start,current_setting('test.pkg.start')::timestamptz);
begin
 x:=public.create_pending_package_booking(gen_random_uuid(),p_provider,'53000000-0000-4000-8000-000000000020',
  '53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',coalesce(p_package,current_setting('test.pkg.guard')::uuid),
  123.45,current_setting('test.pkg.guard_revision')::bigint);
 assert x->>'created'='false' and x->>'reason'=p_reason,format('Expected %s; received %s',p_reason,x);
end $$;
grant execute on function pg_temp.assert_package_failure(text,uuid,timestamptz,uuid) to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_package_failure('provider_not_approved','53000000-0000-4000-8000-000000000004');
select pg_temp.assert_package_failure('provider_area','53000000-0000-4000-8000-000000000005');
select pg_temp.assert_package_failure('invalid_interval',p_start=>now()-interval '1 day');
select pg_temp.assert_package_failure('rental_window',p_start=>current_setting('test.pkg.start')::timestamptz-interval '4 hours');
-- Same-price scope changes still require a fresh package revision.
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000002',true);
select public.save_my_cleaning_package('53000000-0000-4000-8000-000000000010',120,1,123.45,'Changed scope same price',true,1,current_setting('test.pkg.guard')::uuid);
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_package_failure('package_changed');
select set_config('test.pkg.guard_revision','2',true);
reset role;
update app_private.cleaning_package set enabled=false where package_id=current_setting('test.pkg.guard')::uuid;
set local role authenticated;
select pg_temp.assert_package_failure('package_unavailable');
do $$declare r jsonb;t timestamptz:=current_setting('test.pkg.start')::timestamptz;begin
 r:=public.find_package_provider_matches('53000000-0000-4000-8000-000000000020','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',1);
 assert jsonb_array_length(r->'current')=0 and jsonb_array_length(r->'alternatives')=0,'Disabled package matched';
end $$;
reset role;
update app_private.cleaning_package set enabled=true where package_id=current_setting('test.pkg.guard')::uuid;
insert into public.provider_unavailable_date(provider_id,unavailable_on)
 values('53000000-0000-4000-8000-000000000002',(current_setting('test.pkg.start')::timestamptz at time zone 'Asia/Kuala_Lumpur')::date);
set local role authenticated;
select pg_temp.assert_package_failure('availability');
reset role;
delete from public.provider_unavailable_date where provider_id='53000000-0000-4000-8000-000000000002';
delete from public.provider_capability where provider_id='53000000-0000-4000-8000-000000000002' and service_type_id='53000000-0000-4000-8000-000000000010';
set local role authenticated;
select pg_temp.assert_package_failure('service_type');
reset role;
insert into public.provider_capability values('53000000-0000-4000-8000-000000000002','53000000-0000-4000-8000-000000000010');
update public.provider_weekly_slot set start_time='12:00' where provider_id='53000000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.assert_package_failure('availability');
reset role;
update public.provider_weekly_slot set start_time='08:00' where provider_id='53000000-0000-4000-8000-000000000002';
update public.property set address='STALE ADDRESS' where property_id='53000000-0000-4000-8000-000000000020';
set local role authenticated;
select pg_temp.assert_package_failure('rental_location_missing');
reset role;
update public.property set address='PRIVATE RENTAL' where property_id='53000000-0000-4000-8000-000000000020';
set local role authenticated;
-- Approval and geography do not replace ownership verification.
do $$declare t timestamptz:=current_setting('test.pkg.start')::timestamptz;begin
 begin perform public.create_pending_package_booking(gen_random_uuid(),'53000000-0000-4000-8000-000000000002',
  '53000000-0000-4000-8000-000000000021','53000000-0000-4000-8000-000000000010',t,t+interval '2 hours',current_setting('test.pkg.guard')::uuid,123.45,2);
  raise exception 'Foreign property booked';exception when insufficient_privilege then null;end;
end $$;
-- Acceptance uses the immutable booking, not current catalogue or hourly rates.
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000002',true);
do $$declare x jsonb;begin
 x:=public.accept_pending_booking(current_setting('test.pkg.booking')::uuid);
 assert x->>'accepted'='true';
 assert (select package_scope='Floors and bathrooms' and quoted_amount=123.45 and duration_minutes=120 and cleaner_count=2
  from public.booking where booking_id=current_setting('test.pkg.booking')::uuid);
end $$;
select set_config('request.jwt.claim.sub','53000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_package_failure('slot_conflict');
reset role;
-- Even trusted operations cannot silently alter a package booking's snapshot.
do $$begin
 begin update public.booking set quoted_amount=999,quoted_rate=999 where booking_id=current_setting('test.pkg.booking')::uuid;
  raise exception 'Trusted package reprice accepted';exception when insufficient_privilege then null;end;
 assert (select count(*) from public.booking_status_history where booking_id=current_setting('test.pkg.booking')::uuid)=2;
 assert not exists(select 1 from public.booking where package_id is null and quote_basis='package');
end $$;
rollback;
