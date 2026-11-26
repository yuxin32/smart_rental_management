create function public.mark_tenant_announcement_read(p_announcement_id uuid)
returns timestamptz language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); opened timestamptz;
begin
  if actor is null or not exists(
    select 1 from public.announcement a join public.user_account u on u.user_id=actor
    where a.announcement_id=p_announcement_id and u.role='tenant' and u.account_status='active'
      and a.announcement_status='published' and a.published_at<=now()
      and a.published_at>=coalesce(u.accepted_at,u.created_at)
      and (a.expires_at is null or a.expires_at>now())
      and (a.audience_scope='all_tenants' or exists(select 1 from public.announcement_recipient r
        where r.announcement_id=a.announcement_id and r.tenant_id=actor))
  ) then raise exception 'This announcement is not available to your account.' using errcode='42501'; end if;
  insert into public.announcement_recipient(announcement_id,tenant_id,delivery_status,delivered_at,read_at)
    values(p_announcement_id,actor,'delivered',now(),now())
    on conflict(announcement_id,tenant_id) do update set
      read_at=coalesce(public.announcement_recipient.read_at,excluded.read_at),delivery_status='delivered'
    returning read_at into opened;
  return opened;
end;$$;
revoke all on function public.mark_tenant_announcement_read(uuid) from public,anon;
grant execute on function public.mark_tenant_announcement_read(uuid) to authenticated;
notify pgrst,'reload schema';
