-- Local synthetic Auth/Storage only. Every helper and record is rolled back.
begin;
set local plpgsql.check_asserts=on;
\ir fixtures/checkpoint_accounts.sql
insert into public.booking(booking_id,owner_id,provider_id,property_id,service_type_id,
 requested_start_at,requested_end_at,current_status)
values ('33333333-3333-4333-8333-333333333333','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','ffffffff-ffff-4fff-8fff-ffffffffffff',
 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',clock_timestamp()-interval '3 hours',
 clock_timestamp()-interval '1 hour','Accepted');

set local role authenticated;
-- Owner, unrelated Provider, Tenant and Admin cannot use Provider-only RPCs.
do $$ declare actor uuid; begin
 foreach actor in array array[
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid,
  '77777777-7777-4777-8777-777777777777'::uuid,
  '88888888-8888-4888-8888-888888888888'::uuid]
 loop
  perform local_test.login(actor);
  begin
   perform public.complete_cleaning_booking('33333333-3333-4333-8333-333333333333',true,'');
   raise exception 'Another role completed the job';
  exception when insufficient_privilege then null; end;
  begin
   perform public.transition_booking('33333333-3333-4333-8333-333333333333','In Progress');
   raise exception 'Another role started the job';
  exception when insufficient_privilege then null; end;
 end loop;
end $$;
select local_test.login('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
do $$ declare before_photo text; after_photo text; result jsonb; n int; begin
 assert public.begin_evidence_upload('33333333-3333-4333-8333-333333333333',
   gen_random_uuid(),'after','png',128,repeat('a',64))->>'state'='closed';
 before_photo:=local_test.attach_verified_photo('33333333-3333-4333-8333-333333333333','before');
 assert public.transition_booking('33333333-3333-4333-8333-333333333333','In Progress')->>'status'='In Progress';
 assert (select before_locked_at_start from public.booking_evidence
   where booking_id='33333333-3333-4333-8333-333333333333');
 assert public.begin_evidence_upload('33333333-3333-4333-8333-333333333333',
   gen_random_uuid(),'before','png',128,repeat('a',64))->>'state'='closed';
 begin
  perform public.remove_evidence_photo('33333333-3333-4333-8333-333333333333','before',before_photo);
  raise exception 'Locked Before photo was removed';
 exception when check_violation then null; end;
 begin
  perform public.complete_cleaning_booking('33333333-3333-4333-8333-333333333333',false,'');
  raise exception 'Completed without confirmation';
 exception when check_violation then null; end;
 begin
  perform public.complete_cleaning_booking('33333333-3333-4333-8333-333333333333',true,'');
  raise exception 'Completed without After';
 exception when check_violation then null; end;
 after_photo:=local_test.attach_verified_photo('33333333-3333-4333-8333-333333333333','after');
 begin
  perform public.transition_booking('33333333-3333-4333-8333-333333333333','Completed');
  raise exception 'Legacy RPC bypassed confirmation';
 exception when check_violation then null; end;
 begin
  perform public.complete_cleaning_booking('33333333-3333-4333-8333-333333333333',true,repeat('x',1001));
  raise exception 'Overlong comments accepted';
 exception when check_violation then null; end;
 result:=public.complete_cleaning_booking('33333333-3333-4333-8333-333333333333',true,'');
 assert result->>'status'='Completed';
 assert (select completion_remarks='' from public.booking_evidence
   where booking_id='33333333-3333-4333-8333-333333333333');
 select count(*) into n from public.booking_status_history
  where booking_id='33333333-3333-4333-8333-333333333333' and new_status='Completed';
 assert n=1;
 assert public.complete_cleaning_booking('33333333-3333-4333-8333-333333333333',true,'')->>'status'='Completed';
 assert (select count(*) from public.booking_status_history
  where booking_id='33333333-3333-4333-8333-333333333333' and new_status='Completed')=n;
end $$;
select local_test.login('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
do $$ begin
 assert (select count(*) from public.booking_evidence
  where booking_id='33333333-3333-4333-8333-333333333333' and before_path is not null and after_path is not null)=1;
end $$;
reset role;
do $$ begin
 assert (select completion_confirmed_at is not null from public.booking_evidence
  where booking_id='33333333-3333-4333-8333-333333333333');
 begin
  update public.booking_evidence set before_path=null
   where booking_id='33333333-3333-4333-8333-333333333333';
  raise exception 'Direct update bypassed Before lock';
 exception when check_violation then null; end;
 assert not has_function_privilege('anon','public.complete_cleaning_booking(uuid,boolean,text)','EXECUTE');
 assert not has_function_privilege('service_role','public.complete_cleaning_booking(uuid,boolean,text)','EXECUTE');
end $$;
rollback;
