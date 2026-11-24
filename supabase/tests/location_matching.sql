-- Synthetic rollback-only geography, privacy, quote and alternative tests.
begin;
insert into auth.users(id,email) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','owner@location.invalid'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','near@location.invalid'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','later@location.invalid'),
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','outside@location.invalid');
insert into public.user_account(user_id,email,role) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','owner@location.invalid','owner'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','near@location.invalid','provider'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','later@location.invalid','provider'),
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','outside@location.invalid','provider');
insert into public.provider_profile(provider_id,service_area,service_origin_address,hourly_rate,approval_status,full_name)
select user_id,'Test coverage','PRIVATE START',40,'approved','Synthetic Provider' from public.user_account where role='provider';
insert into public.service_type(service_type_id,name) values('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','Location cleaning');
insert into public.provider_capability(provider_id,service_type_id)
select provider_id,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' from public.provider_profile;
insert into public.provider_weekly_slot(provider_id,weekday,start_time,end_time)
select provider_id,n,'08:00','18:00' from public.provider_profile cross join generate_series(1,7)n;
insert into public.property(property_id,owner_id,unit_name,building_name,address)
values('ffffffff-ffff-4fff-8fff-ffffffffffff','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','A-24-08','SYNTHETIC','SYNTHETIC ADDRESS');
insert into app_private.property_location values('ffffffff-ffff-4fff-8fff-ffffffffffff','my-kl-setapak','SYNTHETIC ADDRESS',
 'https://maps.google.com/?q=0,0',0,0);
insert into app_private.provider_location(provider_id,area_ids,origin_snapshot,pin_link,latitude,longitude)
select provider_id,case when provider_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd' then array['my-sgr-pj'] else array['my-kl'] end,
 'PRIVATE START',case when provider_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' then 'https://maps.google.com/?q=0,0.01' end,
 case when provider_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' then 0 end,
 case when provider_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' then .01 end from public.provider_profile;
select set_config('test.geo.start',((((now() at time zone 'Asia/Kuala_Lumpur')::date+7)+time '10:00') at time zone 'Asia/Kuala_Lumpur')::text,true);
-- One covered Provider is busy at the original time; an outside-area Provider
-- is free but must never be advertised as a current or alternative match.
insert into public.booking(owner_id,provider_id,property_id,service_type_id,requested_start_at,requested_end_at,current_status,
 quote_basis,quoted_rate,quoted_duration_minutes,quoted_amount)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','cccccccc-cccc-4ccc-8ccc-cccccccccccc','ffffffff-ffff-4fff-8fff-ffffffffffff',
 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',current_setting('test.geo.start')::timestamptz,
 current_setting('test.geo.start')::timestamptz+interval '2 hours','Accepted','hourly',40,120,80);
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
do $$ declare r jsonb;alt jsonb;x jsonb;t timestamptz:=current_setting('test.geo.start')::timestamptz;begin
 r:=public.find_provider_matches('ffffffff-ffff-4fff-8fff-ffffffffffff','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',t,t+interval '2 hours');
 assert jsonb_array_length(r->'current')=1, 'Current match must pass location and conflict checks';
 assert r->'current'->0->>'provider_id'='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 assert (r->'current'->0->>'distance_km')::numeric=1.1, 'Distance must come from the selected coordinates';
 assert jsonb_array_length(r->'alternatives')=1;
 alt:=r->'alternatives'->0;
 assert alt->>'provider_id'='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
 assert alt->>'distance_km' is null, 'Missing pins must never invent a distance';
 assert (alt->>'end_at')::timestamptz-(alt->>'start_at')::timestamptz=interval '2 hours';
 assert (alt->>'end_at')::timestamptz<=t or (alt->>'start_at')::timestamptz>=t+interval '2 hours';
 assert (alt->>'quoted_amount')::numeric=80;
 assert r::text not like '%PRIVATE START%' and r::text not like '%pin_link%' and r::text not like '%latitude%';
 x:=public.create_pending_booking('11111111-1111-4111-8111-111111111111',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd','ffffffff-ffff-4fff-8fff-ffffffffffff','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',t,t+interval '2 hours',80,'hourly','');
 assert x->>'created'='false' and x->>'reason'='provider_area', 'Old booking RPC cannot bypass service coverage';
 x:=public.create_pending_booking('11111111-1111-4111-8111-111111111112',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','ffffffff-ffff-4fff-8fff-ffffffffffff','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',t,t+interval '2 hours',80,'hourly','');
 assert x->>'created'='true';perform set_config('test.geo.booking',x->>'booking_id',true);
 begin perform public.my_service_location();raise exception 'Owner read a private Provider pin';exception when insufficient_privilege then null;end;
 begin perform public.find_provider_matches(gen_random_uuid(),'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',t,t+interval '2 hours');raise exception 'Unknown property accepted';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
do $$ declare r jsonb;profile jsonb;draft jsonb;begin
 r:=public.accept_pending_booking(current_setting('test.geo.booking')::uuid);assert r->>'accepted'='true';
 profile:=public.my_provider_profile();
 draft:=jsonb_build_object('full_name','Synthetic Provider','bio','','service_area','Test coverage',
  'service_origin_address','PRIVATE START','hourly_rate',40,'daily_rate',null,'contact_number',null,
  'avatar_color_index',0,'show_phone_to_owners',false,'service_type_ids',jsonb_build_array('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'));
 begin perform public.save_located_provider_profile(draft,(profile->>'revision')::bigint,null,array['my-sgr-pj'],null);
  raise exception 'Confirmed service area removed';exception when check_violation then null;end;
 assert public.my_provider_profile()->>'revision'=profile->>'revision';
 assert public.my_service_location()->'area_ids'=jsonb_build_array('my-kl');
end $$;
reset role;
-- Stale address coordinates are ignored instead of being reused as real data.
update public.property set address='CHANGED ADDRESS' where property_id='ffffffff-ffff-4fff-8fff-ffffffffffff';
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
do $$ declare r jsonb;t timestamptz:=current_setting('test.geo.start')::timestamptz;begin
 r:=public.find_provider_matches('ffffffff-ffff-4fff-8fff-ffffffffffff','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',t,t+interval '2 hours');
 assert r->>'location_required'='true' and jsonb_array_length(r->'current')=0 and jsonb_array_length(r->'alternatives')=0;
end $$;
reset role;
do $$ begin
 assert not has_any_column_privilege('authenticated','app_private.provider_location','SELECT,INSERT,UPDATE,REFERENCES');
 assert app_private.read_map_pin('https://maps.google.com/?q=0,0.01')->>'longitude'='0.01';
 begin perform app_private.read_map_pin('https://www.google.com/maps/@3.1,101.1,15z');raise exception 'Viewport was treated as a pin';exception when invalid_parameter_value then null;end;
 begin perform app_private.read_map_pin('https://evil.invalid/?q=3,101');raise exception 'Untrusted map link accepted';exception when invalid_parameter_value then null;end;
end $$;
rollback;
