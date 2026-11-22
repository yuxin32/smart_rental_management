-- Server-only pixel validation. Untrusted bytes never enter the evidence
-- bucket. Client manifests are not attestations. Apply with the matching
-- evidence-validate function; old clients fail closed, with no upload fallback.
create table app_private.evidence_validation (
  upload_id uuid primary key references public.evidence_upload(upload_id) on delete cascade,
  state text not null check (state in ('processing','verified','rejected','retry')),
  token uuid not null,
  lease_until timestamptz not null,
  attempts integer not null check (attempts between 1 and 3),
  canonical_sha256 text check (canonical_sha256 ~ '^[a-f0-9]{64}$'),
  canonical_size integer check (canonical_size between 1 and 5242880),
  width integer check (width between 1 and 1600),
  height integer check (height between 1 and 1600),
  mime text check (mime in ('image/jpeg','image/png')),
  validator_version text,
  verified_at timestamptz,
  check (state <> 'verified' or (canonical_sha256 is not null and canonical_size is not null
    and width is not null and height is not null and mime is not null
    and validator_version='pixels-v1' and verified_at is not null))
);
alter table app_private.evidence_validation enable row level security;
revoke all on app_private.evidence_validation from public,anon,authenticated,service_role;

-- Called only after the endpoint has authenticated the real bearer token.
-- IDs/manifest/path always come from registered rows, not a request path/URL.
create function public.claim_evidence_validation(p_booking_id uuid,p_upload_id uuid,p_provider_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u public.evidence_upload%rowtype; b public.booking%rowtype;
  v app_private.evidence_validation%rowtype; t uuid := gen_random_uuid();
begin
  select * into b from public.booking where booking_id=p_booking_id;
  if b.provider_id is distinct from p_provider_id or p_provider_id is null then
    raise exception 'Assigned provider required' using errcode='42501';
  end if;
  perform 1 from public.provider_profile where provider_id=p_provider_id for update;
  select * into b from public.booking where booking_id=p_booking_id for update;
  if b.provider_id is distinct from p_provider_id then
    raise exception 'Assigned provider required' using errcode='42501';
  end if;
  select * into u from public.evidence_upload where upload_id=p_upload_id
    and booking_id=p_booking_id and provider_id=p_provider_id for update;
  if not found then raise exception 'Upload not found' using errcode='42501'; end if;
  select * into v from app_private.evidence_validation where upload_id=p_upload_id for update;
  if v.state='verified' and u.state in ('pending','attached') then
    return jsonb_build_object('state','verified','path',u.object_path);
  end if;
  -- Ten-minute margin before the existing 24-hour cleanup grace. An Edge
  -- request is bounded by 150s on Free / 400s paid; no late worker is started
  -- near the deletion boundary. Hosted acceptance must check these limits.
  if u.state <> 'pending' or b.current_status <> 'In Progress' or
    u.created_at <= clock_timestamp()-interval '23 hours 50 minutes' then
    return jsonb_build_object('state','expired_or_closed');
  end if;
  if v.state='rejected' then return jsonb_build_object('state','photo_rejected'); end if;
  if v.state='processing' and v.lease_until > clock_timestamp() then
    return jsonb_build_object('state','busy');
  end if;
  if v.attempts >= 3 then return jsonb_build_object('state','attempts_exhausted'); end if;
  insert into app_private.evidence_validation(upload_id,state,token,lease_until,attempts)
    values(p_upload_id,'processing',t,clock_timestamp()+interval '8 minutes',1)
  on conflict(upload_id) do update set state='processing',token=t,
    lease_until=clock_timestamp()+interval '8 minutes',attempts=evidence_validation.attempts+1;
  return jsonb_build_object('state','processing','token',t,'path',u.object_path,
    'source_size',u.byte_size,'source_sha256',u.sha256,
    'extension',case when right(u.object_path,4)='.jpg' then 'jpg' else 'png' end);
end $$;

create function public.finish_evidence_validation(p_upload_id uuid,p_token uuid,
  p_source_sha256 text,p_canonical_sha256 text,p_size integer,p_width integer,p_height integer,p_mime text)
returns boolean language plpgsql security definer set search_path='' as $$
declare u public.evidence_upload%rowtype; b public.booking%rowtype;
  v app_private.evidence_validation%rowtype;
begin
  select * into u from public.evidence_upload where upload_id=p_upload_id;
  if not found then return false; end if;
  perform 1 from public.provider_profile where provider_id=u.provider_id for update;
  select * into b from public.booking where booking_id=u.booking_id for update;
  select * into u from public.evidence_upload where upload_id=p_upload_id for update;
  select * into v from app_private.evidence_validation where upload_id=p_upload_id for update;
  if v.upload_id is null or p_token is null or v.token is distinct from p_token or v.state <> 'processing' or
    v.lease_until <= clock_timestamp() or u.state <> 'pending' or b.current_status <> 'In Progress' or
    b.provider_id is distinct from u.provider_id or
    u.created_at <= clock_timestamp()-interval '24 hours' or
    u.sha256 is distinct from p_source_sha256 then return false; end if;
  if p_canonical_sha256 is null or p_canonical_sha256 !~ '^[a-f0-9]{64}$' or
    p_size is null or p_size not between 1 and 5242880 or p_width is null or
    p_width not between 1 and 1600 or p_height is null or p_height not between 1 and 1600 or
    p_mime is distinct from (case when right(u.object_path,4)='.jpg' then 'image/jpeg' else 'image/png' end) then
    raise exception 'Invalid canonical manifest' using errcode='23514';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='cleaning-evidence' and name=u.object_path
    and metadata->>'size'=p_size::text and metadata->>'mimetype'=p_mime) then return false; end if;
  update app_private.evidence_validation set state='verified',canonical_sha256=p_canonical_sha256,
    canonical_size=p_size,width=p_width,height=p_height,mime=p_mime,
    validator_version='pixels-v1',verified_at=clock_timestamp() where upload_id=p_upload_id;
  return true;
end $$;

create function public.fail_evidence_validation(p_upload_id uuid,p_token uuid,p_rejected boolean)
returns void language sql security definer set search_path='' as $$
  update app_private.evidence_validation set state=case when p_rejected then 'rejected' else 'retry' end
    where upload_id=p_upload_id and token=p_token and state='processing';
$$;
revoke all on function public.claim_evidence_validation(uuid,uuid,uuid),
  public.finish_evidence_validation(uuid,uuid,text,text,integer,integer,integer,text),
  public.fail_evidence_validation(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.claim_evidence_validation(uuid,uuid,uuid),
  public.finish_evidence_validation(uuid,uuid,text,text,integer,integer,integer,text),
  public.fail_evidence_validation(uuid,uuid,boolean) to service_role;

-- Preserve v17 quota/idempotency logic; existence alone must no longer skip
-- validation. The old implementation is inaccessible as a public RPC.
alter function public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text) set schema app_private;
alter function app_private.begin_evidence_upload(uuid,uuid,text,text,integer,text,text) rename to begin_evidence_upload_v17;
revoke all on function app_private.begin_evidence_upload_v17(uuid,uuid,text,text,integer,text,text)
  from public,anon,authenticated,service_role;
create function public.begin_evidence_upload(p_booking_id uuid,p_upload_id uuid,p_kind text,
  p_extension text,p_byte_size integer,p_sha256 text,p_expected_previous_path text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  result := app_private.begin_evidence_upload_v17(p_booking_id,p_upload_id,p_kind,
    p_extension,p_byte_size,p_sha256,p_expected_previous_path);
  if result->>'state'='pending' then
    if exists(select 1 from app_private.evidence_validation where upload_id=p_upload_id and state='rejected') then
      return jsonb_build_object('state','photo_rejected');
    end if;
    result := result || jsonb_build_object('uploaded',exists(select 1 from app_private.evidence_validation
      where upload_id=p_upload_id and state='verified'));
  end if;
  return result;
end $$;
revoke all on function public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text) from public,anon;
grant execute on function public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text) to authenticated;

-- New attachments require a server attestation and the canonical object.
create or replace function public.attach_evidence_upload(p_booking_id uuid,p_upload_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.booking%rowtype; u public.evidence_upload%rowtype;
  v app_private.evidence_validation%rowtype; previous text;
begin
  b := public.lock_evidence_booking(p_booking_id);
  select * into u from public.evidence_upload where upload_id=p_upload_id
    and booking_id=p_booking_id and provider_id=auth.uid() for update;
  if not found then raise exception 'Upload not found' using errcode='42501'; end if;
  select case when u.kind='before' then before_path else after_path end into previous
    from public.booking_evidence where booking_id=p_booking_id;
  select * into v from app_private.evidence_validation where upload_id=p_upload_id;
  if v.state is distinct from 'verified' then
    return jsonb_build_object('attached',false,'reason',case when v.state='rejected'
      then 'photo_rejected' else 'upload_not_confirmed' end);
  end if;
  if not exists(select 1 from storage.objects where bucket_id='cleaning-evidence'
    and name=u.object_path and metadata->>'size'=v.canonical_size::text
    and metadata->>'mimetype'=v.mime) then
    return jsonb_build_object('attached',false,'reason','upload_not_confirmed');
  end if;
  if u.state='attached' and previous=u.object_path then
    return jsonb_build_object('attached',true,'path',u.object_path);
  end if;
  if u.state <> 'pending' or u.created_at <= clock_timestamp()-interval '24 hours' or
    b.current_status <> 'In Progress' then
    return jsonb_build_object('attached',false,'reason','expired_or_closed');
  end if;
  if previous is distinct from u.expected_previous_path then
    update public.evidence_upload set state='retired',updated_at=now() where upload_id=p_upload_id;
    return jsonb_build_object('attached',false,'reason','photo_changed');
  end if;
  insert into public.booking_evidence(booking_id) values(p_booking_id) on conflict do nothing;
  if u.kind='before' then
    update public.booking_evidence set before_path=u.object_path,updated_at=now() where booking_id=p_booking_id;
  else
    update public.booking_evidence set after_path=u.object_path,updated_at=now() where booking_id=p_booking_id;
  end if;
  if previous is not null then
    insert into public.evidence_upload(upload_id,booking_id,provider_id,kind,object_path,state)
      values(gen_random_uuid(),p_booking_id,auth.uid(),u.kind,previous,'retired')
      on conflict(object_path) do update set state='retired',updated_at=now();
  end if;
  update public.evidence_upload set state='attached',updated_at=now() where upload_id=p_upload_id;
  return jsonb_build_object('attached',true,'path',u.object_path);
end $$;

-- No authenticated INSERT policy: only the trusted server can publish bytes.
drop policy evidence_registered_upload on storage.objects;
create or replace function public.can_upload_evidence_object(p_path text)
returns boolean language sql stable security definer set search_path='' as $$ select false; $$;
create or replace function public.can_read_evidence_object(p_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.booking_evidence e join public.booking b using(booking_id)
    join public.evidence_upload u on u.booking_id=b.booking_id and u.object_path=p_path and u.state='attached'
    join app_private.evidence_validation v on v.upload_id=u.upload_id and v.state='verified'
    where (e.before_path=p_path or e.after_path=p_path) and auth.uid() in (b.owner_id,b.provider_id))
    -- Storage DELETE also requires SELECT visibility. Only tombstoned unused
    -- objects are exposed to their uploading provider for cleanup, not owners.
    or exists(select 1 from public.evidence_upload u where u.object_path=p_path
      and u.provider_id=auth.uid() and u.state='deleting');
$$;
-- Old unverified rows/objects are retained, not falsely blessed or deleted.
-- A new completion requires both current attached paths to be verified, even
-- if a privileged integration bypasses the normal transition RPC.
create function app_private.require_verified_completion()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if (select count(distinct u.kind) from public.booking_evidence e
    join public.evidence_upload u on u.booking_id=e.booking_id and u.state='attached' and u.provider_id=new.provider_id
      and ((u.kind='before' and u.object_path=e.before_path) or (u.kind='after' and u.object_path=e.after_path))
    join app_private.evidence_validation v on v.upload_id=u.upload_id and v.state='verified'
    join storage.objects o on o.bucket_id='cleaning-evidence' and o.name=u.object_path
      and o.metadata->>'size'=v.canonical_size::text and o.metadata->>'mimetype'=v.mime
    where e.booking_id=new.booking_id) <> 2 then
    raise exception 'Verified before/after photographs are required' using errcode='23514';
  end if;
  return new;
end $$;
revoke all on function app_private.require_verified_completion() from public,anon,authenticated,service_role;
create trigger require_verified_completion before update of current_status on public.booking
  for each row when (new.current_status='Completed' and old.current_status is distinct from new.current_status)
  execute function app_private.require_verified_completion();
