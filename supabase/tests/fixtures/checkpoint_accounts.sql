-- Included INSIDE each rollback-only test. Synthetic local Auth/Storage only.
\ir verified_evidence.sql
insert into auth.users(id,email,raw_user_meta_data) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','owner@checkpoint.invalid','{"requested_full_name":"Checkpoint Owner"}'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','provider@checkpoint.invalid','{}'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','outsider@checkpoint.invalid','{}'),
 ('77777777-7777-4777-8777-777777777777','tenant@checkpoint.invalid','{}'),
 ('88888888-8888-4888-8888-888888888888','admin@checkpoint.invalid','{}');
insert into public.user_account(user_id,email,role,account_status) values
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','provider@checkpoint.invalid','provider','active'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','outsider@checkpoint.invalid','provider','active'),
 ('77777777-7777-4777-8777-777777777777','tenant@checkpoint.invalid','tenant','active'),
 ('88888888-8888-4888-8888-888888888888','admin@checkpoint.invalid','admin','active');
insert into public.tenant(tenant_id) values ('77777777-7777-4777-8777-777777777777');
insert into public.admin(admin_id,admin_code) values ('88888888-8888-4888-8888-888888888888','CHECKPOINT');
insert into public.provider_profile(provider_id,service_area,service_origin_address,hourly_rate,approval_status)
 values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Synthetic','Synthetic',50,'approved');
insert into public.service_type(service_type_id,name)
 values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','Checkpoint regression');
-- Exercise the integrated self-registration policy and physical-unit binding.
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","email":"owner@checkpoint.invalid","role":"authenticated"}',true);
insert into public.user_account(user_id,email,role)
 values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','owner@checkpoint.invalid','owner');
reset role;
-- Properties are written through owner RPCs in the app. Seed the synthetic
-- record as the local administrator while still exercising unit-binding triggers.
insert into public.property(property_id,owner_id,unit_name,building_name,address)
 values ('ffffffff-ffff-4fff-8fff-ffffffffffff','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','A2508','Synthetic','Synthetic');
do $$ begin
 assert (select account_status='active' and full_name='Checkpoint Owner' from public.user_account
   where user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 assert (select count(*) from public.rental_unit r join public.property p using(property_id)
   where p.property_id='ffffffff-ffff-4fff-8fff-ffffffffffff' and r.unit_number='A-25-08' and p.unit_name=r.unit_number)=1;
end $$;
create function local_test.login(p_id uuid) returns void language plpgsql set search_path='' as $$
begin
 perform set_config('request.jwt.claim.sub',p_id::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_id,'role','authenticated')::text,true);
end $$;
revoke all on function local_test.login(uuid) from public;
grant execute on function local_test.login(uuid) to authenticated;
