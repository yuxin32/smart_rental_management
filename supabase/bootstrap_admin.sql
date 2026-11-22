-- First create an Auth user in the INTEGRATED Supabase project.
-- Replace the UUID below with that new Auth user's UUID; this script contains no password.
begin;
insert into public.user_account(user_id,full_name,email,role,account_status)
select id,coalesce(nullif(raw_user_meta_data->>'full_name',''),'Apartment Administrator'),email,'admin','active'
from auth.users where id='00000000-0000-0000-0000-000000000000'
on conflict(user_id) do nothing;
insert into public.admin(admin_id,admin_code,is_active,can_manage_billing)
select user_id,'ADMIN-001',true,true from public.user_account
where user_id='00000000-0000-0000-0000-000000000000' and role='admin'
on conflict(admin_id) do nothing;
commit;
