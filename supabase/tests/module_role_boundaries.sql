-- The integrated JWT role is authenticated for all four app roles. RPCs must
-- enforce the application role/ownership, rather than trusting the visible UI.
begin;
set local plpgsql.check_asserts=on;
\ir fixtures/checkpoint_accounts.sql
set local role authenticated;
do $$ declare actor uuid; begin
 foreach actor in array array[
  '77777777-7777-4777-8777-777777777777'::uuid,
  '88888888-8888-4888-8888-888888888888'::uuid]
 loop
  perform local_test.login(actor);
  begin
   perform public.find_provider_matches('ffffffff-ffff-4fff-8fff-ffffffffffff',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',now()+interval '1 day',now()+interval '1 day 2 hours');
   raise exception 'Non-owner searched another role rental';
  exception when insufficient_privilege then null; end;
  begin
   perform public.my_provider_weekly_hours();
   raise exception 'Non-provider read private weekly editor data';
  exception when insufficient_privilege then null; end;
  begin
   perform public.my_service_location();
   raise exception 'Non-provider read private service location';
  exception when insufficient_privilege then null; end;
 end loop;
end $$;
reset role;
do $$ begin
 assert not has_function_privilege('authenticated',
  'app_private.create_pending_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,text,text)','EXECUTE');
 assert not has_function_privilege('authenticated','app_private.accept_pending_booking(uuid)','EXECUTE');
 assert not has_function_privilege('anon','public.find_provider_matches(uuid,uuid,timestamptz,timestamptz)','EXECUTE');
 assert not has_function_privilege('anon','public.replace_my_weekly_hours(jsonb,text)','EXECUTE');
 assert has_function_privilege('authenticated','public.replace_my_weekly_hours(jsonb,text)','EXECUTE');
end $$;
rollback;
