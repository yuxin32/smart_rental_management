-- Pending remains the historical state; an expired request cannot be accepted.
begin;
set local plpgsql.check_asserts=on;
\ir fixtures/checkpoint_accounts.sql
insert into public.booking(booking_id,owner_id,provider_id,property_id,service_type_id,
 requested_start_at,requested_end_at,current_status)
values ('44444444-4444-4444-8444-444444444444','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','ffffffff-ffff-4fff-8fff-ffffffffffff',
 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',clock_timestamp()-interval '1 hour',
 clock_timestamp()+interval '1 hour','Pending');
set local role authenticated;
select local_test.login('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
do $$ declare r jsonb;n int; begin
 select count(*) into n from public.booking_status_history
  where booking_id='44444444-4444-4444-8444-444444444444';
 -- Imported requests without structured location must still report expiry.
 r:=public.accept_pending_booking('44444444-4444-4444-8444-444444444444');
 assert r->>'accepted'='false' and r->>'reason'='request_expired';
 assert (select current_status from public.booking
  where booking_id='44444444-4444-4444-8444-444444444444')='Pending';
 assert (select count(*) from public.booking_status_history
  where booking_id='44444444-4444-4444-8444-444444444444')=n;
end $$;
select local_test.login('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
do $$ begin
 begin
  perform public.accept_pending_booking('44444444-4444-4444-8444-444444444444');
  raise exception 'Another Provider responded';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
