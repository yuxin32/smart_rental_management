-- Live tenant-administrator chat and temporary FYP testing access.
-- Document verification remains available, but unit assignment does not depend
-- on it while the testing flag is enabled in the Flutter client.

alter table public.message
  add column if not exists message_type varchar(20) not null default 'text',
  add column if not exists attachment_name varchar(255),
  add column if not exists attachment_mime_type varchar(120),
  add column if not exists attachment_size_bytes bigint,
  add column if not exists expires_at timestamptz;

alter table public.message alter column message_text drop not null;

update public.message
set expires_at = sent_at + interval '2 years'
where expires_at is null;

alter table public.message
  alter column expires_at set default (now() + interval '2 years'),
  alter column expires_at set not null;

alter table public.message
  drop constraint if exists message_type_check,
  drop constraint if exists message_payload_check,
  drop constraint if exists message_attachment_size_check;

alter table public.message
  add constraint message_type_check
    check (message_type in ('text', 'file')),
  add constraint message_payload_check check (
    (
      message_type = 'text'
      and nullif(trim(message_text), '') is not null
      and attachment_storage_path is null
    )
    or
    (
      message_type = 'file'
      and attachment_storage_path is not null
      and attachment_name is not null
    )
  ),
  add constraint message_attachment_size_check check (
    attachment_size_bytes is null
    or attachment_size_bytes between 1 and 10485760
  );

create index if not exists idx_message_conversation_sent_at
  on public.message (conversation_id, sent_at);

create index if not exists idx_message_expires_at
  on public.message (expires_at);

create table if not exists public.chat_attachment_cleanup_queue (
  attachment_storage_path text primary key,
  queued_at timestamptz not null default now()
);

alter table public.chat_attachment_cleanup_queue enable row level security;

drop policy if exists chat_cleanup_admin_select
  on public.chat_attachment_cleanup_queue;
create policy chat_cleanup_admin_select
on public.chat_attachment_cleanup_queue for select to authenticated
using (public.is_admin());

drop policy if exists chat_cleanup_admin_delete
  on public.chat_attachment_cleanup_queue;
create policy chat_cleanup_admin_delete
on public.chat_attachment_cleanup_queue for delete to authenticated
using (public.is_admin());

grant select, delete on public.chat_attachment_cleanup_queue to authenticated;

create or replace function public.queue_deleted_chat_attachment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.attachment_storage_path is not null then
    insert into public.chat_attachment_cleanup_queue (
      attachment_storage_path,
      queued_at
    ) values (
      old.attachment_storage_path,
      now()
    )
    on conflict (attachment_storage_path) do update
    set queued_at = excluded.queued_at;
  end if;

  return old;
end;
$$;

drop trigger if exists trg_queue_deleted_chat_attachment on public.message;
create trigger trg_queue_deleted_chat_attachment
before delete on public.message
for each row execute function public.queue_deleted_chat_attachment();

create or replace function public.can_access_conversation(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversation c
    join public.tenancy t on t.tenancy_id = c.tenancy_id
    where c.conversation_id = target_conversation_id
      and (
        public.is_admin()
        or t.tenant_id = (select auth.uid())
      )
  );
$$;

revoke all on function public.can_access_conversation(uuid)
from public, anon, authenticated;
grant execute on function public.can_access_conversation(uuid)
to authenticated;

drop policy if exists conversation_select on public.conversation;
create policy conversation_select
on public.conversation for select to authenticated
using (public.can_access_conversation(conversation_id));

drop policy if exists message_select on public.message;
create policy message_select
on public.message for select to authenticated
using (
  expires_at > now()
  and public.can_access_conversation(conversation_id)
);

drop policy if exists message_insert on public.message;
create policy message_insert
on public.message for insert to authenticated
with check (
  sender_user_id = (select auth.uid())
  and public.can_access_conversation(conversation_id)
  and expires_at <= now() + interval '2 years 1 minute'
);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'chat-attachments',
  'chat-attachments',
  false,
  10485760,
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
    'text/csv'
  ]::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists chat_attachments_select on storage.objects;
create policy chat_attachments_select
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-attachments'
  and exists (
    select 1
    from public.conversation c
    join public.tenancy t on t.tenancy_id = c.tenancy_id
    where c.conversation_id::text = (storage.foldername(name))[1]
      and (
        public.is_admin()
        or t.tenant_id = (select auth.uid())
      )
  )
);

drop policy if exists chat_attachments_insert on storage.objects;
create policy chat_attachments_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and exists (
    select 1
    from public.conversation c
    join public.tenancy t on t.tenancy_id = c.tenancy_id
    where c.conversation_id::text = (storage.foldername(name))[1]
      and (
        public.is_admin()
        or t.tenant_id = (select auth.uid())
      )
  )
);

drop policy if exists chat_attachments_delete on storage.objects;
create policy chat_attachments_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'chat-attachments'
  and (
    (storage.foldername(name))[2] = (select auth.uid())::text
    or public.is_admin()
  )
);

create or replace function public.update_conversation_last_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversation
  set last_message_at = new.sent_at
  where conversation_id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists trg_update_conversation_last_message on public.message;
create trigger trg_update_conversation_last_message
after insert on public.message
for each row execute function public.update_conversation_last_message();

create or replace function public.get_my_conversations()
returns table (
  chat_conversation_id uuid,
  other_user_id uuid,
  other_party_name text,
  other_party_role text,
  unit_label text,
  chat_status varchar,
  last_message_preview text,
  latest_message_at timestamptz,
  unread_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    return;
  end if;

  if public.is_admin() then
    return query
    select
      c.conversation_id,
      t.tenant_id,
      coalesce(nullif(ua.full_name, ''), ua.email, 'Tenant')::text,
      'tenant'::text,
      case
        when ru.unit_id is null then 'Unit not assigned'
        when nullif(ru.block_and_floor, '') is null then ru.unit_number
        else ru.block_and_floor || ' · ' || ru.unit_number
      end::text,
      c.conversation_status,
      case
        when lm.message_id is null then 'No messages yet'
        when lm.message_type = 'file' then
          'File: ' || coalesce(lm.attachment_name, 'Attachment')
        else left(lm.message_text, 120)
      end::text,
      coalesce(lm.sent_at, c.created_at),
      (
        select count(*)
        from public.message unread
        where unread.conversation_id = c.conversation_id
          and unread.sender_user_id <> current_user_id
          and unread.read_at is null
          and unread.expires_at > now()
      )::bigint
    from public.conversation c
    join public.tenancy t on t.tenancy_id = c.tenancy_id
    join public.user_account ua on ua.user_id = t.tenant_id
    left join public.rental_unit ru on ru.unit_id = t.unit_id
    left join lateral (
      select m.*
      from public.message m
      where m.conversation_id = c.conversation_id
        and m.expires_at > now()
      order by m.sent_at desc
      limit 1
    ) lm on true
    where c.conversation_status <> 'archived'
    order by coalesce(lm.sent_at, c.created_at) desc;
  else
    return query
    select
      c.conversation_id,
      c.admin_id,
      coalesce(nullif(ua.full_name, ''), ua.email, 'Apartment Administrator')::text,
      'admin'::text,
      case
        when nullif(ru.block_and_floor, '') is null then ru.unit_number
        else ru.block_and_floor || ' · ' || ru.unit_number
      end::text,
      c.conversation_status,
      case
        when lm.message_id is null then 'No messages yet'
        when lm.message_type = 'file' then
          'File: ' || coalesce(lm.attachment_name, 'Attachment')
        else left(lm.message_text, 120)
      end::text,
      coalesce(lm.sent_at, c.created_at),
      (
        select count(*)
        from public.message unread
        where unread.conversation_id = c.conversation_id
          and unread.sender_user_id <> current_user_id
          and unread.read_at is null
          and unread.expires_at > now()
      )::bigint
    from public.conversation c
    join public.tenancy t on t.tenancy_id = c.tenancy_id
    join public.user_account ua on ua.user_id = c.admin_id
    join public.rental_unit ru on ru.unit_id = t.unit_id
    left join lateral (
      select m.*
      from public.message m
      where m.conversation_id = c.conversation_id
        and m.expires_at > now()
      order by m.sent_at desc
      limit 1
    ) lm on true
    where t.tenant_id = current_user_id
      and c.conversation_status <> 'archived'
    order by coalesce(lm.sent_at, c.created_at) desc;
  end if;
end;
$$;

grant execute on function public.get_my_conversations() to authenticated;

create or replace function public.mark_conversation_read(
  target_conversation_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_rows integer;
begin
  if not public.can_access_conversation(target_conversation_id) then
    raise exception 'Conversation access is not permitted.';
  end if;

  update public.message
  set delivered_at = coalesce(delivered_at, now()),
      read_at = now()
  where conversation_id = target_conversation_id
    and sender_user_id <> (select auth.uid())
    and read_at is null
    and expires_at > now();

  get diagnostics affected_rows = row_count;
  return affected_rows;
end;
$$;

grant execute on function public.mark_conversation_read(uuid)
to authenticated;

create or replace function public.purge_expired_chat_messages()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_rows integer;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception 'Only an administrator may run chat retention cleanup.';
  end if;

  delete from public.message
  where expires_at <= now();

  get diagnostics affected_rows = row_count;
  return affected_rows;
end;
$$;

revoke all on function public.purge_expired_chat_messages()
from public, anon;
grant execute on function public.purge_expired_chat_messages()
to authenticated, service_role;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message'
  ) then
    alter publication supabase_realtime add table public.message;
  end if;
end;
$$;

create extension if not exists pg_cron;

select cron.schedule(
  'purge-expired-chat-messages',
  '15 3 * * *',
  $$select public.purge_expired_chat_messages();$$
);

-- During module testing, account acceptance is sufficient for assignment.
-- The verification data remains intact and can still be reviewed separately.
create or replace function public.assign_verified_tenant(
  p_registration_id uuid,
  p_unit_id uuid,
  p_start_date date,
  p_end_date date,
  p_monthly_rental_amount numeric,
  p_occupancy_share numeric
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  target_user_id uuid;
  previous_unit_id uuid;
  existing_tenancy_id uuid;
begin
  if current_admin_id is null or not public.is_admin() then
    return false;
  end if;

  if p_start_date is null
     or p_monthly_rental_amount is null
     or p_monthly_rental_amount < 0
     or p_occupancy_share <= 0
     or p_occupancy_share > 1
     or (p_end_date is not null and p_end_date < p_start_date) then
    raise exception 'Invalid tenancy details.';
  end if;

  select auth_user_id
  into target_user_id
  from public.tenant_registration
  where registration_id = p_registration_id
    and auth_user_id is not null
    and registration_status in ('accepted', 'assigned');

  if target_user_id is null then
    raise exception 'The tenant must complete account setup before unit assignment.';
  end if;

  select tenancy_id, unit_id
  into existing_tenancy_id, previous_unit_id
  from public.tenancy
  where tenant_id = target_user_id
    and tenancy_status in ('pending', 'active')
  order by start_date desc
  limit 1;

  if previous_unit_id is not null and previous_unit_id <> p_unit_id then
    update public.rental_unit
    set unit_status = 'available'
    where unit_id = previous_unit_id;
  end if;

  if existing_tenancy_id is null then
    insert into public.tenancy (
      tenant_id,
      unit_id,
      start_date,
      end_date,
      monthly_rental_amount,
      occupancy_share,
      tenancy_status
    ) values (
      target_user_id,
      p_unit_id,
      p_start_date,
      p_end_date,
      p_monthly_rental_amount,
      p_occupancy_share,
      'active'
    )
    returning tenancy_id into existing_tenancy_id;
  else
    update public.tenancy
    set unit_id = p_unit_id,
        start_date = p_start_date,
        end_date = p_end_date,
        monthly_rental_amount = p_monthly_rental_amount,
        occupancy_share = p_occupancy_share,
        tenancy_status = 'active'
    where tenancy_id = existing_tenancy_id;
  end if;

  update public.rental_unit
  set unit_status = 'occupied'
  where unit_id = p_unit_id;

  update public.tenant_registration
  set unit_id = p_unit_id,
      start_date = p_start_date,
      end_date = p_end_date,
      monthly_rental_amount = p_monthly_rental_amount,
      occupancy_share = p_occupancy_share,
      registration_status = 'assigned',
      updated_at = now()
  where registration_id = p_registration_id;

  update public.user_account
  set account_status = 'active',
      updated_at = now()
  where user_id = target_user_id
    and invitation_status = 'accepted';

  insert into public.conversation (
    tenancy_id,
    admin_id,
    conversation_status
  ) values (
    existing_tenancy_id,
    current_admin_id,
    'open'
  )
  on conflict (tenancy_id, admin_id) do update
  set conversation_status = 'open';

  return true;
end;
$$;

grant execute on function public.assign_verified_tenant(
  uuid,
  uuid,
  date,
  date,
  numeric,
  numeric
) to authenticated;

-- Create database-backed chat lists for existing assigned tenants. No sample
-- names or message histories are inserted.
insert into public.conversation (
  tenancy_id,
  admin_id,
  conversation_status
)
select
  t.tenancy_id,
  active_admin.admin_id,
  'open'
from public.tenancy t
cross join lateral (
  select a.admin_id
  from public.admin a
  where a.is_active = true
  order by a.created_at
  limit 1
) active_admin
where t.tenancy_status = 'active'
  and not exists (
    select 1
    from public.conversation c
    where c.tenancy_id = t.tenancy_id
  )
on conflict (tenancy_id, admin_id) do nothing;
