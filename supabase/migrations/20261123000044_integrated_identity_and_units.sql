-- Shared identity, lifecycle, and canonical apartment linkage.
create function app_private.initialize_integrated_profile() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.role in ('owner','provider') then
    new.account_status := 'active';
    new.full_name := coalesce(nullif(new.full_name,''), (select raw_user_meta_data->>'requested_full_name' from auth.users where id=new.user_id),'');
  end if;
  return new;
end;$$;
create trigger a_initialize_integrated_profile before insert on public.user_account
for each row execute function app_private.initialize_integrated_profile();
-- Never allow a self-registering caller to create an administrator or tenant role.
drop policy if exists account_self_insert on public.user_account;
create policy account_self_insert on public.user_account for insert to authenticated
with check (user_id=auth.uid() and role in ('owner','provider')
  and account_status='active' and lower(email)=lower(auth.jwt()->>'email'));

alter table public.rental_unit add column property_id uuid unique references public.property(property_id) on delete restrict;
create function app_private.link_property_unit() returns trigger
language plpgsql security definer set search_path='' as $$
declare code text; existing_property uuid;
begin
  code := upper(regexp_replace(btrim(new.unit_name),'[ -]','','g'));
  if code !~ '^[AB](0[1-9]|1[0-9]|2[0-5])0[1-8]$' then
    raise exception 'Use an apartment unit from A-01-01 to B-25-08 (25 floors, 8 units per floor).' using errcode='22023';
  end if;
  code := substring(code,1,1)||'-'||substring(code,2,2)||'-'||substring(code,4,2);
  if tg_op='UPDATE' and new.unit_name is distinct from old.unit_name then
    raise exception 'A registered apartment unit number cannot be changed. Contact the administrator.' using errcode='22023';
  end if;
  new.unit_name := code;
  return new;
end;$$;
create trigger validate_integrated_property_unit before insert or update on public.property
for each row execute function app_private.link_property_unit();
create function app_private.bind_property_unit() returns trigger
language plpgsql security definer set search_path='' as $$
declare existing_property uuid;
begin
  insert into public.rental_unit(unit_number,block_and_floor,property_id)
  values(new.unit_name,'Block '||left(new.unit_name,1)||' · Floor '||substring(new.unit_name,3,2),new.property_id)
  on conflict(unit_number) do update set property_id=excluded.property_id
    where rental_unit.property_id is null or rental_unit.property_id=excluded.property_id;
  if not found then raise exception 'This apartment unit is already registered to a property.' using errcode='23505'; end if;
  return new;
end;$$;
create trigger bind_integrated_property_unit after insert on public.property
for each row execute function app_private.bind_property_unit();
-- Unit is the physical apartment. Tenancy remains the dated tenant-unit association.
create index rental_unit_property_idx on public.rental_unit(property_id);

-- Invitation service needs these operations; RLS continues protecting client access.
grant all on public.user_account,public.admin,public.tenant,public.tenant_registration,public.audit_log to service_role;
grant select,insert,update on public.user_account to authenticated;
-- Prevent the broad legacy profile grant from exposing administrative fields.
revoke insert,update on public.user_account from authenticated;
grant insert(user_id,email,contact_number,role) on public.user_account to authenticated;
grant update(full_name,contact_number) on public.user_account to authenticated;
update public.app_deployment_environment set environment='staging',project_ref='myetpfavvwuevdcybdes',configured_at=now() where singleton;
notify pgrst, 'reload schema';
