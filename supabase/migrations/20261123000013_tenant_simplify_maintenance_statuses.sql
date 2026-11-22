-- Collapse the previous intermediate and closed states into the simpler
-- maintenance lifecycle used by the application.
update public.maintenance_request
set request_status = case request_status
  when 'under_review' then 'submitted'
  when 'closed' then 'resolved'
  else request_status
end
where request_status in ('under_review', 'closed');

update public.maintenance_update
set old_status = case old_status
      when 'under_review' then 'submitted'
      when 'closed' then 'resolved'
      else old_status
    end,
    new_status = case new_status
      when 'under_review' then 'submitted'
      when 'closed' then 'resolved'
      else new_status
    end
where old_status in ('under_review', 'closed')
   or new_status in ('under_review', 'closed');

alter table public.maintenance_request
  drop constraint if exists maintenance_request_request_status_check;

alter table public.maintenance_request
  add constraint maintenance_request_request_status_check
  check (request_status in ('submitted', 'in_progress', 'resolved', 'rejected'));

create or replace function public.update_maintenance_request_status(
  p_maintenance_id uuid,
  p_new_status varchar,
  p_remarks text default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  previous_status varchar(20);
begin
  if not public.is_admin() then
    raise exception 'Only an apartment administrator can update a maintenance request.';
  end if;

  if p_new_status not in ('in_progress', 'resolved', 'rejected') then
    raise exception 'The selected maintenance status is invalid.';
  end if;

  select request_status into previous_status
  from public.maintenance_request
  where maintenance_id = p_maintenance_id
  for update;

  if previous_status is null then
    raise exception 'Maintenance request not found.';
  end if;

  update public.maintenance_request
  set request_status = p_new_status,
      assigned_admin_id = current_admin_id,
      resolved_at = case
        when p_new_status = 'resolved' then coalesce(resolved_at, now())
        else null
      end
  where maintenance_id = p_maintenance_id;

  insert into public.maintenance_update (
    maintenance_id, updated_by_admin_id, old_status, new_status, remarks
  ) values (
    p_maintenance_id, current_admin_id, previous_status, p_new_status,
    nullif(trim(p_remarks), '')
  );
end;
$$;

revoke all on function public.update_maintenance_request_status(uuid, varchar, text)
from public, anon;
grant execute on function public.update_maintenance_request_status(uuid, varchar, text)
to authenticated;
