-- Participant-only booking presentation data. Provider access to a rental
-- address must be scoped to their assigned booking, not to all properties.
create function public.list_booking_contexts()
returns table (
  booking_id uuid,
  unit_name text,
  building_name text,
  property_address text,
  service_name text,
  instructions text
)
language sql stable security definer set search_path = '' as $$
  select b.booking_id, p.unit_name, p.building_name,
         p.address as property_address, s.name as service_name,
         b.instructions
  from public.booking b
  join public.property p on p.property_id = b.property_id
  join public.service_type s on s.service_type_id = b.service_type_id
  where auth.uid() is not null
    and (b.owner_id = auth.uid() or b.provider_id = auth.uid());
$$;
revoke execute on function public.list_booking_contexts()
  from public, anon;
grant execute on function public.list_booking_contexts()
  to authenticated;
