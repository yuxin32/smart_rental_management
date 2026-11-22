-- Additive UAT changes: seed user-selected names on first profile creation,
-- and aggregate the complete Owner portfolio independently of page size.
create function app_private.seed_registration_full_name() returns trigger
language plpgsql security definer set search_path='' as $$
declare requested text; actor uuid;
begin
 if tg_table_name='user_account' then actor:=new.user_id;
 else actor:=new.provider_id; end if;
 select u.raw_user_meta_data->>'requested_full_name' into requested
 from auth.users u where u.id=actor;
 if requested is not null then
  requested:=btrim(requested);
  if length(requested) not between 2 and 60 then
   raise exception 'Enter a name of 2-60 characters' using errcode='22023';
  end if;
  if nullif(new.full_name,'') is null then new.full_name:=requested; end if;
 end if;
 return new;
end;$$;
revoke all on function app_private.seed_registration_full_name() from public,anon,authenticated,service_role;
create trigger seed_account_full_name before insert on public.user_account
 for each row execute function app_private.seed_registration_full_name();
create trigger seed_provider_full_name before insert on public.provider_profile
 for each row execute function app_private.seed_registration_full_name();

create function public.my_owner_portfolio_summary() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 if actor is null or not exists(select 1 from public.user_account a where a.user_id=actor and a.role='owner') then
  raise exception 'Owner authentication required' using errcode='42501';
 end if;
 select jsonb_build_object('actor_id',actor,
  'property_count',(select count(*) from public.property where owner_id=actor),
  'building_count',(select count(distinct building_name) from public.property where owner_id=actor),
  'size_sqft',(select coalesce(sum(size_sqft),0) from public.property where owner_id=actor),
  'open',(select count(*) from public.booking where owner_id=actor and current_status in ('Pending','Accepted','In Progress')),
  'done',(select count(*) from public.booking where owner_id=actor and current_status='Completed'),
  'total',(select count(*) from public.booking where owner_id=actor)) into result;
 return result;
end;$$;
revoke all on function public.my_owner_portfolio_summary() from public,anon,authenticated,service_role;
grant execute on function public.my_owner_portfolio_summary() to authenticated;
