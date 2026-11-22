-- Keep property-window edits serialised with provider acceptance after
-- 202610220005_provider_data_visibility.sql made raw provider rows own-only.
-- An Owner's ordinary RLS context can see their Booking but cannot SELECT
-- another user's ProviderProfile, so the original invoker-rights trigger
-- silently skipped its FOR UPDATE lock.

create or replace function public.lock_property_window_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_provider_id uuid;
begin
  if new.cleaning_window_start is distinct from old.cleaning_window_start or
     new.cleaning_window_end is distinct from old.cleaning_window_end then
    -- Property UPDATE remains Owner-only by table RLS. Take the same provider
    -- lock as accept_pending_booking before checking confirmed intervals.
    for v_provider_id in
      select distinct b.provider_id from public.booking b
      where b.property_id = old.property_id and
            b.current_status in ('Pending', 'Accepted', 'In Progress')
      order by b.provider_id
    loop
      perform 1 from public.provider_profile p
      where p.provider_id = v_provider_id for update;
    end loop;
    if exists (
      select 1 from public.booking b
      where b.property_id = old.property_id and
            b.current_status in ('Accepted', 'In Progress') and
            b.requested_end_at > now() and
            (
              (b.requested_start_at at time zone 'Asia/Kuala_Lumpur')::time
                < new.cleaning_window_start or
              (b.requested_end_at at time zone 'Asia/Kuala_Lumpur')::time
                > new.cleaning_window_end
            )
    ) then
      raise exception 'Cleaning window change conflicts with a confirmed booking'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

-- A trigger executes automatically; authenticated users must not call its
-- elevated body directly. The trigger remains attached from migration 001.
revoke execute on function public.lock_property_window_change()
  from public, anon, authenticated;
