-- Database-backed announcement workflow for the Admin and Tenant modules.

alter table public.announcement
  add column if not exists audience_label varchar(80) not null default 'All tenants',
  add column if not exists updated_at timestamptz not null default now();

update public.announcement
set audience_label = case audience_scope
  when 'all_tenants' then 'All tenants'
  when 'selected_units' then 'Selected units'
  when 'selected_tenants' then 'Selected tenants'
  else 'All tenants'
end
where audience_label is null
   or trim(audience_label) = ''
   or (
     audience_label = 'All tenants'
     and audience_scope <> 'all_tenants'
   );

drop trigger if exists trg_announcement_updated_at on public.announcement;
create trigger trg_announcement_updated_at
before update on public.announcement
for each row execute function public.set_updated_at();

create index if not exists idx_announcement_status_published_at
  on public.announcement (announcement_status, published_at desc);

-- Administrators can retrieve drafts and published records. Tenants can only
-- retrieve active published records addressed to all tenants or to themselves.
drop policy if exists announcement_select on public.announcement;
create policy announcement_select
on public.announcement for select to authenticated
using (
  public.is_admin()
  or (
    announcement_status = 'published'
    and published_at is not null
    and published_at <= now()
    and (expires_at is null or expires_at > now())
    and (
      audience_scope = 'all_tenants'
      or exists (
        select 1
        from public.announcement_recipient recipient
        where recipient.announcement_id = announcement.announcement_id
          and recipient.tenant_id = (select auth.uid())
      )
    )
  )
);

create or replace function public.create_announcement(
  p_title text,
  p_content text,
  p_audience_scope text,
  p_audience_label text,
  p_publish boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  new_announcement_id uuid;
  normalized_title text := trim(coalesce(p_title, ''));
  normalized_content text := trim(coalesce(p_content, ''));
  normalized_audience_label text := trim(coalesce(p_audience_label, ''));
  target_group text;
  target_status text := case when p_publish then 'published' else 'draft' end;
begin
  if current_admin_id is null or not public.is_admin() then
    raise exception 'Only an active apartment administrator may create announcements.';
  end if;

  if normalized_title = '' or char_length(normalized_title) > 150 then
    raise exception 'Announcement title must contain between 1 and 150 characters.';
  end if;

  if normalized_content = '' or char_length(normalized_content) > 5000 then
    raise exception 'Announcement message must contain between 1 and 5000 characters.';
  end if;

  if p_audience_scope not in ('all_tenants', 'selected_units') then
    raise exception 'Unsupported announcement audience.';
  end if;

  if normalized_audience_label = '' then
    normalized_audience_label := case
      when p_audience_scope = 'all_tenants' then 'All tenants'
      else 'Selected units'
    end;
  end if;

  insert into public.announcement (
    created_by_admin_id,
    title,
    content,
    audience_scope,
    audience_label,
    published_at,
    announcement_status
  ) values (
    current_admin_id,
    normalized_title,
    normalized_content,
    p_audience_scope,
    normalized_audience_label,
    case when p_publish then now() else null end,
    target_status
  )
  returning announcement_id into new_announcement_id;

  target_group := trim(
    regexp_replace(normalized_audience_label, '\s+tenants$', '', 'i')
  );

  insert into public.announcement_recipient (
    announcement_id,
    tenant_id,
    delivery_status,
    delivered_at
  )
  select
    new_announcement_id,
    tenancy.tenant_id,
    case when p_publish then 'delivered' else 'pending' end,
    case when p_publish then now() else null end
  from public.tenancy tenancy
  join public.rental_unit rental_unit on rental_unit.unit_id = tenancy.unit_id
  where tenancy.tenancy_status = 'active'
    and (
      p_audience_scope = 'all_tenants'
      or lower(
        coalesce(nullif(rental_unit.block_and_floor, ''), rental_unit.unit_number)
      ) like '%' || lower(target_group) || '%'
    )
  on conflict (announcement_id, tenant_id) do nothing;

  insert into public.audit_log (
    actor_user_id,
    action_type,
    entity_type,
    entity_id,
    outcome,
    metadata
  ) values (
    current_admin_id,
    case when p_publish
      then 'announcement_published'
      else 'announcement_draft_saved'
    end,
    'announcement',
    new_announcement_id,
    'success',
    jsonb_build_object(
      'audience_scope', p_audience_scope,
      'audience_label', normalized_audience_label,
      'status', target_status
    )
  );

  return new_announcement_id;
end;
$$;

revoke all on function public.create_announcement(text, text, text, text, boolean)
from public, anon;
grant execute on function public.create_announcement(text, text, text, text, boolean)
to authenticated;
