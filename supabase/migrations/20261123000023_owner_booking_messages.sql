-- Booking-linked Owner/Provider communication. Apply after migration 009
-- in a backed-up staging project and verify RLS with two real identities.
-- Completed conversations remain readable but cannot receive new messages.

create table public.booking_message (
  message_id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.booking(booking_id)
    on delete cascade,
  sender_user_id uuid not null references public.user_account(user_id),
  client_message_id uuid not null,
  body text not null,
  created_at timestamptz not null default now(),
  constraint booking_message_body_valid check (
    body = btrim(body) and length(body) between 1 and 2000
  ),
  constraint booking_message_retry_unique
    unique (sender_user_id, client_message_id)
);

create index booking_message_thread_idx
  on public.booking_message(booking_id, created_at, message_id);

alter table public.booking_message enable row level security;

-- No client-side INSERT/UPDATE/DELETE: the RPC below controls actor,
-- booking status, body validation and idempotent network retries.
revoke all on public.booking_message from public, anon, authenticated;
grant select on public.booking_message to authenticated;

create policy booking_message_participant_read
  on public.booking_message for select to authenticated
  using (exists (
    select 1 from public.booking b
    where b.booking_id = booking_message.booking_id and
      (b.owner_id = (select auth.uid()) or
       b.provider_id = (select auth.uid()))
  ));

create function public.send_booking_message(
  p_booking_id uuid,
  p_client_message_id uuid,
  p_body text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_booking public.booking%rowtype;
  v_message public.booking_message%rowtype;
  v_body text := btrim(coalesce(p_body, ''));
  v_reused boolean := false;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_booking_id is null or p_client_message_id is null or
     length(v_body) not between 1 and 2000 then
    raise exception 'Invalid message' using errcode = '22023';
  end if;

  -- A share lock serialises this check with status transitions, so a
  -- cancellation/completion cannot commit between checking and inserting.
  select * into v_booking from public.booking b
    where b.booking_id = p_booking_id for share;
  if not found or
     v_actor not in (v_booking.owner_id, v_booking.provider_id) then
    raise exception 'Booking participant required' using errcode = '42501';
  end if;

  -- A retry of a previously accepted send is safe even if the booking was
  -- completed while the network response was lost.
  select * into v_message from public.booking_message m
    where m.sender_user_id = v_actor and
          m.client_message_id = p_client_message_id;
  if found then
    v_reused := true;
  else
    if v_booking.current_status not in ('Accepted', 'In Progress') then
      raise exception 'Messages are closed for this booking'
        using errcode = '23514';
    end if;
    insert into public.booking_message
      (booking_id, sender_user_id, client_message_id, body)
    values (p_booking_id, v_actor, p_client_message_id, v_body)
    on conflict (sender_user_id, client_message_id) do nothing
    returning * into v_message;
    if not found then
      select * into v_message from public.booking_message m
        where m.sender_user_id = v_actor and
              m.client_message_id = p_client_message_id;
      v_reused := true;
    end if;
  end if;
  if v_message.booking_id is distinct from p_booking_id or
     v_message.body is distinct from v_body then
    raise exception 'Message retry token reused with different content'
      using errcode = '23505';
  end if;
  return jsonb_build_object(
    'message_id', v_message.message_id,
    'created_at', v_message.created_at,
    'reused', v_reused
  );
end;
$$;

revoke execute on function public.send_booking_message(uuid, uuid, text)
  from public, anon;
grant execute on function public.send_booking_message(uuid, uuid, text)
  to authenticated;

-- New tables are not automatically in the Supabase Realtime publication.
do $$
begin
  if exists (select 1 from pg_publication
             where pubname = 'supabase_realtime') and
     not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and
             schemaname = 'public' and tablename = 'booking_message'
     ) then
    alter publication supabase_realtime add table public.booking_message;
  end if;
end;
$$;
