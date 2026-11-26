-- Property identity, rather than a global A/B code, identifies the apartment.
alter table public.rental_unit drop constraint if exists rental_unit_unit_number_key;
alter table public.rental_unit alter column unit_number type text;
alter table public.rental_unit alter column block_and_floor type text;
drop trigger if exists validate_integrated_property_unit on public.property;
drop trigger if exists bind_integrated_property_unit on public.property;
create or replace function app_private.bind_property_unit() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if nullif(btrim(new.unit_name),'') is null or nullif(btrim(new.building_name),'') is null then
    raise exception 'Enter a building name and unit number.' using errcode='22023'; end if;
  insert into public.rental_unit(unit_number,block_and_floor,property_id,occupancy_capacity)
  values(new.unit_name,new.building_name,new.property_id,8)
  on conflict(property_id) do update set unit_number=excluded.unit_number,block_and_floor=excluded.block_and_floor;
  return new;
end;$$;
create trigger bind_integrated_property_unit after insert or update of unit_name,building_name on public.property
for each row execute function app_private.bind_property_unit();
drop function if exists app_private.link_property_unit();
insert into public.rental_unit(unit_number,block_and_floor,property_id,occupancy_capacity)
select unit_name,building_name,property_id,8 from public.property
on conflict(property_id) do update set unit_number=excluded.unit_number,block_and_floor=excluded.block_and_floor;
-- Retain historic unit IDs for meter/reading/billing foreign keys, but remove
-- the obsolete generated inventory from all active assignment choices.
update public.rental_unit set unit_status='inactive' where property_id is null;
notify pgrst,'reload schema';
