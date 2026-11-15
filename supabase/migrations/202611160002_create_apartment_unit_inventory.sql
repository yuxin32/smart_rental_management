-- Standard unit code: <block>-<two-digit floor>-<two-digit unit>
-- Example: A-03-06 = Block A, Floor 03, Unit 06.
-- Preserve existing unit IDs so tenancy and meter references remain stable.

update public.rental_unit
set unit_number = 'A-01-01',
    block_and_floor = 'Block A · Floor 01'
where unit_number = 'SIM-A-01-01';

update public.rental_unit
set unit_number = 'B-05-04',
    block_and_floor = 'Block B · Floor 05'
where unit_number = 'SIM-B-05-03';

update public.rental_unit
set unit_number = 'B-08-07',
    block_and_floor = 'Block B · Floor 08'
where unit_number = 'C-08-11';

update public.rental_unit
set unit_number = 'B-08-08',
    block_and_floor = 'Block B · Floor 08'
where unit_number = 'SIM-C-08-11';

insert into public.rental_unit (
  unit_number,
  block_and_floor,
  occupancy_capacity,
  unit_status
)
select
  block_code || '-' || lpad(floor_number::text, 2, '0') || '-' ||
    lpad(unit_number::text, 2, '0'),
  'Block ' || block_code || ' · Floor ' || lpad(floor_number::text, 2, '0'),
  1,
  'available'
from (values ('A'), ('B')) as blocks(block_code)
cross join generate_series(1, 25) as floors(floor_number)
cross join generate_series(1, 8) as units(unit_number)
on conflict (unit_number) do update
set block_and_floor = excluded.block_and_floor,
    occupancy_capacity = greatest(
      rental_unit.occupancy_capacity,
      coalesce((
        select count(*)::int
        from public.tenancy
        where tenancy.unit_id = rental_unit.unit_id
          and tenancy.tenancy_status = 'active'
      ), 0)
    ),
    unit_status = case
      when exists (
        select 1
        from public.tenancy
        where tenancy.unit_id = rental_unit.unit_id
          and tenancy.tenancy_status = 'active'
      ) then 'occupied'
      else rental_unit.unit_status
    end;
