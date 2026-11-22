begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','integration-owner@example.invalid','{"requested_role":"owner","requested_full_name":"Integration Owner"}'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','integration-admin@example.invalid','{}');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","email":"integration-owner@example.invalid","role":"authenticated"}',true);
insert into public.user_account(user_id,email,role) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','integration-owner@example.invalid','owner');
insert into public.property(owner_id,unit_name,building_name,address,bedrooms,size_sqft)
 values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','A12-05','Integration Building','Synthetic test address',2,900);
reset role;
do $$ begin
 if not exists(select 1 from public.user_account where user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and full_name='Integration Owner' and account_status='active') then raise exception 'Owner profile initialization failed'; end if;
 if not exists(select 1 from public.rental_unit r join public.property p using(property_id) where r.unit_number='A-12-05' and p.unit_name=r.unit_number) then raise exception 'Canonical unit mapping failed'; end if;
end $$;
select 'PASS: owner self-registration, active profile, normalized apartment, and property-unit FK' as result;
rollback;
