-- Port of original 035; prerequisites are integrated booking lifecycle 015/016.
-- Original 031 (response deadline), 032 (locations), and 033/034 (weekly editor)
-- are independent features and are intentionally not imported by this port.
-- Server-time protection also covers older clients and direct updates.
create function app_private.require_booking_start_time()
returns trigger language plpgsql set search_path='' as $$
begin
  if old.current_status='Accepted' and new.current_status='In Progress'
     and clock_timestamp() < old.requested_start_at then
    raise exception 'The scheduled start time has not been reached'
      using errcode='PT409',detail='booking_start_not_reached';
  end if;
  return new;
end;
$$;
revoke all on function app_private.require_booking_start_time()
  from public,anon,authenticated,service_role;
create trigger require_booking_start_time
before update of current_status on public.booking
for each row execute function app_private.require_booking_start_time();
