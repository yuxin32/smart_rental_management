-- Server-side sliding-window limits. Deploy manually to verified staging first.
-- Existing message/upload rows are the event ledger: no copy of private text,
-- photos, or extra per-request activity log is created for rate limiting.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated, service_role;

create table app_private.activity_limit (
  action text not null check (action in ('message', 'evidence')),
  window_seconds integer not null check (window_seconds between 1 and 86400),
  max_events integer not null check (max_events between 1 and 1000),
  primary key(action, window_seconds)
);
alter table app_private.activity_limit enable row level security;
revoke all on app_private.activity_limit from public, anon, authenticated, service_role;
insert into app_private.activity_limit(action, window_seconds, max_events) values
  ('message', 10, 8), ('message', 60, 40), ('message', 3600, 300),
  ('evidence', 60, 6), ('evidence', 3600, 30), ('evidence', 86400, 100);

create index booking_message_sender_time on public.booking_message(sender_user_id, created_at desc);
create index evidence_upload_provider_time on public.evidence_upload(provider_id, created_at desc);

-- Called only while the entry point holds its actor/action advisory lock.
-- A bounded index scan reads at most max_events rows per window, not all history.
create function app_private.check_activity_budget(p_actor uuid, p_action text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_rule record; v_oldest timestamptz; v_now timestamptz := clock_timestamp();
  v_retry integer := 0; v_policy_found boolean := false;
begin
  if p_actor is null or p_actor is distinct from auth.uid() or p_action not in ('message','evidence') then
    raise exception 'Activity actor required' using errcode = '42501';
  end if;
  for v_rule in select * from app_private.activity_limit where action=p_action order by window_seconds loop
    v_policy_found := true;
    v_oldest := null;
    if p_action = 'message' then
      select created_at into v_oldest from public.booking_message
        where sender_user_id=p_actor and created_at > v_now - make_interval(secs=>v_rule.window_seconds)
        order by created_at desc offset (v_rule.max_events-1) limit 1;
    else
      select created_at into v_oldest from public.evidence_upload
        where provider_id=p_actor and created_at > v_now - make_interval(secs=>v_rule.window_seconds)
        order by created_at desc offset (v_rule.max_events-1) limit 1;
    end if;
    if v_oldest is not null then
      v_retry := greatest(v_retry, ceil(extract(epoch from
        (v_oldest + make_interval(secs=>v_rule.window_seconds) - v_now)))::integer, 1);
    end if;
  end loop;
  if not v_policy_found then raise exception 'ABUSE_POLICY_UNAVAILABLE' using errcode='55000'; end if;
  if v_retry > 0 then
    raise sqlstate 'PT429' using
      message = case when p_action='message' then 'CHAT_RATE_LIMITED' else 'EVIDENCE_RATE_LIMITED' end,
      detail = 'retry_after_seconds=' || least(v_retry,86400)::text;
  end if;
end $$;
revoke all on function app_private.check_activity_budget(uuid,text) from public, anon, authenticated, service_role;

create or replace function public.send_booking_message(
  p_booking_id uuid, p_client_message_id uuid, p_body text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid(); v_booking public.booking%rowtype;
  v_message public.booking_message%rowtype; v_body text := btrim(coalesce(p_body,''));
  v_reused boolean := false;
begin
  if v_actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_booking_id is null or p_client_message_id is null or length(v_body) not between 1 and 2000 then
    raise exception 'Invalid message' using errcode='22023';
  end if;
  -- Fresh snapshots after waiting are part of the concurrency contract.
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'ABUSE_REQUIRES_READ_COMMITTED' using errcode='25000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('rental-abuse:message:' || v_actor::text,0));
  select * into v_booking from public.booking where booking_id=p_booking_id for share;
  if not found or v_actor not in (v_booking.owner_id,v_booking.provider_id) then
    raise exception 'Booking participant required' using errcode='42501';
  end if;
  select * into v_message from public.booking_message
    where sender_user_id=v_actor and client_message_id=p_client_message_id;
  if found then
    v_reused := true;
  else
    if v_booking.current_status not in ('Accepted','In Progress') then
      raise exception 'Messages are closed for this booking' using errcode='23514';
    end if;
    perform app_private.check_activity_budget(v_actor,'message');
    insert into public.booking_message(booking_id,sender_user_id,client_message_id,body,created_at)
      values(p_booking_id,v_actor,p_client_message_id,v_body,clock_timestamp())
      on conflict(sender_user_id,client_message_id) do nothing returning * into v_message;
    if not found then
      select * into v_message from public.booking_message
        where sender_user_id=v_actor and client_message_id=p_client_message_id;
      v_reused := true;
    end if;
  end if;
  if v_message.booking_id is distinct from p_booking_id or v_message.body is distinct from v_body then
    raise exception 'Message retry token reused with different content' using errcode='23505';
  end if;
  return jsonb_build_object('message_id',v_message.message_id,'created_at',v_message.created_at,'reused',v_reused);
end $$;
revoke all on function public.send_booking_message(uuid,uuid,text) from public,anon;
grant execute on function public.send_booking_message(uuid,uuid,text) to authenticated;

create or replace function public.begin_evidence_upload(
  p_booking_id uuid, p_upload_id uuid, p_kind text, p_extension text,
  p_byte_size integer, p_sha256 text, p_expected_previous_path text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_booking public.booking%rowtype; v_upload public.evidence_upload%rowtype; v_previous text;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'ABUSE_REQUIRES_READ_COMMITTED' using errcode='25000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('rental-abuse:evidence:' || auth.uid()::text,0));
  v_booking := public.lock_evidence_booking(p_booking_id);
  if p_upload_id is null or p_kind is null or p_kind not in ('before','after') or
     p_extension is null or p_extension not in ('jpg','png') or
     p_byte_size is null or p_byte_size not between 1 and 5242880 or
     p_sha256 is null or p_sha256 !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid image manifest' using errcode='23514';
  end if;
  select * into v_upload from public.evidence_upload where upload_id=p_upload_id for update;
  if found then
    if v_upload.provider_id <> auth.uid() or v_upload.booking_id <> p_booking_id or
       v_upload.kind <> p_kind or v_upload.byte_size is distinct from p_byte_size or
       v_upload.sha256 is distinct from p_sha256 or
       v_upload.expected_previous_path is distinct from p_expected_previous_path or
       v_upload.object_path <> p_booking_id::text || '/' || p_kind || '_' || p_upload_id::text || '.' || p_extension then
      raise exception 'Upload token cannot be reused for different content' using errcode='23514';
    end if;
  else
    if v_booking.current_status <> 'In Progress' then return jsonb_build_object('state','closed'); end if;
    select case when p_kind='before' then before_path else after_path end into v_previous
      from public.booking_evidence where booking_id=p_booking_id;
    if v_previous is distinct from p_expected_previous_path then return jsonb_build_object('state','photo_changed'); end if;
    perform app_private.check_activity_budget(auth.uid(),'evidence');
    insert into public.evidence_upload(upload_id,booking_id,provider_id,kind,object_path,
      expected_previous_path,byte_size,sha256,created_at)
    values(p_upload_id,p_booking_id,auth.uid(),p_kind,
      p_booking_id::text || '/' || p_kind || '_' || p_upload_id::text || '.' || p_extension,
      v_previous,p_byte_size,p_sha256,clock_timestamp()) returning * into v_upload;
  end if;
  if v_upload.state='pending' and
     (v_booking.current_status <> 'In Progress' or v_upload.created_at <= now()-interval '24 hours') then
    return jsonb_build_object('state','expired_or_closed');
  end if;
  return jsonb_build_object('state',v_upload.state,'path',v_upload.object_path,
    'uploaded',exists(select 1 from storage.objects where bucket_id='cleaning-evidence' and name=v_upload.object_path));
end $$;
revoke all on function public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text) from public,anon;
grant execute on function public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text) to authenticated;
