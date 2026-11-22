-- Register immutable objects before upload. Only RPCs can attach evidence;
-- cleanup tombstones cannot ever become attachable again. No Storage object
-- is deleted by SQL: the authenticated client must use the Storage API.
create table public.evidence_upload (
  upload_id uuid primary key,
  booking_id uuid not null references public.booking(booking_id),
  provider_id uuid not null references public.user_account(user_id),
  kind text not null check (kind in ('before', 'after')),
  object_path text not null unique,
  expected_previous_path text,
  byte_size integer check (byte_size between 1 and 5242880),
  sha256 text check (sha256 ~ '^[a-f0-9]{64}$'),
  state text not null default 'pending'
    check (state in ('pending', 'attached', 'retired', 'deleting', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index evidence_upload_booking_state on public.evidence_upload(booking_id, state, created_at);
create index evidence_upload_cleanup_candidates on public.evidence_upload(state, created_at, booking_id);
create index booking_evidence_before_path on public.booking_evidence(before_path) where before_path is not null;
create index booking_evidence_after_path on public.booking_evidence(after_path) where after_path is not null;
alter table public.evidence_upload enable row level security;
revoke all on public.evidence_upload from public, anon, authenticated;
grant select on public.evidence_upload to authenticated;
create policy evidence_upload_provider_read on public.evidence_upload
  for select to authenticated using (provider_id = (select auth.uid()));

-- Serialize photo/remarks writes against completion, using the lifecycle's
-- provider-then-booking lock order. No caller-provided Owner/Provider IDs.
create function public.lock_evidence_booking(p_booking_id uuid)
returns public.booking language plpgsql security definer set search_path = '' as $$
declare v_booking public.booking%rowtype; v_provider uuid;
begin
  select provider_id into v_provider from public.booking where booking_id = p_booking_id;
  if auth.uid() is null or v_provider is distinct from auth.uid() then
    raise exception 'Assigned provider required' using errcode = '42501';
  end if;
  perform 1 from public.provider_profile where provider_id = v_provider for update;
  select * into v_booking from public.booking where booking_id = p_booking_id for update;
  if not found then raise exception 'Booking not found' using errcode = 'P0002'; end if;
  return v_booking;
end $$;
revoke all on function public.lock_evidence_booking(uuid) from public, anon, authenticated;

create function public.begin_evidence_upload(
  p_booking_id uuid, p_upload_id uuid, p_kind text,
  p_extension text, p_byte_size integer, p_sha256 text, p_expected_previous_path text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_booking public.booking%rowtype; v_upload public.evidence_upload%rowtype; v_previous text;
begin
  v_booking := public.lock_evidence_booking(p_booking_id);
  if p_upload_id is null or p_kind is null or p_kind not in ('before','after') or
     p_extension is null or p_extension not in ('jpg','png') or
     p_byte_size is null or p_byte_size not between 1 and 5242880 or
     p_sha256 is null or p_sha256 !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid image manifest' using errcode = '23514';
  end if;
  select * into v_upload from public.evidence_upload where upload_id = p_upload_id for update;
  if found then
    if v_upload.provider_id <> auth.uid() or v_upload.booking_id <> p_booking_id or
       v_upload.kind <> p_kind or v_upload.byte_size is distinct from p_byte_size or
       v_upload.sha256 is distinct from p_sha256 or
       v_upload.expected_previous_path is distinct from p_expected_previous_path or
       v_upload.object_path <> p_booking_id::text || '/' || p_kind || '_' || p_upload_id::text || '.' || p_extension then
      raise exception 'Upload token cannot be reused for different content' using errcode = '23514';
    end if;
  else
    if v_booking.current_status <> 'In Progress' then
      return jsonb_build_object('state','closed');
    end if;
    select case when p_kind = 'before' then before_path else after_path end into v_previous
      from public.booking_evidence where booking_id = p_booking_id;
    if v_previous is distinct from p_expected_previous_path then
      return jsonb_build_object('state','photo_changed');
    end if;
    insert into public.evidence_upload(upload_id,booking_id,provider_id,kind,
      object_path,expected_previous_path,byte_size,sha256)
    values(p_upload_id,p_booking_id,auth.uid(),p_kind,
      p_booking_id::text || '/' || p_kind || '_' || p_upload_id::text || '.' || p_extension,
      v_previous,p_byte_size,p_sha256) returning * into v_upload;
  end if;
  if v_upload.state = 'pending' and
     (v_booking.current_status <> 'In Progress' or v_upload.created_at <= now() - interval '24 hours') then
    return jsonb_build_object('state','expired_or_closed');
  end if;
  return jsonb_build_object('state',v_upload.state,'path',v_upload.object_path,
    'uploaded',exists(select 1 from storage.objects
      where bucket_id = 'cleaning-evidence' and name = v_upload.object_path));
end $$;

create function public.attach_evidence_upload(p_booking_id uuid, p_upload_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_booking public.booking%rowtype; v_upload public.evidence_upload%rowtype; v_previous text;
begin
  v_booking := public.lock_evidence_booking(p_booking_id);
  select * into v_upload from public.evidence_upload where upload_id = p_upload_id
    and booking_id = p_booking_id and provider_id = auth.uid() for update;
  if not found then raise exception 'Upload not found' using errcode = '42501'; end if;
  select case when v_upload.kind = 'before' then before_path else after_path end into v_previous
    from public.booking_evidence where booking_id = p_booking_id;
  if v_upload.state = 'attached' and v_previous = v_upload.object_path then
    return jsonb_build_object('attached',true,'path',v_upload.object_path);
  end if;
  if v_upload.state <> 'pending' or v_upload.created_at <= now() - interval '24 hours' or
     v_booking.current_status <> 'In Progress' then
    return jsonb_build_object('attached',false,'reason','expired_or_closed');
  end if;
  if not exists(select 1 from storage.objects where bucket_id = 'cleaning-evidence'
    and name = v_upload.object_path and metadata->>'size' = v_upload.byte_size::text
    and metadata->>'mimetype' = case when right(v_upload.object_path,4) = '.jpg'
      then 'image/jpeg' else 'image/png' end) then
    return jsonb_build_object('attached',false,'reason','upload_not_confirmed');
  end if;
  -- Compare-and-set prevents two devices silently replacing each other's work.
  if v_previous is distinct from v_upload.expected_previous_path then
    update public.evidence_upload set state = 'retired', updated_at = now() where upload_id = p_upload_id;
    return jsonb_build_object('attached',false,'reason','photo_changed');
  end if;
  insert into public.booking_evidence(booking_id) values(p_booking_id) on conflict do nothing;
  if v_upload.kind = 'before' then
    update public.booking_evidence set before_path = v_upload.object_path, updated_at = now()
      where booking_id = p_booking_id;
  else
    update public.booking_evidence set after_path = v_upload.object_path, updated_at = now()
      where booking_id = p_booking_id;
  end if;
  if v_previous is not null then
    -- Only known, previously referenced legacy objects are adopted. Unknown
    -- historical files are never guessed to be safe to delete.
    insert into public.evidence_upload(upload_id,booking_id,provider_id,kind,object_path,state)
      values(gen_random_uuid(),p_booking_id,auth.uid(),v_upload.kind,v_previous,'retired')
      on conflict(object_path) do update set state = 'retired', updated_at = now();
  end if;
  update public.evidence_upload set state = 'attached', updated_at = now() where upload_id = p_upload_id;
  return jsonb_build_object('attached',true,'path',v_upload.object_path);
end $$;

create function public.save_evidence_remarks(p_booking_id uuid, p_remarks text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_booking public.booking%rowtype;
begin
  v_booking := public.lock_evidence_booking(p_booking_id);
  if v_booking.current_status <> 'In Progress' or p_remarks is null or char_length(btrim(p_remarks)) > 1000 then
    raise exception 'Remarks cannot be changed' using errcode = '23514';
  end if;
  insert into public.booking_evidence(booking_id,completion_remarks) values(p_booking_id,btrim(p_remarks))
  on conflict(booking_id) do update set completion_remarks = excluded.completion_remarks, updated_at = now();
end $$;

-- A bounded, booking-scoped outbox. A crashed/failed deletion can be retried.
-- Pending uploads have a 24-hour grace period. Cleanup never uses device time.
create function public.claim_evidence_cleanup(p_booking_id uuid)
returns table(object_path text) language plpgsql security definer set search_path = '' as $$
begin
  perform public.lock_evidence_booking(p_booking_id);
  return query
    with candidates as (
      select u.upload_id from public.evidence_upload u
      where u.booking_id = p_booking_id and u.provider_id = auth.uid()
        and (u.state in ('retired','deleting') or
          (u.state = 'pending' and u.created_at <= now() - interval '24 hours'))
        and not exists(select 1 from public.booking_evidence e
          where e.before_path = u.object_path or e.after_path = u.object_path)
      order by u.created_at,u.upload_id limit 20 for update
    )
    update public.evidence_upload u set state = 'deleting', updated_at = now()
    from candidates c where u.upload_id = c.upload_id returning u.object_path;
end $$;

create function public.finish_evidence_cleanup(p_booking_id uuid, p_path text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  perform public.lock_evidence_booking(p_booking_id);
  if exists(select 1 from storage.objects where bucket_id = 'cleaning-evidence' and name = p_path) then
    return false;
  end if;
  update public.evidence_upload set state = 'deleted', updated_at = now()
    where booking_id = p_booking_id and provider_id = auth.uid()
      and object_path = p_path and state = 'deleting';
  if found then return true; end if;
  return exists(select 1 from public.evidence_upload where booking_id=p_booking_id
    and provider_id=auth.uid() and object_path=p_path and state='deleted');
end $$;

-- All client evidence writes now use locking RPCs, including remarks.
revoke insert,update,delete on public.booking_evidence from anon, authenticated;
drop policy evidence_provider_insert on public.booking_evidence;
drop policy evidence_provider_update on public.booking_evidence;

create function public.can_upload_evidence_object(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.evidence_upload u join public.booking b using(booking_id)
    where u.object_path = p_path and u.provider_id = auth.uid() and u.state = 'pending'
      and u.created_at > now() - interval '24 hours' and b.current_status = 'In Progress');
$$;
create function public.can_delete_evidence_object(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.evidence_upload u
    where u.object_path = p_path and u.provider_id = auth.uid() and u.state = 'deleting')
    and not exists(select 1 from public.booking_evidence e where e.before_path = p_path or e.after_path = p_path);
$$;
create function public.can_read_evidence_object(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.booking_evidence e join public.booking b using(booking_id)
    where (e.before_path = p_path or e.after_path = p_path)
      and auth.uid() in (b.owner_id,b.provider_id))
    or exists(select 1 from public.evidence_upload u where u.object_path = p_path and u.provider_id = auth.uid());
$$;
drop policy evidence_object_provider_insert on storage.objects;
drop policy evidence_object_participant_read on storage.objects;
create policy evidence_registered_upload on storage.objects for insert to authenticated
  with check(bucket_id = 'cleaning-evidence' and public.can_upload_evidence_object(name));
create policy evidence_private_read on storage.objects for select to authenticated
  using(bucket_id = 'cleaning-evidence' and public.can_read_evidence_object(name));
create policy evidence_obsolete_delete on storage.objects for delete to authenticated
  using(bucket_id = 'cleaning-evidence' and public.can_delete_evidence_object(name));
grant delete on storage.objects to authenticated;

revoke all on function public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text) from public,anon;
revoke all on function public.attach_evidence_upload(uuid,uuid) from public,anon;
revoke all on function public.save_evidence_remarks(uuid,text) from public,anon;
revoke all on function public.claim_evidence_cleanup(uuid) from public,anon;
revoke all on function public.finish_evidence_cleanup(uuid,text) from public,anon;
revoke all on function public.can_upload_evidence_object(text) from public,anon;
revoke all on function public.can_delete_evidence_object(text) from public,anon;
revoke all on function public.can_read_evidence_object(text) from public,anon;
grant execute on function public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text),
  public.attach_evidence_upload(uuid,uuid), public.save_evidence_remarks(uuid,text),
  public.claim_evidence_cleanup(uuid), public.finish_evidence_cleanup(uuid,text),
  public.can_upload_evidence_object(text), public.can_delete_evidence_object(text),
  public.can_read_evidence_object(text) to authenticated;

-- Maintenance worker: the service credential stays outside Flutter. This
-- handles abandoned bookings without depending on a Provider reopening them.
create function public.list_evidence_cleanup_batch()
returns table(booking_id uuid,object_path text)
language sql stable security definer set search_path = '' as $$
  select u.booking_id,u.object_path from public.evidence_upload u
  where (u.state in ('retired','deleting') or
    (u.state='pending' and u.created_at <= now()-interval '24 hours'))
    and not exists(select 1 from public.booking_evidence e
      where e.before_path=u.object_path or e.after_path=u.object_path)
  order by u.created_at,u.upload_id limit 20;
$$;

create function public.claim_evidence_cleanup_batch()
returns table(booking_id uuid,object_path text)
language plpgsql security definer set search_path = '' as $$
declare v_booking record; v_count integer := 0; v_added integer;
begin
  for v_booking in
    select distinct b.provider_id,b.booking_id from public.booking b
    join public.evidence_upload u on u.booking_id=b.booking_id
    where u.state in ('retired','deleting') or
      (u.state='pending' and u.created_at <= now()-interval '24 hours')
    order by b.provider_id,b.booking_id limit 20
  loop
    -- Match the booking lifecycle's lock order; never stall an active write.
    perform 1 from public.provider_profile p where p.provider_id=v_booking.provider_id for update skip locked;
    if not found then continue; end if;
    perform 1 from public.booking b where b.booking_id=v_booking.booking_id for update skip locked;
    if not found then continue; end if;
    return query with candidates as (
      select u.upload_id from public.evidence_upload u
      where u.booking_id=v_booking.booking_id and
        (u.state in ('retired','deleting') or (u.state='pending' and u.created_at<=now()-interval '24 hours'))
        and not exists(select 1 from public.booking_evidence e
          where e.before_path=u.object_path or e.after_path=u.object_path)
      order by u.created_at,u.upload_id limit (20-v_count) for update
    ) update public.evidence_upload u set state='deleting',updated_at=now()
      from candidates c where u.upload_id=c.upload_id returning u.booking_id,u.object_path;
    get diagnostics v_added = row_count;
    v_count := v_count + v_added;
    exit when v_count >= 20;
  end loop;
end $$;

create function public.finish_evidence_cleanup_batch(p_booking_id uuid,p_path text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if exists(select 1 from storage.objects where bucket_id='cleaning-evidence' and name=p_path)
    or exists(select 1 from public.booking_evidence where before_path=p_path or after_path=p_path) then
    return false;
  end if;
  update public.evidence_upload set state='deleted',updated_at=now()
    where booking_id=p_booking_id and object_path=p_path and state='deleting';
  if found then return true; end if;
  return exists(select 1 from public.evidence_upload where booking_id=p_booking_id
    and object_path=p_path and state='deleted');
end $$;
revoke all on function public.list_evidence_cleanup_batch() from public,anon,authenticated;
revoke all on function public.claim_evidence_cleanup_batch() from public,anon,authenticated;
revoke all on function public.finish_evidence_cleanup_batch(uuid,text) from public,anon,authenticated;
grant execute on function public.list_evidence_cleanup_batch(),
  public.claim_evidence_cleanup_batch(), public.finish_evidence_cleanup_batch(uuid,text),
  public.get_app_environment() to service_role;
