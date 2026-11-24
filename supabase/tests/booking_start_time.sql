-- psql -X -v ON_ERROR_STOP=1 -f supabase/tests/booking_start_time.sql
-- Disposable local database only; all fixture helpers/data roll back.
begin;
set local plpgsql.check_asserts=on;
\ir fixtures/checkpoint_accounts.sql
insert into public.booking(booking_id,owner_id,provider_id,property_id,service_type_id,
 requested_start_at,requested_end_at,current_status)
select id,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'ffffffff-ffff-4fff-8fff-ffffffffffff','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',starts,ends,'Accepted'
from (values
 ('11111111-1111-4111-8111-111111111111'::uuid,clock_timestamp()+interval '1 day',clock_timestamp()+interval '1 day 2 hours'),
 ('22222222-2222-4222-8222-222222222222'::uuid,clock_timestamp()-interval '3 hours',clock_timestamp()-interval '1 hour')
) v(id,starts,ends);
set local timezone='America/Los_Angeles';
set local role authenticated;
select local_test.login('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
do $$ begin
 begin perform public.transition_booking('11111111-1111-4111-8111-111111111111','In Progress');
  raise exception 'Owner started provider job'; exception when insufficient_privilege then null; end;
end $$;
select local_test.login('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
do $$ declare n integer; d text; begin
 select count(*) into n from public.booking_status_history where booking_id='11111111-1111-4111-8111-111111111111';
 for i in 1..2 loop
  begin perform public.transition_booking('11111111-1111-4111-8111-111111111111','In Progress');
   raise exception 'Future job started'; exception when sqlstate 'PT409' then
    get stacked diagnostics d=pg_exception_detail; assert d='booking_start_not_reached'; end;
 end loop;
 assert (select current_status from public.booking where booking_id='11111111-1111-4111-8111-111111111111')='Accepted';
 assert (select count(*) from public.booking_status_history where booking_id='11111111-1111-4111-8111-111111111111')=n;
 assert public.begin_evidence_upload('11111111-1111-4111-8111-111111111111',
   gen_random_uuid(),'before','png',128,repeat('a',64))->>'state'='closed';
 begin perform public.transition_booking('22222222-2222-4222-8222-222222222222','In Progress');
  raise exception 'Started without a Before photo'; exception when sqlstate 'PT409' then
   get stacked diagnostics d=pg_exception_detail; assert d='before_photo_required'; end;
 assert public.begin_evidence_upload('22222222-2222-4222-8222-222222222222',
   gen_random_uuid(),'after','png',128,repeat('a',64))->>'state'='closed';
 perform local_test.attach_verified_photo('22222222-2222-4222-8222-222222222222','before');
 assert public.transition_booking('22222222-2222-4222-8222-222222222222','In Progress')->>'status'='In Progress';
 assert (select before_locked_at_start from public.booking_evidence where booking_id='22222222-2222-4222-8222-222222222222');
 assert (select count(*) from public.booking_status_history
   where booking_id='22222222-2222-4222-8222-222222222222' and new_status='In Progress')=1;
 begin perform public.transition_booking('22222222-2222-4222-8222-222222222222','In Progress');
  raise exception 'Started twice'; exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Trigger backstop also covers privileged/direct updates and a second timezone.
set local timezone='Asia/Kuala_Lumpur';
do $$ declare d text; begin
 begin update public.booking set current_status='In Progress' where booking_id='11111111-1111-4111-8111-111111111111';
  raise exception 'Raw update bypassed clock'; exception when sqlstate 'PT409' then
   get stacked diagnostics d=pg_exception_detail; assert d='booking_start_not_reached'; end;
end $$;
rollback;
