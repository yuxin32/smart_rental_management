-- Allow administrators to revise an existing draft and either keep it as a
-- draft or publish it. Published announcements remain immutable in this flow.

create or replace function public.update_draft_announcement(
  p_announcement_id uuid,
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
  current_status text;
  normalized_title text := trim(coalesce(p_title, ''));
  normalized_content text := trim(coalesce(p_content, ''));
  normalized_audience_label text := trim(coalesce(p_audience_label, ''));
  target_group text;
  target_status text := case when p_publish then 'published' else 'draft' end;
begin
  if current_admin_id is null or not public.is_admin() then
    raise exception 'Only an active apartment administrator may edit announcements.';
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

  select announcement_status
  into current_status
  from public.announcement
  where announcement_id = p_announcement_id
  for update;

  if current_status is null then
    raise exception 'Announcement draft was not found.';
  end if;

  if current_status <> 'draft' then
    raise exception 'Only draft announcements may be modified.';
  end if;

  if normalized_audience_label = '' then
    normalized_audience_label := case
      when p_audience_scope = 'all_tenants' then 'All tenants'
      else 'Selected units'
    end;
  end if;

  update public.announcement
  set title = normalized_title,
      content = normalized_content,
      audience_scope = p_audience_scope,
      audience_label = normalized_audience_label,
      published_at = case when p_publish then now() else null end,
      announcement_status = target_status
  where announcement_id = p_announcement_id;

  delete from public.announcement_recipient
  where announcement_id = p_announcement_id;

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
    p_announcement_id,
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
      else 'announcement_draft_updated'
    end,
    'announcement',
    p_announcement_id,
    'success',
    jsonb_build_object(
      'audience_scope', p_audience_scope,
      'audience_label', normalized_audience_label,
      'status', target_status
    )
  );

  return p_announcement_id;
end;
$$;

revoke all on function public.update_draft_announcement(
  uuid,
  text,
  text,
  text,
  text,
  boolean
) from public, anon;
grant execute on function public.update_draft_announcement(
  uuid,
  text,
  text,
  text,
  text,
  boolean
) to authenticated;
