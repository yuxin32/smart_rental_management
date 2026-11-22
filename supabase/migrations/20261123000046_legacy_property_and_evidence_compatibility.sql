alter table public.property add column legacy_source_project varchar(20);
comment on column public.property.legacy_source_project is 'Original project for imported property labels outside the integrated A/B unit inventory. No physical apartment ownership is inferred.';
alter table public.booking_evidence add column if not exists before_locked_at_start boolean not null default false;
alter table public.booking_evidence add column if not exists completion_confirmed_at timestamptz;
create or replace function app_private.link_property_unit() returns trigger
language plpgsql security definer set search_path='' as $$
declare code text; existing_property uuid;
begin
  if tg_op='UPDATE' and old.legacy_source_project is not null and new.unit_name is not distinct from old.unit_name then return new; end if;
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
insert into supabase_migrations.schema_migrations(version,name) values ('20261123000046','legacy_property_and_evidence_compatibility') on conflict(version) do nothing;
notify pgrst, 'reload schema';
