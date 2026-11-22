-- Tenant account lifecycle
-- Stores tenant information before a Supabase Auth account is created.

alter table public.user_account
  add column if not exists invitation_status varchar(20) not null default 'not_invited'
    check (invitation_status in ('not_invited', 'invited', 'accepted', 'expired', 'cancelled'));

alter table public.user_account
  add column if not exists invited_at timestamptz;

alter table public.user_account
  add column if not exists accepted_at timestamptz;

alter table public.tenant
  add column if not exists ic_number varchar(30);

create unique index if not exists uq_tenant_ic_number
  on public.tenant (ic_number)
  where ic_number is not null;

create table if not exists public.tenant_registration (
  registration_id uuid primary key default gen_random_uuid(),
  full_name varchar(100) not null,
  ic_number varchar(30) not null,
  email varchar(254) not null,
  contact_number varchar(30),
  identity_document_path text,
  employment_or_study_proof_path text,
  verification_status varchar(20) not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected')),
  registration_status varchar(20) not null default 'draft'
    check (registration_status in (
      'draft', 'assigned', 'invited', 'accepted', 'cancelled', 'expired'
    )),
  unit_id uuid references public.rental_unit(unit_id) on delete restrict,
  start_date date,
  end_date date,
  monthly_rental_amount numeric(12,2),
  occupancy_share numeric(5,4) not null default 1.0000
    check (occupancy_share > 0 and occupancy_share <= 1),
  auth_user_id uuid references auth.users(id) on delete set null,
  created_by_admin_id uuid not null references public.admin(admin_id) on delete restrict,
  invited_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint uq_tenant_registration_email unique (email),
  constraint uq_tenant_registration_ic_number unique (ic_number),
  constraint valid_registration_dates check (
    end_date is null or start_date is null or end_date >= start_date
  ),
  constraint complete_assignment check (
    registration_status not in ('assigned', 'invited', 'accepted')
    or (
      unit_id is not null
      and start_date is not null
      and monthly_rental_amount is not null
      and monthly_rental_amount >= 0
    )
  )
);

create index if not exists idx_tenant_registration_status
  on public.tenant_registration (registration_status);

create index if not exists idx_tenant_registration_created_by
  on public.tenant_registration (created_by_admin_id);

create index if not exists idx_tenant_registration_auth_user
  on public.tenant_registration (auth_user_id);

drop trigger if exists trg_tenant_registration_updated_at
  on public.tenant_registration;
create trigger trg_tenant_registration_updated_at
before update on public.tenant_registration
for each row execute function public.set_updated_at();

create unique index if not exists uq_open_tenancy_per_tenant
  on public.tenancy (tenant_id)
  where tenancy_status in ('pending', 'active');

alter table public.tenant_registration enable row level security;

drop policy if exists tenant_registration_admin_select
  on public.tenant_registration;
create policy tenant_registration_admin_select
on public.tenant_registration for select to authenticated
using (public.is_admin());

drop policy if exists tenant_registration_admin_insert
  on public.tenant_registration;
create policy tenant_registration_admin_insert
on public.tenant_registration for insert to authenticated
with check (
  public.is_admin()
  and created_by_admin_id = (select auth.uid())
);

drop policy if exists tenant_registration_admin_update
  on public.tenant_registration;
create policy tenant_registration_admin_update
on public.tenant_registration for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists tenant_registration_admin_delete
  on public.tenant_registration;
create policy tenant_registration_admin_delete
on public.tenant_registration for delete to authenticated
using (public.is_admin());

grant select, insert, update, delete
on public.tenant_registration to authenticated;

create or replace function public.activate_current_tenant()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  activated boolean := false;
begin
  if current_user_id is null then
    return false;
  end if;

  update public.user_account
  set account_status = 'active',
      invitation_status = 'accepted',
      accepted_at = coalesce(accepted_at, now()),
      updated_at = now()
  where user_id = current_user_id
    and role = 'tenant'
    and invitation_status in ('invited', 'accepted');

  activated := found;

  if activated then
    update public.tenancy
    set tenancy_status = 'active'
    where tenant_id = current_user_id
      and tenancy_status = 'pending';

    update public.tenant_registration
    set registration_status = 'accepted',
        accepted_at = coalesce(accepted_at, now()),
        updated_at = now()
    where auth_user_id = current_user_id
      and registration_status = 'invited';
  end if;

  return activated;
end;
$$;

grant execute on function public.activate_current_tenant() to authenticated;
