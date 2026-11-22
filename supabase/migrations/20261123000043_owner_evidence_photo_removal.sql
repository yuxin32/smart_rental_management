-- Remove one current attachment before completion, without deleting Storage
-- metadata directly. The existing tombstone/Storage API cleanup removes bytes.
create function public.remove_evidence_photo(
  p_booking_id uuid, p_kind text, p_expected_path text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  b public.booking%rowtype;
  u public.evidence_upload%rowtype;
  current_path text;
begin
  b := public.lock_evidence_booking(p_booking_id);
  if p_kind is null or p_kind not in ('before', 'after') or
     p_expected_path is null or p_expected_path = '' or
     left(p_expected_path, length(p_booking_id::text) + 1) <> p_booking_id::text || '/' then
    raise exception 'Invalid photo removal request' using errcode = '22023';
  end if;
  if b.current_status <> 'In Progress' then
    return jsonb_build_object('removed', false, 'reason', 'booking_closed');
  end if;
  select case when p_kind = 'before' then before_path else after_path end
    into current_path from public.booking_evidence where booking_id = p_booking_id for update;
  select * into u from public.evidence_upload where object_path = p_expected_path for update;
  if found and (u.booking_id <> p_booking_id or u.provider_id <> auth.uid() or u.kind <> p_kind) then
    raise exception 'Assigned photo required' using errcode = '42501';
  end if;
  -- Replays cannot detach a newer replacement, even if an earlier removal won.
  if current_path is null and u.upload_id is not null and u.state in ('retired', 'deleting', 'deleted') then
    return jsonb_build_object('removed', true, 'path', p_expected_path);
  end if;
  if current_path is distinct from p_expected_path then
    return jsonb_build_object('removed', false, 'reason', 'photo_changed');
  end if;
  if p_kind = 'before' then
    update public.booking_evidence set before_path = null, updated_at = now() where booking_id = p_booking_id;
  else
    update public.booking_evidence set after_path = null, updated_at = now() where booking_id = p_booking_id;
  end if;
  if u.upload_id is null then
    -- Adopt only the exact legacy attachment just detached from this booking.
    insert into public.evidence_upload(upload_id, booking_id, provider_id, kind, object_path, state)
      values(gen_random_uuid(), p_booking_id, auth.uid(), p_kind, p_expected_path, 'retired');
  else
    update public.evidence_upload set state = 'retired', updated_at = now() where upload_id = u.upload_id;
  end if;
  return jsonb_build_object('removed', true, 'path', p_expected_path);
end $$;

revoke all on function public.remove_evidence_photo(uuid,text,text) from public, anon, authenticated;
grant execute on function public.remove_evidence_photo(uuid,text,text) to authenticated;
