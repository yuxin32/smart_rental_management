-- One Owner review per Completed cleaning booking. Apply to staging first.
-- Direct client writes are forbidden; the function validates ownership and
-- recomputes the Provider's average in the same database transaction.
create table public.booking_review (
  booking_id uuid primary key references public.booking(booking_id)
    on delete cascade,
  owner_id uuid not null references public.user_account(user_id),
  provider_id uuid not null references public.provider_profile(provider_id),
  rating smallint not null check (rating between 1 and 5),
  comment text check (comment is null or
    (comment = btrim(comment) and length(comment) between 1 and 300)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index booking_review_provider_idx
  on public.booking_review(provider_id, created_at desc);

alter table public.booking_review enable row level security;
revoke all on public.booking_review from public, anon, authenticated;
grant select on public.booking_review to authenticated;
create policy booking_review_participant_read
  on public.booking_review for select to authenticated
  using (owner_id = (select auth.uid()) or
         provider_id = (select auth.uid()));

create function public.save_booking_review(
  p_booking_id uuid,
  p_rating integer,
  p_comment text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_booking public.booking%rowtype;
  v_review public.booking_review%rowtype;
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
  v_average numeric(3,2);
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_rating is null or p_rating not between 1 and 5 or
     length(v_comment) > 300 then
    raise exception 'Rating must be 1 to 5 and comment at most 300 characters'
      using errcode = '22023';
  end if;

  select * into v_booking from public.booking b
    where b.booking_id = p_booking_id for share;
  if not found or v_booking.owner_id <> v_actor then
    raise exception 'Only the booking Owner can review this booking'
      using errcode = '42501';
  end if;
  if v_booking.current_status <> 'Completed' then
    raise exception 'Only a Completed booking can be reviewed'
      using errcode = '23514';
  end if;

  -- Serialise multiple reviews for the same Provider before aggregating.
  perform 1 from public.provider_profile p
    where p.provider_id = v_booking.provider_id for update;
  insert into public.booking_review
    (booking_id, owner_id, provider_id, rating, comment)
  values
    (p_booking_id, v_actor, v_booking.provider_id, p_rating, v_comment)
  on conflict (booking_id) do update set
    rating = excluded.rating,
    comment = excluded.comment,
    updated_at = now()
  returning * into v_review;

  select round(avg(r.rating)::numeric, 2) into v_average
    from public.booking_review r
    where r.provider_id = v_booking.provider_id;
  update public.provider_profile p set rating_average = v_average
    where p.provider_id = v_booking.provider_id;

  return jsonb_build_object('booking_id', v_review.booking_id,
    'rating', v_review.rating, 'comment', v_review.comment,
    'rating_average', v_average);
end;
$$;
revoke execute on function public.save_booking_review(uuid, integer, text)
  from public, anon;
grant execute on function public.save_booking_review(uuid, integer, text)
  to authenticated;
