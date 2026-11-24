-- Synthetic disposable rows. No hosted data or credentials.
begin;
insert into auth.users(id,email) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','owner@weekly.invalid'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','provider@weekly.invalid'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','other@weekly.invalid');
insert into public.user_account(user_id,email,role) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','owner@weekly.invalid','owner'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','provider@weekly.invalid','provider'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','other@weekly.invalid','provider');
insert into public.provider_profile(provider_id,service_area,service_origin_address,hourly_rate,approval_status) values
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Area','PRIVATE',50,'approved'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Other','OTHER PRIVATE',50,'approved');
insert into public.provider_weekly_slot(provider_id,weekday,start_time,end_time)
 select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',day,time '08:00',time '18:00' from generate_series(1,7) day;
insert into public.provider_weekly_slot(provider_id,weekday,start_time,end_time)
 values('cccccccc-cccc-4ccc-8ccc-cccccccccccc',1,'06:00','08:00');
insert into public.service_type(service_type_id,name)
 values('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','Weekly fixture cleaning');
insert into public.provider_capability(provider_id,service_type_id)
 values('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1');
insert into public.property(property_id,owner_id,unit_name,building_name,address)
 values('ffffffff-ffff-4fff-8fff-ffffffffffff','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','A-24-08','Synthetic','Private');
insert into public.booking(booking_id,owner_id,provider_id,property_id,service_type_id,
 requested_start_at,requested_end_at,current_status,quote_basis,quoted_rate,quoted_duration_minutes,quoted_amount)
 select '11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','ffffffff-ffff-4fff-8fff-ffffffffffff',
 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
 ((date_trunc('week',clock_timestamp() at time zone 'Asia/Kuala_Lumpur')::date+14)+time '10:00') at time zone 'Asia/Kuala_Lumpur',
 ((date_trunc('week',clock_timestamp() at time zone 'Asia/Kuala_Lumpur')::date+14)+time '12:00') at time zone 'Asia/Kuala_Lumpur',
 'Accepted','hourly',50,120,100;
set local role authenticated;
select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
do $$
declare state jsonb; before_state jsonb; next_state jsonb; changes jsonb;
begin
 state:=public.my_provider_weekly_hours();
 assert state->>'provider_id'=auth.uid()::text;
 assert jsonb_array_length(state->'slots')=7;
 assert state->>'revision'~'^[0-9a-f]{32}$';
 assert state->'required_service_ids'='["eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1"]'::jsonb;
 assert state->'required_intervals'='[{"weekday":1,"start_minute":600,"end_minute":720,"booking_count":1}]'::jsonb;
 changes:='[{"weekday":1,"slots":[{"start_minute":540,"end_minute":780}]},
             {"weekday":2,"slots":[{"start_minute":540,"end_minute":780}]}]';
 next_state:=public.replace_my_weekly_hours(changes,state->>'revision');
 assert next_state->>'revision'<>state->>'revision';
 assert (select count(*) from public.provider_weekly_slot where weekday in(1,2) and start_time='09:00')=2;
 assert (select count(*) from public.provider_weekly_slot)=7;
 before_state:=next_state;
 begin perform public.replace_my_weekly_hours(changes,state->>'revision');
   raise exception 'Stale copy accepted';exception when sqlstate 'PT409' then null;end;
 assert public.my_provider_weekly_hours()=before_state;
 begin perform public.replace_my_weekly_hours('[{"weekday":2,"slots":[]},{"weekday":1,"slots":[]}]',before_state->>'revision');
   raise exception 'Confirmed work cleared';exception when check_violation then null;end;
 assert public.my_provider_weekly_hours()=before_state,'Failed copy partly saved';
 begin perform public.replace_my_weekly_hours('[{"weekday":2,"slots":[{"start_minute":480,"end_minute":540}]}]',before_state->>'revision');
   raise exception 'Short slot saved';exception when check_violation then null;end;
 begin perform public.replace_my_weekly_hours(
   '[{"weekday":2,"slots":[{"start_minute":480,"end_minute":720},{"start_minute":660,"end_minute":780}]}]',before_state->>'revision');
   raise exception 'Overlap saved';exception when check_violation then null;end;
 begin perform public.replace_my_weekly_hours('[{"weekday":2,"slots":[]},{"weekday":2,"slots":[]}]',before_state->>'revision');
   raise exception 'Duplicate day saved';exception when invalid_parameter_value then null;end;
 begin perform public.replace_my_weekly_hours(
   '[{"weekday":2,"slots":[],"provider_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}]',before_state->>'revision');
   raise exception 'Foreign identity accepted';exception when invalid_parameter_value then null;end;
 assert public.my_provider_weekly_hours()=before_state;
 next_state:=public.replace_my_weekly_hours(
   '[{"weekday":1,"slots":[{"start_minute":480,"end_minute":600},{"start_minute":600,"end_minute":720}]}]',before_state->>'revision');
 assert (select count(*) from public.provider_weekly_slot where weekday=1)=2;
 assert jsonb_array_length(next_state->'slots')=8;
 begin delete from public.provider_weekly_slot where weekday=1 and start_time='10:00';
   raise exception 'Raw delete bypassed guard';exception when check_violation then null;end;
 assert jsonb_array_length(public.my_provider_weekly_hours()->'slots')=8;
end $$;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
do $$begin
 begin perform public.my_provider_weekly_hours();raise exception 'Owner read private hours';exception when insufficient_privilege then null;end;
 begin perform public.replace_my_weekly_hours('[{"weekday":1,"slots":[]}]',repeat('0',32));
   raise exception 'Owner wrote hours';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true);
do $$declare state jsonb;begin
 state:=public.my_provider_weekly_hours();
 assert state->>'provider_id'=auth.uid()::text and jsonb_array_length(state->'slots')=1;
 assert state->'required_intervals'='[]'::jsonb;
end $$;
reset role;
do $$begin
 assert (select count(*) from public.provider_weekly_slot where provider_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc')=1;
 assert not has_function_privilege('anon','public.my_provider_weekly_hours()','EXECUTE');
 assert not has_function_privilege('anon','public.replace_my_weekly_hours(jsonb,text)','EXECUTE');
 assert not has_function_privilege('service_role','public.replace_my_weekly_hours(jsonb,text)','EXECUTE');
 assert not has_function_privilege('authenticated','app_private.provider_weekly_state(uuid)','EXECUTE');
end $$;
rollback;
