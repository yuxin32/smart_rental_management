-- Shared apartment unit inventory for Block A and Block B.
-- Unit code format: <block>-<two-digit floor>-<two-digit unit>.

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
on conflict (unit_number) do nothing;
