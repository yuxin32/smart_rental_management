-- Extend the six-state lifecycle without changing previously applied migrations.
-- Pending requests may be cancelled by the owner. Accepted bookings may be
-- cancelled by either participant before work starts; a reason is mandatory.
-- The provider-then-booking lock order matches accept_pending_booking so a
-- cancellation racing acceptance or start is resolved against the locked state.
create or replace function public.transition_booking(
  p_booking_id uuid,
  p_new_status public.booking_status_enum,
  p_reason text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_provider_id uuid;
  v_booking public.booking%rowtype;
  v_evidence public.booking_evidence%rowtype;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select b.provider_id into v_provider_id from public.booking b
  where b.booking_id = p_booking_id;
  if v_provider_id is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;

  perform 1 from public.provider_profile p
    where p.provider_id = v_provider_id for update;
  select * into v_booking from public.booking b
    where b.booking_id = p_booking_id for update;
  if not found then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;

  if not (
    (v_booking.current_status = 'Pending' and
      p_new_status = 'Declined' and v_actor = v_booking.provider_id) or
    (v_booking.current_status = 'Pending' and
      p_new_status = 'Cancelled' and v_actor = v_booking.owner_id) or
    (v_booking.current_status = 'Accepted' and
      p_new_status = 'Cancelled' and
      v_actor in (v_booking.owner_id, v_booking.provider_id)) or
    (v_booking.current_status = 'Accepted' and
      p_new_status = 'In Progress' and v_actor = v_booking.provider_id) or
    (v_booking.current_status = 'In Progress' and
      p_new_status = 'Completed' and v_actor = v_booking.provider_id)
  ) then
    raise exception 'Transition or actor is not permitted'
      using errcode = '42501';
  end if;

  if p_new_status = 'Cancelled' and
     (v_reason is null or char_length(v_reason) > 300) then
    raise exception 'Cancellation reason is required (maximum 300 characters)'
      using errcode = '23514';
  end if;

  if p_new_status = 'Completed' then
    select * into v_evidence from public.booking_evidence e
      where e.booking_id = p_booking_id for update;
    if not found or v_evidence.before_path is null or
       v_evidence.after_path is null or
       length(btrim(v_evidence.completion_remarks)) = 0 or
       not exists (
         select 1 from storage.objects o
         where o.bucket_id = 'cleaning-evidence' and
               o.name = v_evidence.before_path
       ) or not exists (
         select 1 from storage.objects o
         where o.bucket_id = 'cleaning-evidence' and
               o.name = v_evidence.after_path
       ) then
      raise exception 'Before/after images and remarks are required'
        using errcode = '23514';
    end if;
  end if;

  update public.booking set current_status = p_new_status
    where booking_id = p_booking_id;
  insert into public.booking_status_history
    (booking_id, changed_by_user_id, previous_status, new_status,
     change_reason)
  values (p_booking_id, v_actor, v_booking.current_status, p_new_status,
          v_reason);
  return jsonb_build_object('status', p_new_status::text);
end;
$$;
revoke execute on function public.transition_booking(
  uuid, public.booking_status_enum, text) from public, anon;
grant execute on function public.transition_booking(
  uuid, public.booking_status_enum, text) to authenticated;
