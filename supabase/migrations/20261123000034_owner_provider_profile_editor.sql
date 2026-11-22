-- Own-profile editor, explicit mutable fields, no role/approval/score writes.
alter table public.provider_profile
  add column full_name text check(full_name is null or length(btrim(full_name)) between 2 and 60),
  add column avatar_color_index smallint not null default 0 check(avatar_color_index between 0 and 5),
  add column show_phone_to_owners boolean not null default false,
  add column profile_revision bigint not null default 1;

create function app_private.bump_provider_profile_revision()
returns trigger language plpgsql set search_path='' as $$
begin new.profile_revision:=old.profile_revision+1;return new;end;
$$;
revoke all on function app_private.bump_provider_profile_revision() from public,anon,authenticated,service_role;
create trigger bump_provider_profile_revision before update on public.provider_profile
  for each row execute function app_private.bump_provider_profile_revision();

-- Capability edits through the pre-existing setup route also invalidate drafts.
create function app_private.bump_capability_profile_revision()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  update public.provider_profile set profile_revision=profile_revision
    where provider_id=coalesce(new.provider_id,old.provider_id);
  return null;
end;
$$;
revoke all on function app_private.bump_capability_profile_revision() from public,anon,authenticated,service_role;
create trigger bump_capability_profile_revision after insert or delete on public.provider_capability
  for each row execute function app_private.bump_capability_profile_revision();

create function public.my_provider_profile()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_result jsonb;
begin
  if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor and role='provider') then
    raise exception 'Provider authentication required' using errcode='42501';
  end if;
  select jsonb_build_object(
    'provider_id',p.provider_id,'full_name',p.full_name,'bio',p.bio,
    'hourly_rate',p.hourly_rate,'daily_rate',p.daily_rate,'service_area',p.service_area,
    'service_origin_address',p.service_origin_address,'avatar_color_index',p.avatar_color_index,
    'show_phone_to_owners',p.show_phone_to_owners,'revision',p.profile_revision,
    'contact_number',a.contact_number,'email',u.email,'approval_status',p.approval_status,
    'rating_average',(select round(avg(rating),2) from public.booking_review where provider_id=v_actor),
    'review_count',(select count(*) from public.booking_review where provider_id=v_actor),
    'completed_jobs',(select count(*) from public.booking where provider_id=v_actor and current_status='Completed'),
    'active_jobs',(select count(*) from public.booking where provider_id=v_actor and
      current_status in ('Accepted','In Progress') and requested_start_at<statement_timestamp()+interval '7 days'
      and requested_end_at>statement_timestamp()),
    'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.service_type_id,'name',s.name,
      'selected',exists(select 1 from public.provider_capability c where c.provider_id=v_actor and c.service_type_id=s.service_type_id))
      order by s.name) from public.service_type s),'[]'::jsonb),
    'weekly_slots',coalesce((select jsonb_agg(jsonb_build_object('weekday',weekday,'start_time',start_time,'end_time',end_time)
      order by weekday,start_time) from public.provider_weekly_slot where provider_id=v_actor),'[]'::jsonb)
  ) into v_result from public.provider_profile p join public.user_account a on a.user_id=p.provider_id
    join auth.users u on u.id=p.provider_id where p.provider_id=v_actor;
  if v_result is null then raise exception 'Provider profile required' using errcode='P0002';end if;
  return v_result;
end;
$$;
revoke all on function public.my_provider_profile() from public,anon,authenticated,service_role;
grant execute on function public.my_provider_profile() to authenticated;

create function public.save_my_provider_profile(p_input jsonb,p_expected_revision bigint,p_expected_contact text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid:=auth.uid(); v_profile public.provider_profile%rowtype;
  v_contact text; v_phone text;v_hourly numeric;v_daily numeric;v_services uuid[];
begin
  if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor and role='provider') then
    raise exception 'Provider authentication required' using errcode='42501';
  end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' or
    exists(select 1 from jsonb_object_keys(p_input) k where k not in
      ('full_name','bio','service_area','service_origin_address','hourly_rate','daily_rate',
       'avatar_color_index','show_phone_to_owners','contact_number','service_type_ids')) or
    not (p_input ?& array['full_name','bio','service_area','service_origin_address','hourly_rate','daily_rate',
       'avatar_color_index','show_phone_to_owners','contact_number','service_type_ids']) then
    raise exception 'Only explicit editable profile fields are accepted' using errcode='22023';
  end if;
  if jsonb_typeof(p_input->'full_name')<>'string' or length(btrim(p_input->>'full_name')) not between 2 and 60 or
    jsonb_typeof(p_input->'bio')<>'string' or length(p_input->>'bio')>200 or
    jsonb_typeof(p_input->'service_area')<>'string' or length(btrim(p_input->>'service_area')) not between 1 and 200 or
    jsonb_typeof(p_input->'service_origin_address')<>'string' or length(btrim(p_input->>'service_origin_address')) not between 1 and 500 or
    jsonb_typeof(p_input->'show_phone_to_owners')<>'boolean' or
    jsonb_typeof(p_input->'avatar_color_index')<>'number' or
    (p_input->>'avatar_color_index')::numeric <> trunc((p_input->>'avatar_color_index')::numeric) or
    (p_input->>'avatar_color_index')::integer not between 0 and 5 or
    jsonb_typeof(p_input->'contact_number') not in ('null','string') or
    jsonb_typeof(p_input->'hourly_rate') not in ('number','null') or
    jsonb_typeof(p_input->'daily_rate') not in ('number','null') or
    jsonb_typeof(p_input->'service_type_ids')<>'array' or
    jsonb_array_length(p_input->'service_type_ids') not between 1 and 50 then
    raise exception 'Invalid profile fields' using errcode='22023';
  end if;
  v_phone:=nullif(btrim(p_input->>'contact_number'),'');
  if (v_phone is not null and (v_phone !~ '^\+?[0-9 ()-]+$' or
      length(regexp_replace(v_phone,'[^0-9]','','g')) not between 9 and 15)) or
      ((p_input->>'show_phone_to_owners')::boolean and v_phone is null) then
    raise exception 'Valid phone required when sharing contact' using errcode='22023';
  end if;
  v_hourly:=(p_input->>'hourly_rate')::numeric;v_daily:=(p_input->>'daily_rate')::numeric;
  if (v_hourly is null and v_daily is null) or
    (v_hourly is not null and (v_hourly<=0 or v_hourly>99999999.99 or round(v_hourly,2)<>v_hourly)) or
    (v_daily is not null and (v_daily<=0 or v_daily>99999999.99 or round(v_daily,2)<>v_daily)) then
    raise exception 'Positive hourly or daily rate with at most two decimals required' using errcode='22023';
  end if;
  select array_agg(value::uuid) into v_services from jsonb_array_elements_text(p_input->'service_type_ids');
  select * into v_profile from public.provider_profile where provider_id=v_actor for update;
  if not found then raise exception 'Provider profile required' using errcode='P0002';end if;
  select contact_number into v_contact from public.user_account where user_id=v_actor for update;
  if p_expected_revision is null or v_profile.profile_revision<>p_expected_revision or
    v_contact is distinct from p_expected_contact then
    raise exception 'Profile changed; reload before saving' using errcode='40001';
  end if;
  -- Existing capability operation serialises and protects confirmed bookings.
  -- Any failure rolls back contact, appearance, rates and capabilities together.
  perform public.replace_provider_capabilities(v_services);
  update public.user_account set contact_number=v_phone where user_id=v_actor;
  update public.provider_profile set full_name=btrim(p_input->>'full_name'),bio=btrim(p_input->>'bio'),
    service_area=btrim(p_input->>'service_area'),service_origin_address=btrim(p_input->>'service_origin_address'),
    hourly_rate=v_hourly,daily_rate=v_daily,avatar_color_index=(p_input->>'avatar_color_index')::smallint,
    show_phone_to_owners=(p_input->>'show_phone_to_owners')::boolean where provider_id=v_actor;
  return public.my_provider_profile();
end;
$$;
revoke all on function public.save_my_provider_profile(jsonb,bigint,text) from public,anon,authenticated,service_role;
grant execute on function public.save_my_provider_profile(jsonb,bigint,text) to authenticated;

-- Phone sharing is enforced by server, never by a widget-only privacy switch.
-- No directory-wide contacts, email or private origin are exposed.
create function public.booking_provider_contact(p_booking_id uuid)
returns text language sql stable security definer set search_path='' as $$
  select a.contact_number from public.booking b
    join public.provider_profile p on p.provider_id=b.provider_id
    join public.user_account a on a.user_id=p.provider_id
  where auth.uid() is not null and b.booking_id=p_booking_id and b.owner_id=auth.uid()
    and b.current_status in ('Accepted','In Progress') and p.show_phone_to_owners;
$$;
revoke all on function public.booking_provider_contact(uuid) from public,anon,authenticated,service_role;
grant execute on function public.booking_provider_contact(uuid) to authenticated;
