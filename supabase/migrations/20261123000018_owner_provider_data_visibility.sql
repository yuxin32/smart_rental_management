-- Provider data minimisation. Apply after 202610170004_provider_setup.sql.
-- Keep the exact service origin private; approved directory rows expose only
-- fields needed to present a provider to an authenticated user.

drop policy if exists provider_profile_read on public.provider_profile;
create policy provider_profile_self_read on public.provider_profile
  for select to authenticated
  using ((select auth.uid()) = provider_id);

-- Raw capability and availability rows are operational inputs. A future
-- matching RPC should return eligible results, not another provider's
-- complete schedule or unavailable-date list.
drop policy if exists capability_read on public.provider_capability;
create policy capability_self_read on public.provider_capability
  for select to authenticated
  using ((select auth.uid()) = provider_id);

drop policy if exists weekly_slot_read on public.provider_weekly_slot;
create policy weekly_slot_self_read on public.provider_weekly_slot
  for select to authenticated
  using ((select auth.uid()) = provider_id);

drop policy if exists unavailable_date_read on public.provider_unavailable_date;
create policy unavailable_date_self_read on public.provider_unavailable_date
  for select to authenticated
  using ((select auth.uid()) = provider_id);

-- SECURITY DEFINER bypasses the private-row RLS deliberately. The result
-- contains an explicit safe column list; never add service_origin_address,
-- contact details, or raw availability here.
create function public.list_approved_provider_directory()
returns table (
  provider_id uuid,
  bio text,
  service_area text,
  hourly_rate numeric,
  daily_rate numeric,
  rating_average numeric,
  completed_job_count integer,
  service_type_ids uuid[]
)
language sql stable security definer set search_path = '' as $$
  select p.provider_id, p.bio, p.service_area, p.hourly_rate,
         p.daily_rate, p.rating_average, p.completed_job_count,
         array(
           select c.service_type_id
           from public.provider_capability c
           where c.provider_id = p.provider_id
           order by c.service_type_id
         ) as service_type_ids
  from public.provider_profile p
  where (select auth.uid()) is not null
    and p.approval_status = 'approved'
  order by p.provider_id;
$$;
revoke execute on function public.list_approved_provider_directory()
  from public, anon;
grant execute on function public.list_approved_provider_directory()
  to authenticated;
