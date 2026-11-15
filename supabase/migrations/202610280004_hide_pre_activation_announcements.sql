-- Prevent newly activated tenants from reading announcements that were
-- published before they accepted their invitation. Administrators retain
-- access to every draft and published announcement.

drop policy if exists announcement_select on public.announcement;

create policy announcement_select
on public.announcement for select to authenticated
using (
  public.is_admin()
  or (
    announcement_status = 'published'
    and published_at is not null
    and published_at <= now()
    and (expires_at is null or expires_at > now())
    and exists (
      select 1
      from public.user_account account
      where account.user_id = (select auth.uid())
        and account.account_type = 'tenant'
        and account.account_status = 'active'
        and announcement.published_at >= coalesce(
          account.accepted_at,
          account.created_at
        )
    )
    and (
      audience_scope = 'all_tenants'
      or exists (
        select 1
        from public.announcement_recipient recipient
        where recipient.announcement_id = announcement.announcement_id
          and recipient.tenant_id = (select auth.uid())
      )
    )
  )
);
