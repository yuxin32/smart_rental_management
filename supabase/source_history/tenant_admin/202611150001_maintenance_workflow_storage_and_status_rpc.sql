insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'maintenance-request-images',
  'maintenance-request-images',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.is_allowed_maintenance_image(file_path text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select lower(coalesce(file_path, '')) ~ '\.(jpe?g|png|webp|heic|heif)$';
$$;

revoke all on function public.is_allowed_maintenance_image(text)
from public, anon;
grant execute on function public.is_allowed_maintenance_image(text)
to authenticated;

drop policy if exists maintenance_images_select on storage.objects;
create policy maintenance_images_select
on storage.objects for select to authenticated
using (
  bucket_id = 'maintenance-request-images'
  and (
    public.is_admin()
    or exists (
      select 1
      from public.maintenance_request m
      join public.tenancy t on t.tenancy_id = m.tenancy_id
      where m.image_storage_path = name
        and t.tenant_id = (select auth.uid())
    )
  )
);

drop policy if exists maintenance_images_insert on storage.objects;
create policy maintenance_images_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'maintenance-request-images'
  and public.is_allowed_maintenance_image(name)
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1
    from public.maintenance_request m
    join public.tenancy t on t.tenancy_id = m.tenancy_id
    where m.maintenance_id::text = (storage.foldername(name))[2]
      and t.tenant_id = (select auth.uid())
  )
);

drop policy if exists maintenance_images_delete on storage.objects;
create policy maintenance_images_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'maintenance-request-images'
  and (
    public.is_admin()
    or (storage.foldername(name))[1] = (select auth.uid())::text
  )
);

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
