begin;

-- MIGRATION 20261123000001_tenant_initial_schema.sql
create type public.account_type as enum ('tenant','admin','owner','provider');
-- Smart Rental Management - initial Supabase schema
-- The Supabase auth.users table is the identity source. This migration does
-- not duplicate it; public.user_account stores application profile data.

create extension if not exists pgcrypto;

create table if not exists public.user_account (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name varchar(100) not null default '',
  email varchar(254) not null,
  contact_number varchar(30),
  role public.account_type not null,
  account_status varchar(20) not null default 'pending'
    check (account_status in ('pending', 'active', 'suspended', 'expired', 'deactivated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin (
  admin_id uuid primary key references public.user_account(user_id) on delete cascade,
  admin_code varchar(20) not null unique,
  is_active boolean not null default true,
  can_manage_billing boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.tenant (
  tenant_id uuid primary key references public.user_account(user_id) on delete cascade,
  verification_status varchar(20) not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected', 'expired')),
  is_verified boolean not null default false,
  identity_document_path text,
  employment_or_study_proof_path text,
  verified_by_admin_id uuid references public.admin(admin_id),
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.rental_unit (
  unit_id uuid primary key default gen_random_uuid(),
  unit_number varchar(50) not null unique,
  block_and_floor varchar(50),
  occupancy_capacity int not null default 1 check (occupancy_capacity > 0),
  unit_status varchar(20) not null default 'available'
    check (unit_status in ('available', 'occupied', 'maintenance', 'inactive')),
  created_at timestamptz not null default now()
);

create table if not exists public.tenancy (
  tenancy_id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant(tenant_id) on delete restrict,
  unit_id uuid not null references public.rental_unit(unit_id) on delete restrict,
  start_date date not null,
  end_date date,
  monthly_rental_amount numeric(12,2) not null check (monthly_rental_amount >= 0),
  occupancy_share numeric(5,4) not null default 1.0000
    check (occupancy_share > 0 and occupancy_share <= 1),
  tenancy_status varchar(20) not null default 'active'
    check (tenancy_status in ('pending', 'active', 'ended', 'terminated')),
  created_at timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);

create unique index if not exists uq_active_tenancy_per_tenant
  on public.tenancy (tenant_id) where tenancy_status = 'active';

create table if not exists public.electricity_device (
  device_id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.rental_unit(unit_id) on delete restrict,
  registered_by_admin_id uuid not null references public.admin(admin_id) on delete restrict,
  device_identifier varchar(64) not null unique,
  meter_model varchar(80) not null default 'CHINT DDSU666 5(80)A 2P',
  reading_type varchar(20) not null default 'cumulative_kwh'
    check (reading_type in ('cumulative_kwh', 'interval_kwh')),
  sampling_interval_sec int not null default 300 check (sampling_interval_sec > 0),
  calibration_factor double precision not null default 1.0 check (calibration_factor > 0),
  measurement_tolerance double precision not null default 0.02
    check (measurement_tolerance >= 0),
  device_status varchar(20) not null default 'active'
    check (device_status in ('pending', 'active', 'offline', 'retired')),
  registered_at timestamptz not null default now()
);

create table if not exists public.electricity_reading (
  reading_id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.electricity_device(device_id) on delete restrict,
  measurement_timestamp timestamptz not null,
  received_at timestamptz not null default now(),
  cumulative_energy_kwh numeric(14,6) not null check (cumulative_energy_kwh >= 0),
  interval_energy_kwh numeric(14,6) check (interval_energy_kwh is null or interval_energy_kwh >= 0),
  voltage_v numeric(8,3),
  current_a numeric(10,3),
  power_w numeric(12,3),
  power_factor numeric(5,3) check (power_factor is null or power_factor between 0 and 1),
  frequency_hz numeric(7,3),
  sequence_number bigint,
  validation_status varchar(20) not null default 'pending'
    check (validation_status in ('pending', 'accepted', 'rejected', 'flagged')),
  validation_reason varchar(255),
  created_at timestamptz not null default now(),
  unique (device_id, measurement_timestamp),
  unique (device_id, sequence_number)
);

create index if not exists ix_electricity_reading_device_time
  on public.electricity_reading (device_id, measurement_timestamp desc);

create table if not exists public.tariff_plan (
  tariff_id uuid primary key default gen_random_uuid(),
  created_by_admin_id uuid not null references public.admin(admin_id) on delete restrict,
  tariff_name varchar(80) not null,
  calculation_method varchar(20) not null default 'flat'
    check (calculation_method in ('flat', 'tiered')),
  effective_from date not null,
  effective_to date,
  tariff_status varchar(20) not null default 'active'
    check (tariff_status in ('draft', 'active', 'expired', 'inactive')),
  created_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from)
);

create table if not exists public.tariff_rate (
  tariff_rate_id uuid primary key default gen_random_uuid(),
  tariff_id uuid not null references public.tariff_plan(tariff_id) on delete cascade,
  tier_sequence int not null check (tier_sequence > 0),
  lower_kwh numeric(14,6) not null check (lower_kwh >= 0),
  upper_kwh numeric(14,6),
  rate_per_kwh numeric(10,4) not null check (rate_per_kwh >= 0),
  unique (tariff_id, tier_sequence),
  check (upper_kwh is null or upper_kwh > lower_kwh)
);

create table if not exists public.bill (
  bill_id uuid primary key default gen_random_uuid(),
  tenancy_id uuid not null references public.tenancy(tenancy_id) on delete restrict,
  generated_by_admin_id uuid not null references public.admin(admin_id) on delete restrict,
  billing_period_start date not null,
  billing_period_end date not null,
  validated_kwh numeric(14,6) not null default 0 check (validated_kwh >= 0),
  rental_amount numeric(12,2) not null default 0 check (rental_amount >= 0),
  utility_amount numeric(12,2) not null default 0 check (utility_amount >= 0),
  occupancy_share numeric(5,4) not null default 1.0000
    check (occupancy_share > 0 and occupancy_share <= 1),
  total_amount numeric(12,2) not null default 0 check (total_amount >= 0),
  due_date date not null,
  bill_status varchar(20) not null default 'unpaid'
    check (bill_status in ('draft', 'issued', 'unpaid', 'paid', 'overdue', 'void')),
  generated_at timestamptz not null default now(),
  unique (tenancy_id, billing_period_start, billing_period_end),
  check (billing_period_end >= billing_period_start)
);

create table if not exists public.bill_tariff_detail (
  bill_tariff_id uuid primary key default gen_random_uuid(),
  bill_id uuid not null references public.bill(bill_id) on delete cascade,
  tariff_rate_id uuid not null references public.tariff_rate(tariff_rate_id) on delete restrict,
  segment_start numeric(14,6) not null check (segment_start >= 0),
  segment_end numeric(14,6),
  allocated_kwh numeric(14,6) not null check (allocated_kwh >= 0),
  applied_rate numeric(10,4) not null check (applied_rate >= 0),
  segment_amount numeric(12,2) not null check (segment_amount >= 0),
  check (segment_end is null or segment_end >= segment_start)
);

create table if not exists public.payment_transaction (
  payment_id uuid primary key default gen_random_uuid(),
  bill_id uuid not null references public.bill(bill_id) on delete restrict,
  initiated_by_tenant_id uuid not null references public.tenant(tenant_id) on delete restrict,
  gateway_reference varchar(100),
  provider_transaction_id varchar(100),
  amount numeric(12,2) not null check (amount >= 0),
  currency char(3) not null default 'MYR',
  payment_status varchar(20) not null default 'initiated'
    check (payment_status in ('initiated', 'pending', 'successful', 'failed', 'cancelled', 'refunded')),
  gateway_result_code varchar(50),
  initiated_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.maintenance_request (
  maintenance_id uuid primary key default gen_random_uuid(),
  tenancy_id uuid not null references public.tenancy(tenancy_id) on delete restrict,
  assigned_admin_id uuid references public.admin(admin_id) on delete set null,
  category varchar(50) not null,
  description text not null,
  location_details varchar(150),
  image_storage_path text,
  request_status varchar(20) not null default 'submitted'
    check (request_status in ('submitted', 'in_progress', 'resolved', 'rejected')),
  submitted_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists public.maintenance_update (
  update_id uuid primary key default gen_random_uuid(),
  maintenance_id uuid not null references public.maintenance_request(maintenance_id) on delete cascade,
  updated_by_admin_id uuid not null references public.admin(admin_id) on delete restrict,
  old_status varchar(20),
  new_status varchar(20) not null,
  remarks text,
  created_at timestamptz not null default now()
);

create table if not exists public.announcement (
  announcement_id uuid primary key default gen_random_uuid(),
  created_by_admin_id uuid not null references public.admin(admin_id) on delete restrict,
  title varchar(150) not null,
  content text not null,
  audience_scope varchar(30) not null default 'all_tenants'
    check (audience_scope in ('all_tenants', 'selected_tenants', 'selected_units')),
  published_at timestamptz,
  expires_at timestamptz,
  announcement_status varchar(20) not null default 'draft'
    check (announcement_status in ('draft', 'published', 'expired', 'archived')),
  created_at timestamptz not null default now()
);

create table if not exists public.announcement_recipient (
  announcement_id uuid not null references public.announcement(announcement_id) on delete cascade,
  tenant_id uuid not null references public.tenant(tenant_id) on delete cascade,
  delivery_status varchar(20) not null default 'pending'
    check (delivery_status in ('pending', 'delivered', 'failed')),
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (announcement_id, tenant_id)
);

create table if not exists public.conversation (
  conversation_id uuid primary key default gen_random_uuid(),
  tenancy_id uuid not null references public.tenancy(tenancy_id) on delete restrict,
  admin_id uuid not null references public.admin(admin_id) on delete restrict,
  conversation_status varchar(20) not null default 'open'
    check (conversation_status in ('open', 'closed', 'archived')),
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  unique (tenancy_id, admin_id)
);

create table if not exists public.message (
  message_id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversation(conversation_id) on delete cascade,
  sender_user_id uuid not null references public.user_account(user_id) on delete restrict,
  message_text text not null,
  attachment_storage_path text,
  sent_at timestamptz not null default now(),
  delivered_at timestamptz,
  read_at timestamptz
);

create table if not exists public.audit_log (
  audit_id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.user_account(user_id) on delete set null,
  action_type varchar(80) not null,
  entity_type varchar(80) not null,
  entity_id uuid,
  outcome varchar(30) not null,
  event_timestamp timestamptz not null default now(),
  metadata jsonb
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_user_account_updated_at on public.user_account;
create trigger trg_user_account_updated_at
before update on public.user_account
for each row execute function public.set_updated_at();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin
    where admin_id = (select auth.uid())
      and is_active = true
  );
$$;

create or replace function public.has_tenant_access(target_tenancy_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tenancy
    where tenancy_id = target_tenancy_id
      and tenant_id = (select auth.uid())
      and tenancy_status = 'active'
  );
$$;

alter table public.user_account enable row level security;
alter table public.admin enable row level security;
alter table public.tenant enable row level security;
alter table public.rental_unit enable row level security;
alter table public.tenancy enable row level security;
alter table public.electricity_device enable row level security;
alter table public.electricity_reading enable row level security;
alter table public.tariff_plan enable row level security;
alter table public.tariff_rate enable row level security;
alter table public.bill enable row level security;
alter table public.bill_tariff_detail enable row level security;
alter table public.payment_transaction enable row level security;
alter table public.maintenance_request enable row level security;
alter table public.maintenance_update enable row level security;
alter table public.announcement enable row level security;
alter table public.announcement_recipient enable row level security;
alter table public.conversation enable row level security;
alter table public.message enable row level security;
alter table public.audit_log enable row level security;

create policy user_account_select on public.user_account for select to authenticated
using (user_id = (select auth.uid()) or public.is_admin());
create policy user_account_update on public.user_account for update to authenticated
using (user_id = (select auth.uid()) or public.is_admin())
with check (user_id = (select auth.uid()) or public.is_admin());

create policy admin_select on public.admin for select to authenticated
using (admin_id = (select auth.uid()) or public.is_admin());
create policy admin_manage on public.admin for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy tenant_select on public.tenant for select to authenticated
using (tenant_id = (select auth.uid()) or public.is_admin());
create policy tenant_manage on public.tenant for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy unit_select on public.rental_unit for select to authenticated
using (
  public.is_admin()
  or exists (
    select 1 from public.tenancy t
    where t.unit_id = rental_unit.unit_id
      and t.tenant_id = (select auth.uid())
      and t.tenancy_status = 'active'
  )
);
create policy unit_manage on public.rental_unit for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy tenancy_select on public.tenancy for select to authenticated
using (tenant_id = (select auth.uid()) or public.is_admin());
create policy tenancy_manage on public.tenancy for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy device_select on public.electricity_device for select to authenticated
using (
  public.is_admin()
  or exists (
    select 1 from public.tenancy t
    where t.unit_id = electricity_device.unit_id
      and t.tenant_id = (select auth.uid())
      and t.tenancy_status = 'active'
  )
);
create policy device_manage on public.electricity_device for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy reading_select on public.electricity_reading for select to authenticated
using (
  public.is_admin()
  or exists (
    select 1
    from public.electricity_device d
    join public.tenancy t on t.unit_id = d.unit_id
    where d.device_id = electricity_reading.device_id
      and t.tenant_id = (select auth.uid())
      and t.tenancy_status = 'active'
      and electricity_reading.validation_status = 'accepted'
  )
);
create policy reading_admin_manage on public.electricity_reading for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy tariff_select on public.tariff_plan for select to authenticated
using (public.is_admin() or tariff_status = 'active');
create policy tariff_manage on public.tariff_plan for all to authenticated
using (public.is_admin()) with check (public.is_admin());
create policy tariff_rate_select on public.tariff_rate for select to authenticated
using (
  public.is_admin()
  or exists (select 1 from public.tariff_plan p where p.tariff_id = tariff_rate.tariff_id and p.tariff_status = 'active')
);
create policy tariff_rate_manage on public.tariff_rate for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy bill_select on public.bill for select to authenticated
using (public.is_admin() or public.has_tenant_access(tenancy_id));
create policy bill_admin_manage on public.bill for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy bill_detail_select on public.bill_tariff_detail for select to authenticated
using (
  public.is_admin()
  or exists (select 1 from public.bill b where b.bill_id = bill_tariff_detail.bill_id and public.has_tenant_access(b.tenancy_id))
);
create policy bill_detail_admin_manage on public.bill_tariff_detail for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy payment_select on public.payment_transaction for select to authenticated
using (public.is_admin() or initiated_by_tenant_id = (select auth.uid()));
create policy payment_insert on public.payment_transaction for insert to authenticated
with check (initiated_by_tenant_id = (select auth.uid()));
create policy payment_admin_manage on public.payment_transaction for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy maintenance_select on public.maintenance_request for select to authenticated
using (public.is_admin() or public.has_tenant_access(tenancy_id));
create policy maintenance_insert on public.maintenance_request for insert to authenticated
with check (public.has_tenant_access(tenancy_id));
create policy maintenance_admin_manage on public.maintenance_request for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy maintenance_update_select on public.maintenance_update for select to authenticated
using (
  public.is_admin()
  or exists (
    select 1 from public.maintenance_request m
    where m.maintenance_id = maintenance_update.maintenance_id
      and public.has_tenant_access(m.tenancy_id)
  )
);
create policy maintenance_update_admin_manage on public.maintenance_update for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy announcement_select on public.announcement for select to authenticated
using (public.is_admin() or announcement_status = 'published');
create policy announcement_admin_manage on public.announcement for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy recipient_select on public.announcement_recipient for select to authenticated
using (public.is_admin() or tenant_id = (select auth.uid()));
create policy recipient_admin_manage on public.announcement_recipient for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy conversation_select on public.conversation for select to authenticated
using (public.is_admin() or public.has_tenant_access(tenancy_id));
create policy conversation_admin_manage on public.conversation for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy message_select on public.message for select to authenticated
using (
  public.is_admin()
  or exists (
    select 1
    from public.conversation c
    where c.conversation_id = message.conversation_id
      and public.has_tenant_access(c.tenancy_id)
  )
);
create policy message_insert on public.message for insert to authenticated
with check (
  sender_user_id = (select auth.uid())
  and exists (
    select 1
    from public.conversation c
    where c.conversation_id = message.conversation_id
      and (public.is_admin() or public.has_tenant_access(c.tenancy_id))
  )
);

create policy audit_admin_select on public.audit_log for select to authenticated
using (public.is_admin());

grant usage on schema public to anon, authenticated;
grant select, insert, update on public.user_account to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- Protect role and lifecycle fields from self-service changes, and ensure a
-- tenant can only start a payment for a bill belonging to the tenant's active
-- tenancy.
create or replace function public.protect_user_account_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    new.role := old.role;
    new.account_status := old.account_status;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_user_account_fields on public.user_account;
create trigger trg_protect_user_account_fields
before update on public.user_account
for each row execute function public.protect_user_account_fields();

drop policy if exists user_account_update on public.user_account;
create policy user_account_update on public.user_account for update to authenticated
using (user_id = (select auth.uid()) or public.is_admin())
with check (user_id = (select auth.uid()) or public.is_admin());

drop policy if exists payment_insert on public.payment_transaction;
create policy payment_insert on public.payment_transaction for insert to authenticated
with check (
  initiated_by_tenant_id = (select auth.uid())
  and exists (
    select 1
    from public.bill b
    join public.tenancy t on t.tenancy_id = b.tenancy_id
    where b.bill_id = payment_transaction.bill_id
      and t.tenant_id = (select auth.uid())
      and t.tenancy_status = 'active'
  )
);


-- MIGRATION 20261123000002_tenant_tenant_account_lifecycle.sql
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


-- MIGRATION 20261123000003_tenant_tenant_onboarding_audit.sql
-- Tenant onboarding audit trail and safe pending-invitation resend support.
-- The existing audit_log table is reused so administrators can trace the
-- tenant information, unit assignment, and invitation lifecycle.

create index if not exists idx_audit_log_entity_event
  on public.audit_log (entity_type, entity_id, event_timestamp desc);

create index if not exists idx_audit_log_action_event
  on public.audit_log (action_type, event_timestamp desc);

create or replace function public.audit_tenant_registration_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  assigned_unit_number varchar(50);
begin
  -- The authenticated administrator is the actor for changes made through the
  -- application. Service-role changes do not have an auth.uid() and are
  -- logged explicitly by the invitation Edge Function instead.
  if (select auth.uid()) is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    insert into public.audit_log (
      actor_user_id,
      action_type,
      entity_type,
      entity_id,
      outcome,
      metadata
    ) values (
      (select auth.uid()),
      'TENANT_INFORMATION_ADDED',
      'tenant_registration',
      new.registration_id,
      'success',
      jsonb_build_object(
        'verification_status', new.verification_status,
        'registration_status', new.registration_status
      )
    );
  elsif tg_op = 'UPDATE'
    and new.unit_id is not null
    and (
      old.unit_id is distinct from new.unit_id
      or old.start_date is distinct from new.start_date
      or old.end_date is distinct from new.end_date
      or old.monthly_rental_amount is distinct from new.monthly_rental_amount
      or old.occupancy_share is distinct from new.occupancy_share
    ) then
    select unit_number
    into assigned_unit_number
    from public.rental_unit
    where unit_id = new.unit_id;

    insert into public.audit_log (
      actor_user_id,
      action_type,
      entity_type,
      entity_id,
      outcome,
      metadata
    ) values (
      (select auth.uid()),
      'TENANT_UNIT_ASSIGNED',
      'tenant_registration',
      new.registration_id,
      'success',
      jsonb_build_object(
        'unit_id', new.unit_id,
        'unit_number', assigned_unit_number,
        'start_date', new.start_date,
        'end_date', new.end_date,
        'monthly_rental_amount', new.monthly_rental_amount,
        'occupancy_share', new.occupancy_share
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_audit_tenant_registration_changes
  on public.tenant_registration;

create trigger trg_audit_tenant_registration_changes
after insert or update on public.tenant_registration
for each row execute function public.audit_tenant_registration_changes();

revoke all on function public.audit_tenant_registration_changes()
from public, anon, authenticated;


-- MIGRATION 20261123000004_tenant_tenant_verification_documents.sql
-- Tenant-submitted verification documents.
-- The document binary is kept in a private Storage bucket. The database
-- stores only the storage paths, submission metadata, and administrator review.

create or replace function public.is_allowed_verification_file(file_path text)
returns boolean
language sql
immutable
as $$
  select lower(file_path) like '%.pdf'
      or lower(file_path) like '%.jpg'
      or lower(file_path) like '%.jpeg'
      or lower(file_path) like '%.png'
      or lower(file_path) like '%.webp'
      or lower(file_path) like '%.heic'
      or lower(file_path) like '%.heif';
$$;

revoke all on function public.is_allowed_verification_file(text)
from public, anon, authenticated;
grant execute on function public.is_allowed_verification_file(text)
to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'tenant-verification-documents',
  'tenant-verification-documents',
  false,
  10485760,
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ]::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = array[
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif'
    ]::text[];

alter table public.tenant_registration
  add column if not exists documents_submitted_at timestamptz,
  add column if not exists verification_notes text,
  add column if not exists verification_reviewed_by_admin_id uuid
    references public.admin(admin_id),
  add column if not exists verification_reviewed_at timestamptz;

-- Before this workflow, invited and accepted registrations were required to
-- have an assigned unit. A tenant must now be able to accept an invitation
-- and submit documents before a unit is assigned.
alter table public.tenant_registration
  drop constraint if exists complete_assignment;

alter table public.tenant_registration
  drop constraint if exists valid_assignment_status;

alter table public.tenant_registration
  add constraint valid_assignment_status check (
    registration_status <> 'assigned'
    or (
      unit_id is not null
      and start_date is not null
      and monthly_rental_amount is not null
      and monthly_rental_amount >= 0
    )
  );

drop policy if exists tenant_registration_tenant_select
  on public.tenant_registration;
create policy tenant_registration_tenant_select
on public.tenant_registration for select to authenticated
using (auth_user_id = (select auth.uid()));

drop policy if exists tenant_verification_documents_select
  on storage.objects;
create policy tenant_verification_documents_select
on storage.objects for select to authenticated
using (
  bucket_id = 'tenant-verification-documents'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_admin()
  )
);

drop policy if exists tenant_verification_documents_insert
  on storage.objects;
create policy tenant_verification_documents_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'tenant-verification-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.is_allowed_verification_file(name)
);

drop policy if exists tenant_verification_documents_update
  on storage.objects;
create policy tenant_verification_documents_update
on storage.objects for update to authenticated
using (
  bucket_id = 'tenant-verification-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'tenant-verification-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.is_allowed_verification_file(name)
);

drop policy if exists tenant_verification_documents_delete
  on storage.objects;
create policy tenant_verification_documents_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'tenant-verification-documents'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_admin()
  )
);

create or replace function public.complete_current_tenant_setup()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    return false;
  end if;

  update public.user_account
  set invitation_status = 'accepted',
      accepted_at = coalesce(accepted_at, now()),
      updated_at = now()
  where user_id = current_user_id
    and role = 'tenant'
    and account_status = 'pending'
    and invitation_status = 'invited';

  if not found and not exists (
    select 1
    from public.user_account
    where user_id = current_user_id
      and role = 'tenant'
      and invitation_status = 'accepted'
  ) then
    return false;
  end if;

  update public.tenant_registration
  set registration_status = case
        when registration_status = 'invited' then 'accepted'
        else registration_status
      end,
      accepted_at = coalesce(accepted_at, now()),
      updated_at = now()
  where auth_user_id = current_user_id;

  return true;
end;
$$;

grant execute on function public.complete_current_tenant_setup() to authenticated;

create or replace function public.submit_tenant_verification_documents(
  p_identity_document_path text,
  p_employment_or_study_proof_path text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    return false;
  end if;

  if p_identity_document_path is null
     or p_employment_or_study_proof_path is null
     or not public.is_allowed_verification_file(p_identity_document_path)
     or not public.is_allowed_verification_file(p_employment_or_study_proof_path)
     or split_part(p_identity_document_path, '/', 1) <> current_user_id::text
     or split_part(p_employment_or_study_proof_path, '/', 1) <> current_user_id::text then
    raise exception 'Invalid verification document path.';
  end if;

  update public.tenant_registration
  set identity_document_path = p_identity_document_path,
      employment_or_study_proof_path = p_employment_or_study_proof_path,
      documents_submitted_at = now(),
      verification_status = 'pending',
      verification_notes = null,
      verification_reviewed_by_admin_id = null,
      verification_reviewed_at = null,
      updated_at = now()
  where auth_user_id = current_user_id
    and registration_status in ('invited', 'accepted');

  if not found then
    return false;
  end if;

  update public.tenant
  set identity_document_path = p_identity_document_path,
      employment_or_study_proof_path = p_employment_or_study_proof_path,
      verification_status = 'pending',
      is_verified = false,
      verified_by_admin_id = null,
      verified_at = null
  where tenant_id = current_user_id;

  return true;
end;
$$;

grant execute on function public.submit_tenant_verification_documents(text, text)
to authenticated;

create or replace function public.review_tenant_verification(
  p_registration_id uuid,
  p_verification_status varchar,
  p_verification_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  target_user_id uuid;
  identity_path text;
  proof_path text;
begin
  if current_admin_id is null or not public.is_admin() then
    return false;
  end if;

  if p_verification_status not in ('verified', 'rejected', 'pending') then
    raise exception 'Invalid verification status.';
  end if;

  select auth_user_id, identity_document_path, employment_or_study_proof_path
  into target_user_id, identity_path, proof_path
  from public.tenant_registration
  where registration_id = p_registration_id;

  if not found then
    raise exception 'Tenant registration was not found.';
  end if;

  if p_verification_status = 'verified'
     and (identity_path is null or proof_path is null) then
    raise exception 'Both tenant verification documents are required.';
  end if;

  update public.tenant_registration
  set verification_status = p_verification_status,
      verification_notes = nullif(trim(coalesce(p_verification_notes, '')), ''),
      verification_reviewed_by_admin_id = current_admin_id,
      verification_reviewed_at = now(),
      updated_at = now()
  where registration_id = p_registration_id;

  if target_user_id is not null then
    update public.tenant
    set verification_status = p_verification_status,
        is_verified = p_verification_status = 'verified',
        verified_by_admin_id = case
          when p_verification_status = 'verified' then current_admin_id
          else null
        end,
        verified_at = case
          when p_verification_status = 'verified' then now()
          else null
        end
    where tenant_id = target_user_id;
  end if;

  insert into public.audit_log (
    actor_user_id,
    action_type,
    entity_type,
    entity_id,
    outcome,
    metadata
  ) values (
    current_admin_id,
    'TENANT_VERIFICATION_REVIEWED',
    'tenant_registration',
    p_registration_id,
    'success',
    jsonb_build_object(
      'verification_status', p_verification_status,
      'has_identity_document', identity_path is not null,
      'has_employment_or_study_proof', proof_path is not null
    )
  );

  return true;
end;
$$;

grant execute on function public.review_tenant_verification(uuid, varchar, text)
to authenticated;

create or replace function public.assign_verified_tenant(
  p_registration_id uuid,
  p_unit_id uuid,
  p_start_date date,
  p_end_date date,
  p_monthly_rental_amount numeric,
  p_occupancy_share numeric
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  target_user_id uuid;
  previous_unit_id uuid;
  existing_tenancy_id uuid;
begin
  if current_admin_id is null or not public.is_admin() then
    return false;
  end if;

  if p_start_date is null
     or p_monthly_rental_amount is null
     or p_monthly_rental_amount < 0
     or p_occupancy_share <= 0
     or p_occupancy_share > 1
     or (p_end_date is not null and p_end_date < p_start_date) then
    raise exception 'Invalid tenancy details.';
  end if;

  select auth_user_id
  into target_user_id
  from public.tenant_registration
  where registration_id = p_registration_id
    and verification_status = 'verified';

  if target_user_id is null then
    raise exception 'The tenant must be verified before unit assignment.';
  end if;

  select tenancy_id, unit_id
  into existing_tenancy_id, previous_unit_id
  from public.tenancy
  where tenant_id = target_user_id
    and tenancy_status in ('pending', 'active')
  order by start_date desc
  limit 1;

  if previous_unit_id is not null and previous_unit_id <> p_unit_id then
    update public.rental_unit
    set unit_status = 'available'
    where unit_id = previous_unit_id;
  end if;

  if existing_tenancy_id is null then
    insert into public.tenancy (
      tenant_id,
      unit_id,
      start_date,
      end_date,
      monthly_rental_amount,
      occupancy_share,
      tenancy_status
    ) values (
      target_user_id,
      p_unit_id,
      p_start_date,
      p_end_date,
      p_monthly_rental_amount,
      p_occupancy_share,
      'active'
    );
  else
    update public.tenancy
    set unit_id = p_unit_id,
        start_date = p_start_date,
        end_date = p_end_date,
        monthly_rental_amount = p_monthly_rental_amount,
        occupancy_share = p_occupancy_share,
        tenancy_status = 'active'
    where tenancy_id = existing_tenancy_id;
  end if;

  update public.rental_unit
  set unit_status = 'occupied'
  where unit_id = p_unit_id;

  update public.tenant_registration
  set unit_id = p_unit_id,
      start_date = p_start_date,
      end_date = p_end_date,
      monthly_rental_amount = p_monthly_rental_amount,
      occupancy_share = p_occupancy_share,
      registration_status = 'assigned',
      updated_at = now()
  where registration_id = p_registration_id;

  update public.user_account
  set account_status = 'active',
      updated_at = now()
  where user_id = target_user_id
    and invitation_status = 'accepted';

  return true;
end;
$$;

grant execute on function public.assign_verified_tenant(uuid, uuid, date, date, numeric, numeric)
to authenticated;


-- MIGRATION 20261123000005_tenant_live_chat_and_testing_access.sql
-- Live tenant-administrator chat and temporary FYP testing access.
-- Document verification remains available, but unit assignment does not depend
-- on it while the testing flag is enabled in the Flutter client.

alter table public.message
  add column if not exists message_type varchar(20) not null default 'text',
  add column if not exists attachment_name varchar(255),
  add column if not exists attachment_mime_type varchar(120),
  add column if not exists attachment_size_bytes bigint,
  add column if not exists expires_at timestamptz;

alter table public.message alter column message_text drop not null;

update public.message
set expires_at = sent_at + interval '2 years'
where expires_at is null;

alter table public.message
  alter column expires_at set default (now() + interval '2 years'),
  alter column expires_at set not null;

alter table public.message
  drop constraint if exists message_type_check,
  drop constraint if exists message_payload_check,
  drop constraint if exists message_attachment_size_check;

alter table public.message
  add constraint message_type_check
    check (message_type in ('text', 'file')),
  add constraint message_payload_check check (
    (
      message_type = 'text'
      and nullif(trim(message_text), '') is not null
      and attachment_storage_path is null
    )
    or
    (
      message_type = 'file'
      and attachment_storage_path is not null
      and attachment_name is not null
    )
  ),
  add constraint message_attachment_size_check check (
    attachment_size_bytes is null
    or attachment_size_bytes between 1 and 10485760
  );

create index if not exists idx_message_conversation_sent_at
  on public.message (conversation_id, sent_at);

create index if not exists idx_message_expires_at
  on public.message (expires_at);

create table if not exists public.chat_attachment_cleanup_queue (
  attachment_storage_path text primary key,
  queued_at timestamptz not null default now()
);

alter table public.chat_attachment_cleanup_queue enable row level security;

drop policy if exists chat_cleanup_admin_select
  on public.chat_attachment_cleanup_queue;
create policy chat_cleanup_admin_select
on public.chat_attachment_cleanup_queue for select to authenticated
using (public.is_admin());

drop policy if exists chat_cleanup_admin_delete
  on public.chat_attachment_cleanup_queue;
create policy chat_cleanup_admin_delete
on public.chat_attachment_cleanup_queue for delete to authenticated
using (public.is_admin());

grant select, delete on public.chat_attachment_cleanup_queue to authenticated;

create or replace function public.queue_deleted_chat_attachment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.attachment_storage_path is not null then
    insert into public.chat_attachment_cleanup_queue (
      attachment_storage_path,
      queued_at
    ) values (
      old.attachment_storage_path,
      now()
    )
    on conflict (attachment_storage_path) do update
    set queued_at = excluded.queued_at;
  end if;

  return old;
end;
$$;

drop trigger if exists trg_queue_deleted_chat_attachment on public.message;
create trigger trg_queue_deleted_chat_attachment
before delete on public.message
for each row execute function public.queue_deleted_chat_attachment();

create or replace function public.can_access_conversation(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversation c
    join public.tenancy t on t.tenancy_id = c.tenancy_id
    where c.conversation_id = target_conversation_id
      and (
        public.is_admin()
        or t.tenant_id = (select auth.uid())
      )
  );
$$;

revoke all on function public.can_access_conversation(uuid)
from public, anon, authenticated;
grant execute on function public.can_access_conversation(uuid)
to authenticated;

drop policy if exists conversation_select on public.conversation;
create policy conversation_select
on public.conversation for select to authenticated
using (public.can_access_conversation(conversation_id));

drop policy if exists message_select on public.message;
create policy message_select
on public.message for select to authenticated
using (
  expires_at > now()
  and public.can_access_conversation(conversation_id)
);

drop policy if exists message_insert on public.message;
create policy message_insert
on public.message for insert to authenticated
with check (
  sender_user_id = (select auth.uid())
  and public.can_access_conversation(conversation_id)
  and expires_at <= now() + interval '2 years 1 minute'
);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'chat-attachments',
  'chat-attachments',
  false,
  10485760,
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
    'text/csv'
  ]::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists chat_attachments_select on storage.objects;
create policy chat_attachments_select
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-attachments'
  and exists (
    select 1
    from public.conversation c
    join public.tenancy t on t.tenancy_id = c.tenancy_id
    where c.conversation_id::text = (storage.foldername(name))[1]
      and (
        public.is_admin()
        or t.tenant_id = (select auth.uid())
      )
  )
);

drop policy if exists chat_attachments_insert on storage.objects;
create policy chat_attachments_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and exists (
    select 1
    from public.conversation c
    join public.tenancy t on t.tenancy_id = c.tenancy_id
    where c.conversation_id::text = (storage.foldername(name))[1]
      and (
        public.is_admin()
        or t.tenant_id = (select auth.uid())
      )
  )
);

drop policy if exists chat_attachments_delete on storage.objects;
create policy chat_attachments_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'chat-attachments'
  and (
    (storage.foldername(name))[2] = (select auth.uid())::text
    or public.is_admin()
  )
);

create or replace function public.update_conversation_last_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversation
  set last_message_at = new.sent_at
  where conversation_id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists trg_update_conversation_last_message on public.message;
create trigger trg_update_conversation_last_message
after insert on public.message
for each row execute function public.update_conversation_last_message();

create or replace function public.get_my_conversations()
returns table (
  chat_conversation_id uuid,
  other_user_id uuid,
  other_party_name text,
  other_party_role text,
  unit_label text,
  chat_status varchar,
  last_message_preview text,
  latest_message_at timestamptz,
  unread_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    return;
  end if;

  if public.is_admin() then
    return query
    select
      c.conversation_id,
      t.tenant_id,
      coalesce(nullif(ua.full_name, ''), ua.email, 'Tenant')::text,
      'tenant'::text,
      case
        when ru.unit_id is null then 'Unit not assigned'
        when nullif(ru.block_and_floor, '') is null then ru.unit_number
        else ru.block_and_floor || ' · ' || ru.unit_number
      end::text,
      c.conversation_status,
      case
        when lm.message_id is null then 'No messages yet'
        when lm.message_type = 'file' then
          'File: ' || coalesce(lm.attachment_name, 'Attachment')
        else left(lm.message_text, 120)
      end::text,
      coalesce(lm.sent_at, c.created_at),
      (
        select count(*)
        from public.message unread
        where unread.conversation_id = c.conversation_id
          and unread.sender_user_id <> current_user_id
          and unread.read_at is null
          and unread.expires_at > now()
      )::bigint
    from public.conversation c
    join public.tenancy t on t.tenancy_id = c.tenancy_id
    join public.user_account ua on ua.user_id = t.tenant_id
    left join public.rental_unit ru on ru.unit_id = t.unit_id
    left join lateral (
      select m.*
      from public.message m
      where m.conversation_id = c.conversation_id
        and m.expires_at > now()
      order by m.sent_at desc
      limit 1
    ) lm on true
    where c.conversation_status <> 'archived'
    order by coalesce(lm.sent_at, c.created_at) desc;
  else
    return query
    select
      c.conversation_id,
      c.admin_id,
      coalesce(nullif(ua.full_name, ''), ua.email, 'Apartment Administrator')::text,
      'admin'::text,
      case
        when nullif(ru.block_and_floor, '') is null then ru.unit_number
        else ru.block_and_floor || ' · ' || ru.unit_number
      end::text,
      c.conversation_status,
      case
        when lm.message_id is null then 'No messages yet'
        when lm.message_type = 'file' then
          'File: ' || coalesce(lm.attachment_name, 'Attachment')
        else left(lm.message_text, 120)
      end::text,
      coalesce(lm.sent_at, c.created_at),
      (
        select count(*)
        from public.message unread
        where unread.conversation_id = c.conversation_id
          and unread.sender_user_id <> current_user_id
          and unread.read_at is null
          and unread.expires_at > now()
      )::bigint
    from public.conversation c
    join public.tenancy t on t.tenancy_id = c.tenancy_id
    join public.user_account ua on ua.user_id = c.admin_id
    join public.rental_unit ru on ru.unit_id = t.unit_id
    left join lateral (
      select m.*
      from public.message m
      where m.conversation_id = c.conversation_id
        and m.expires_at > now()
      order by m.sent_at desc
      limit 1
    ) lm on true
    where t.tenant_id = current_user_id
      and c.conversation_status <> 'archived'
    order by coalesce(lm.sent_at, c.created_at) desc;
  end if;
end;
$$;

grant execute on function public.get_my_conversations() to authenticated;

create or replace function public.mark_conversation_read(
  target_conversation_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_rows integer;
begin
  if not public.can_access_conversation(target_conversation_id) then
    raise exception 'Conversation access is not permitted.';
  end if;

  update public.message
  set delivered_at = coalesce(delivered_at, now()),
      read_at = now()
  where conversation_id = target_conversation_id
    and sender_user_id <> (select auth.uid())
    and read_at is null
    and expires_at > now();

  get diagnostics affected_rows = row_count;
  return affected_rows;
end;
$$;

grant execute on function public.mark_conversation_read(uuid)
to authenticated;

create or replace function public.purge_expired_chat_messages()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_rows integer;
begin
  if (select auth.uid()) is not null and not public.is_admin() then
    raise exception 'Only an administrator may run chat retention cleanup.';
  end if;

  delete from public.message
  where expires_at <= now();

  get diagnostics affected_rows = row_count;
  return affected_rows;
end;
$$;

revoke all on function public.purge_expired_chat_messages()
from public, anon;
grant execute on function public.purge_expired_chat_messages()
to authenticated, service_role;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message'
  ) then
    alter publication supabase_realtime add table public.message;
  end if;
end;
$$;

create extension if not exists pg_cron;

select cron.schedule(
  'purge-expired-chat-messages',
  '15 3 * * *',
  $$select public.purge_expired_chat_messages();$$
);

-- During module testing, account acceptance is sufficient for assignment.
-- The verification data remains intact and can still be reviewed separately.
create or replace function public.assign_verified_tenant(
  p_registration_id uuid,
  p_unit_id uuid,
  p_start_date date,
  p_end_date date,
  p_monthly_rental_amount numeric,
  p_occupancy_share numeric
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  target_user_id uuid;
  previous_unit_id uuid;
  existing_tenancy_id uuid;
begin
  if current_admin_id is null or not public.is_admin() then
    return false;
  end if;

  if p_start_date is null
     or p_monthly_rental_amount is null
     or p_monthly_rental_amount < 0
     or p_occupancy_share <= 0
     or p_occupancy_share > 1
     or (p_end_date is not null and p_end_date < p_start_date) then
    raise exception 'Invalid tenancy details.';
  end if;

  select auth_user_id
  into target_user_id
  from public.tenant_registration
  where registration_id = p_registration_id
    and auth_user_id is not null
    and registration_status in ('accepted', 'assigned');

  if target_user_id is null then
    raise exception 'The tenant must complete account setup before unit assignment.';
  end if;

  select tenancy_id, unit_id
  into existing_tenancy_id, previous_unit_id
  from public.tenancy
  where tenant_id = target_user_id
    and tenancy_status in ('pending', 'active')
  order by start_date desc
  limit 1;

  if previous_unit_id is not null and previous_unit_id <> p_unit_id then
    update public.rental_unit
    set unit_status = 'available'
    where unit_id = previous_unit_id;
  end if;

  if existing_tenancy_id is null then
    insert into public.tenancy (
      tenant_id,
      unit_id,
      start_date,
      end_date,
      monthly_rental_amount,
      occupancy_share,
      tenancy_status
    ) values (
      target_user_id,
      p_unit_id,
      p_start_date,
      p_end_date,
      p_monthly_rental_amount,
      p_occupancy_share,
      'active'
    )
    returning tenancy_id into existing_tenancy_id;
  else
    update public.tenancy
    set unit_id = p_unit_id,
        start_date = p_start_date,
        end_date = p_end_date,
        monthly_rental_amount = p_monthly_rental_amount,
        occupancy_share = p_occupancy_share,
        tenancy_status = 'active'
    where tenancy_id = existing_tenancy_id;
  end if;

  update public.rental_unit
  set unit_status = 'occupied'
  where unit_id = p_unit_id;

  update public.tenant_registration
  set unit_id = p_unit_id,
      start_date = p_start_date,
      end_date = p_end_date,
      monthly_rental_amount = p_monthly_rental_amount,
      occupancy_share = p_occupancy_share,
      registration_status = 'assigned',
      updated_at = now()
  where registration_id = p_registration_id;

  update public.user_account
  set account_status = 'active',
      updated_at = now()
  where user_id = target_user_id
    and invitation_status = 'accepted';

  insert into public.conversation (
    tenancy_id,
    admin_id,
    conversation_status
  ) values (
    existing_tenancy_id,
    current_admin_id,
    'open'
  )
  on conflict (tenancy_id, admin_id) do update
  set conversation_status = 'open';

  return true;
end;
$$;

grant execute on function public.assign_verified_tenant(
  uuid,
  uuid,
  date,
  date,
  numeric,
  numeric
) to authenticated;

-- Create database-backed chat lists for existing assigned tenants. No sample
-- names or message histories are inserted.
insert into public.conversation (
  tenancy_id,
  admin_id,
  conversation_status
)
select
  t.tenancy_id,
  active_admin.admin_id,
  'open'
from public.tenancy t
cross join lateral (
  select a.admin_id
  from public.admin a
  where a.is_active = true
  order by a.created_at
  limit 1
) active_admin
where t.tenancy_status = 'active'
  and not exists (
    select 1
    from public.conversation c
    where c.tenancy_id = t.tenancy_id
  )
on conflict (tenancy_id, admin_id) do nothing;


-- MIGRATION 20261123000006_tenant_database_announcements.sql
-- Database-backed announcement workflow for the Admin and Tenant modules.

alter table public.announcement
  add column if not exists audience_label varchar(80) not null default 'All tenants',
  add column if not exists updated_at timestamptz not null default now();

update public.announcement
set audience_label = case audience_scope
  when 'all_tenants' then 'All tenants'
  when 'selected_units' then 'Selected units'
  when 'selected_tenants' then 'Selected tenants'
  else 'All tenants'
end
where audience_label is null
   or trim(audience_label) = ''
   or (
     audience_label = 'All tenants'
     and audience_scope <> 'all_tenants'
   );

drop trigger if exists trg_announcement_updated_at on public.announcement;
create trigger trg_announcement_updated_at
before update on public.announcement
for each row execute function public.set_updated_at();

create index if not exists idx_announcement_status_published_at
  on public.announcement (announcement_status, published_at desc);

-- Administrators can retrieve drafts and published records. Tenants can only
-- retrieve active published records addressed to all tenants or to themselves.
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

create or replace function public.create_announcement(
  p_title text,
  p_content text,
  p_audience_scope text,
  p_audience_label text,
  p_publish boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  new_announcement_id uuid;
  normalized_title text := trim(coalesce(p_title, ''));
  normalized_content text := trim(coalesce(p_content, ''));
  normalized_audience_label text := trim(coalesce(p_audience_label, ''));
  target_group text;
  target_status text := case when p_publish then 'published' else 'draft' end;
begin
  if current_admin_id is null or not public.is_admin() then
    raise exception 'Only an active apartment administrator may create announcements.';
  end if;

  if normalized_title = '' or char_length(normalized_title) > 150 then
    raise exception 'Announcement title must contain between 1 and 150 characters.';
  end if;

  if normalized_content = '' or char_length(normalized_content) > 5000 then
    raise exception 'Announcement message must contain between 1 and 5000 characters.';
  end if;

  if p_audience_scope not in ('all_tenants', 'selected_units') then
    raise exception 'Unsupported announcement audience.';
  end if;

  if normalized_audience_label = '' then
    normalized_audience_label := case
      when p_audience_scope = 'all_tenants' then 'All tenants'
      else 'Selected units'
    end;
  end if;

  insert into public.announcement (
    created_by_admin_id,
    title,
    content,
    audience_scope,
    audience_label,
    published_at,
    announcement_status
  ) values (
    current_admin_id,
    normalized_title,
    normalized_content,
    p_audience_scope,
    normalized_audience_label,
    case when p_publish then now() else null end,
    target_status
  )
  returning announcement_id into new_announcement_id;

  target_group := trim(
    regexp_replace(normalized_audience_label, '\s+tenants$', '', 'i')
  );

  insert into public.announcement_recipient (
    announcement_id,
    tenant_id,
    delivery_status,
    delivered_at
  )
  select
    new_announcement_id,
    tenancy.tenant_id,
    case when p_publish then 'delivered' else 'pending' end,
    case when p_publish then now() else null end
  from public.tenancy tenancy
  join public.rental_unit rental_unit on rental_unit.unit_id = tenancy.unit_id
  where tenancy.tenancy_status = 'active'
    and (
      p_audience_scope = 'all_tenants'
      or lower(
        coalesce(nullif(rental_unit.block_and_floor, ''), rental_unit.unit_number)
      ) like '%' || lower(target_group) || '%'
    )
  on conflict (announcement_id, tenant_id) do nothing;

  insert into public.audit_log (
    actor_user_id,
    action_type,
    entity_type,
    entity_id,
    outcome,
    metadata
  ) values (
    current_admin_id,
    case when p_publish
      then 'announcement_published'
      else 'announcement_draft_saved'
    end,
    'announcement',
    new_announcement_id,
    'success',
    jsonb_build_object(
      'audience_scope', p_audience_scope,
      'audience_label', normalized_audience_label,
      'status', target_status
    )
  );

  return new_announcement_id;
end;
$$;

revoke all on function public.create_announcement(text, text, text, text, boolean)
from public, anon;
grant execute on function public.create_announcement(text, text, text, text, boolean)
to authenticated;


-- MIGRATION 20261123000007_tenant_edit_draft_announcements.sql
-- Allow administrators to revise an existing draft and either keep it as a
-- draft or publish it. Published announcements remain immutable in this flow.

create or replace function public.update_draft_announcement(
  p_announcement_id uuid,
  p_title text,
  p_content text,
  p_audience_scope text,
  p_audience_label text,
  p_publish boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  current_status text;
  normalized_title text := trim(coalesce(p_title, ''));
  normalized_content text := trim(coalesce(p_content, ''));
  normalized_audience_label text := trim(coalesce(p_audience_label, ''));
  target_group text;
  target_status text := case when p_publish then 'published' else 'draft' end;
begin
  if current_admin_id is null or not public.is_admin() then
    raise exception 'Only an active apartment administrator may edit announcements.';
  end if;

  if normalized_title = '' or char_length(normalized_title) > 150 then
    raise exception 'Announcement title must contain between 1 and 150 characters.';
  end if;

  if normalized_content = '' or char_length(normalized_content) > 5000 then
    raise exception 'Announcement message must contain between 1 and 5000 characters.';
  end if;

  if p_audience_scope not in ('all_tenants', 'selected_units') then
    raise exception 'Unsupported announcement audience.';
  end if;

  select announcement_status
  into current_status
  from public.announcement
  where announcement_id = p_announcement_id
  for update;

  if current_status is null then
    raise exception 'Announcement draft was not found.';
  end if;

  if current_status <> 'draft' then
    raise exception 'Only draft announcements may be modified.';
  end if;

  if normalized_audience_label = '' then
    normalized_audience_label := case
      when p_audience_scope = 'all_tenants' then 'All tenants'
      else 'Selected units'
    end;
  end if;

  update public.announcement
  set title = normalized_title,
      content = normalized_content,
      audience_scope = p_audience_scope,
      audience_label = normalized_audience_label,
      published_at = case when p_publish then now() else null end,
      announcement_status = target_status
  where announcement_id = p_announcement_id;

  delete from public.announcement_recipient
  where announcement_id = p_announcement_id;

  target_group := trim(
    regexp_replace(normalized_audience_label, '\s+tenants$', '', 'i')
  );

  insert into public.announcement_recipient (
    announcement_id,
    tenant_id,
    delivery_status,
    delivered_at
  )
  select
    p_announcement_id,
    tenancy.tenant_id,
    case when p_publish then 'delivered' else 'pending' end,
    case when p_publish then now() else null end
  from public.tenancy tenancy
  join public.rental_unit rental_unit on rental_unit.unit_id = tenancy.unit_id
  where tenancy.tenancy_status = 'active'
    and (
      p_audience_scope = 'all_tenants'
      or lower(
        coalesce(nullif(rental_unit.block_and_floor, ''), rental_unit.unit_number)
      ) like '%' || lower(target_group) || '%'
    )
  on conflict (announcement_id, tenant_id) do nothing;

  insert into public.audit_log (
    actor_user_id,
    action_type,
    entity_type,
    entity_id,
    outcome,
    metadata
  ) values (
    current_admin_id,
    case when p_publish
      then 'announcement_published'
      else 'announcement_draft_updated'
    end,
    'announcement',
    p_announcement_id,
    'success',
    jsonb_build_object(
      'audience_scope', p_audience_scope,
      'audience_label', normalized_audience_label,
      'status', target_status
    )
  );

  return p_announcement_id;
end;
$$;

revoke all on function public.update_draft_announcement(
  uuid,
  text,
  text,
  text,
  text,
  boolean
) from public, anon;
grant execute on function public.update_draft_announcement(
  uuid,
  text,
  text,
  text,
  text,
  boolean
) to authenticated;


-- MIGRATION 20261123000008_tenant_hide_pre_activation_announcements.sql
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
        and account.role = 'tenant'
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


-- MIGRATION 20261123000009_tenant_simulated_electricity_device_registration.sql
-- Metadata required to register both simulated and physical DDSU666 meters.

alter table public.electricity_device
  add column if not exists meter_serial_number varchar(80),
  add column if not exists communication_type varchar(30)
    not null default 'RS485 Modbus-RTU',
  add column if not exists modbus_slave_id int not null default 1,
  add column if not exists installation_date date not null default current_date,
  add column if not exists initial_cumulative_kwh numeric(14,6)
    not null default 0,
  add column if not exists data_source varchar(20)
    not null default 'simulated',
  add column if not exists last_seen_at timestamptz;

update public.electricity_device
set meter_serial_number = device_identifier
where meter_serial_number is null;

alter table public.electricity_device
  alter column meter_serial_number set not null;

alter table public.electricity_device
  drop constraint if exists electricity_device_modbus_slave_id_check,
  drop constraint if exists electricity_device_initial_kwh_check,
  drop constraint if exists electricity_device_data_source_check;

alter table public.electricity_device
  add constraint electricity_device_modbus_slave_id_check
    check (modbus_slave_id between 1 and 247),
  add constraint electricity_device_initial_kwh_check
    check (initial_cumulative_kwh >= 0),
  add constraint electricity_device_data_source_check
    check (data_source in ('simulated', 'physical'));

create unique index if not exists uq_electricity_device_serial_number
  on public.electricity_device (meter_serial_number);

create unique index if not exists uq_current_electricity_device_per_unit
  on public.electricity_device (unit_id)
  where device_status in ('pending', 'active', 'offline');

create or replace function public.audit_electricity_device_registration()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_log (
    actor_user_id,
    action_type,
    entity_type,
    entity_id,
    outcome,
    metadata
  ) values (
    new.registered_by_admin_id,
    'ELECTRICITY_DEVICE_REGISTERED',
    'electricity_device',
    new.device_id,
    'success',
    jsonb_build_object(
      'device_identifier', new.device_identifier,
      'meter_serial_number', new.meter_serial_number,
      'unit_id', new.unit_id,
      'data_source', new.data_source,
      'device_status', new.device_status
    )
  );

  return new;
end;
$$;

drop trigger if exists trg_audit_electricity_device_registration
  on public.electricity_device;
create trigger trg_audit_electricity_device_registration
after insert on public.electricity_device
for each row execute function public.audit_electricity_device_registration();


-- MIGRATION 20261123000010_tenant_meter_ingestion_evidence.sql
-- Evidence retained for simulated ingestion and backend-validation tests.

alter table public.electricity_reading
  add column if not exists ingestion_source varchar(30)
    not null default 'legacy_or_seed',
  add column if not exists ingestion_run_id varchar(80),
  add column if not exists raw_payload jsonb not null default '{}'::jsonb;

alter table public.electricity_reading
  drop constraint if exists electricity_reading_ingestion_source_check;

alter table public.electricity_reading
  add constraint electricity_reading_ingestion_source_check
    check (ingestion_source in (
      'legacy_or_seed',
      'admin_dataset_test',
      'esp32_physical'
    ));

create index if not exists ix_electricity_reading_ingestion_run
  on public.electricity_reading (ingestion_run_id)
  where ingestion_run_id is not null;


-- MIGRATION 20261123000011_tenant_electricity_reading_realtime.sql
-- Allow authenticated clients to receive new electricity readings through
-- Supabase Realtime. Existing row-level-security policies still determine
-- which records each administrator or tenant may read.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'electricity_reading'
  ) then
    alter publication supabase_realtime
      add table public.electricity_reading;
  end if;
end
$$;


-- MIGRATION 20261123000012_tenant_maintenance_workflow_storage_and_status_rpc.sql
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'maintenance-request-images',
  'maintenance-request-images',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.is_allowed_maintenance_image(file_path text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select lower(coalesce(file_path, '')) ~ '\.(jpe?g|png|webp|heic|heif)$';
$$;

revoke all on function public.is_allowed_maintenance_image(text)
from public, anon;
grant execute on function public.is_allowed_maintenance_image(text)
to authenticated;

drop policy if exists maintenance_images_select on storage.objects;
create policy maintenance_images_select
on storage.objects for select to authenticated
using (
  bucket_id = 'maintenance-request-images'
  and (
    public.is_admin()
    or exists (
      select 1
      from public.maintenance_request m
      join public.tenancy t on t.tenancy_id = m.tenancy_id
      where m.image_storage_path = name
        and t.tenant_id = (select auth.uid())
    )
  )
);

drop policy if exists maintenance_images_insert on storage.objects;
create policy maintenance_images_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'maintenance-request-images'
  and public.is_allowed_maintenance_image(name)
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1
    from public.maintenance_request m
    join public.tenancy t on t.tenancy_id = m.tenancy_id
    where m.maintenance_id::text = (storage.foldername(name))[2]
      and t.tenant_id = (select auth.uid())
  )
);

drop policy if exists maintenance_images_delete on storage.objects;
create policy maintenance_images_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'maintenance-request-images'
  and (
    public.is_admin()
    or (storage.foldername(name))[1] = (select auth.uid())::text
  )
);

create or replace function public.update_maintenance_request_status(
  p_maintenance_id uuid,
  p_new_status varchar,
  p_remarks text default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  previous_status varchar(20);
begin
  if not public.is_admin() then
    raise exception 'Only an apartment administrator can update a maintenance request.';
  end if;

  if p_new_status not in ('in_progress', 'resolved', 'rejected') then
    raise exception 'The selected maintenance status is invalid.';
  end if;

  select request_status into previous_status
  from public.maintenance_request
  where maintenance_id = p_maintenance_id
  for update;

  if previous_status is null then
    raise exception 'Maintenance request not found.';
  end if;

  update public.maintenance_request
  set request_status = p_new_status,
      assigned_admin_id = current_admin_id,
      resolved_at = case
        when p_new_status = 'resolved' then coalesce(resolved_at, now())
        else null
      end
  where maintenance_id = p_maintenance_id;

  insert into public.maintenance_update (
    maintenance_id, updated_by_admin_id, old_status, new_status, remarks
  ) values (
    p_maintenance_id, current_admin_id, previous_status, p_new_status,
    nullif(trim(p_remarks), '')
  );
end;
$$;

revoke all on function public.update_maintenance_request_status(uuid, varchar, text)
from public, anon;
grant execute on function public.update_maintenance_request_status(uuid, varchar, text)
to authenticated;


-- MIGRATION 20261123000013_tenant_simplify_maintenance_statuses.sql
-- Collapse the previous intermediate and closed states into the simpler
-- maintenance lifecycle used by the application.
update public.maintenance_request
set request_status = case request_status
  when 'under_review' then 'submitted'
  when 'closed' then 'resolved'
  else request_status
end
where request_status in ('under_review', 'closed');

update public.maintenance_update
set old_status = case old_status
      when 'under_review' then 'submitted'
      when 'closed' then 'resolved'
      else old_status
    end,
    new_status = case new_status
      when 'under_review' then 'submitted'
      when 'closed' then 'resolved'
      else new_status
    end
where old_status in ('under_review', 'closed')
   or new_status in ('under_review', 'closed');

alter table public.maintenance_request
  drop constraint if exists maintenance_request_request_status_check;

alter table public.maintenance_request
  add constraint maintenance_request_request_status_check
  check (request_status in ('submitted', 'in_progress', 'resolved', 'rejected'));

create or replace function public.update_maintenance_request_status(
  p_maintenance_id uuid,
  p_new_status varchar,
  p_remarks text default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_admin_id uuid := (select auth.uid());
  previous_status varchar(20);
begin
  if not public.is_admin() then
    raise exception 'Only an apartment administrator can update a maintenance request.';
  end if;

  if p_new_status not in ('in_progress', 'resolved', 'rejected') then
    raise exception 'The selected maintenance status is invalid.';
  end if;

  select request_status into previous_status
  from public.maintenance_request
  where maintenance_id = p_maintenance_id
  for update;

  if previous_status is null then
    raise exception 'Maintenance request not found.';
  end if;

  update public.maintenance_request
  set request_status = p_new_status,
      assigned_admin_id = current_admin_id,
      resolved_at = case
        when p_new_status = 'resolved' then coalesce(resolved_at, now())
        else null
      end
  where maintenance_id = p_maintenance_id;

  insert into public.maintenance_update (
    maintenance_id, updated_by_admin_id, old_status, new_status, remarks
  ) values (
    p_maintenance_id, current_admin_id, previous_status, p_new_status,
    nullif(trim(p_remarks), '')
  );
end;
$$;

revoke all on function public.update_maintenance_request_status(uuid, varchar, text)
from public, anon;
grant execute on function public.update_maintenance_request_status(uuid, varchar, text)
to authenticated;


-- MIGRATION 20261123000014_owner_core_booking.sql
create temporary table integration_tenant_functions on commit drop as select oid from pg_proc where pronamespace='public'::regnamespace;
-- Core Owner/Provider booking schema. Review in a disposable Supabase project
-- before deployment; this repository does not currently connect to a project.
-- Time-of-day rules use Asia/Kuala_Lumpur as specified by the FYP report.

create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;
set search_path = public, extensions;


create type public.booking_status_enum as enum
  ('Pending', 'Accepted', 'In Progress', 'Completed', 'Declined', 'Cancelled');



create table public.property (
  property_id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.user_account(user_id),
  unit_name text not null,
  building_name text not null,
  address text not null,
  cleaning_window_start time not null default time '08:00',
  cleaning_window_end time not null default time '18:00',
  created_at timestamptz not null default now(),
  constraint property_window_order
    check (cleaning_window_end > cleaning_window_start),
  constraint property_owner_unit_unique
    unique (owner_id, building_name, unit_name)
);

create table public.provider_profile (
  provider_id uuid primary key references public.user_account(user_id),
  bio text,
  service_area text not null,
  service_origin_address text not null,
  hourly_rate numeric(10,2),
  daily_rate numeric(10,2),
  approval_status text not null default 'pending',
  rating_average numeric(3,2),
  completed_job_count integer not null default 0,
  constraint provider_rate_nonnegative
    check ((hourly_rate is null or hourly_rate >= 0)
       and (daily_rate is null or daily_rate >= 0)),
  constraint provider_has_rate
    check (hourly_rate is not null or daily_rate is not null),
  constraint provider_rating_range
    check (rating_average is null or rating_average between 1 and 5),
  constraint provider_completed_count_nonnegative
    check (completed_job_count >= 0)
);

create table public.service_type (
  service_type_id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text
);

create table public.provider_capability (
  provider_id uuid not null references public.provider_profile(provider_id)
    on delete cascade,
  service_type_id uuid not null references public.service_type(service_type_id),
  primary key (provider_id, service_type_id)
);

-- Weekly slots and whole-day exceptions are the authoritative availability
-- inputs. Alternative cleaning windows are calculated, never stored.
create table public.provider_weekly_slot (
  slot_id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profile(provider_id)
    on delete cascade,
  weekday integer not null check (weekday between 1 and 7),
  start_time time not null,
  end_time time not null,
  constraint provider_slot_order check (end_time > start_time),
  constraint provider_slot_unique
    unique (provider_id, weekday, start_time, end_time)
);

create table public.provider_unavailable_date (
  provider_id uuid not null references public.provider_profile(provider_id)
    on delete cascade,
  unavailable_on date not null,
  primary key (provider_id, unavailable_on)
);

create table public.booking (
  booking_id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.user_account(user_id),
  provider_id uuid not null references public.provider_profile(provider_id),
  property_id uuid not null references public.property(property_id),
  service_type_id uuid not null references public.service_type(service_type_id),
  requested_start_at timestamptz not null,
  requested_end_at timestamptz not null,
  instructions text not null default '',
  current_status public.booking_status_enum not null default 'Pending',
  created_at timestamptz not null default now(),
  constraint booking_interval_order
    check (requested_end_at > requested_start_at)
);

-- Database backstop for half-open intervals. Pending does not block capacity.
alter table public.booking add constraint booking_no_confirmed_overlap
  exclude using gist (
    provider_id with =,
    tstzrange(requested_start_at, requested_end_at, '[)') with &&
  ) where (current_status in ('Accepted', 'In Progress'));

create index booking_owner_idx on public.booking(owner_id, created_at desc);
create index booking_provider_idx
  on public.booking(provider_id, requested_start_at);

create table public.booking_status_history (
  status_history_id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.booking(booking_id)
    on delete cascade,
  changed_by_user_id uuid not null references public.user_account(user_id),
  previous_status public.booking_status_enum,
  new_status public.booking_status_enum not null,
  change_reason text,
  changed_at timestamptz not null default now()
);
create index booking_status_history_booking_idx
  on public.booking_status_history(booking_id, changed_at);

alter table public.user_account enable row level security;
alter table public.property enable row level security;
alter table public.provider_profile enable row level security;
alter table public.service_type enable row level security;
alter table public.provider_capability enable row level security;
alter table public.provider_weekly_slot enable row level security;
alter table public.provider_unavailable_date enable row level security;
alter table public.booking enable row level security;
alter table public.booking_status_history enable row level security;

create policy account_self_read on public.user_account for select
  to authenticated using ((select auth.uid()) = user_id);
create policy account_self_insert on public.user_account for insert
  to authenticated with check (
    (select auth.uid()) = user_id and
    lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
create policy account_self_update on public.user_account for update
  to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy property_owner_read on public.property for select
  to authenticated using ((select auth.uid()) = owner_id);
create policy property_owner_insert on public.property for insert
  to authenticated with check (
    (select auth.uid()) = owner_id and
    exists (select 1 from public.user_account a
            where a.user_id = owner_id and a.role = 'owner')
  );
create policy property_owner_update on public.property for update
  to authenticated using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy provider_profile_read on public.provider_profile for select
  to authenticated using (true);
create policy provider_profile_insert on public.provider_profile for insert
  to authenticated with check (
    (select auth.uid()) = provider_id and
    exists (select 1 from public.user_account a
            where a.user_id = provider_id and a.role = 'provider')
  );
create policy provider_profile_update on public.provider_profile for update
  to authenticated using ((select auth.uid()) = provider_id)
  with check ((select auth.uid()) = provider_id);

create policy service_type_read on public.service_type for select
  to authenticated using (true);
create policy capability_read on public.provider_capability for select
  to authenticated using (true);
create policy capability_provider_insert on public.provider_capability for insert
  to authenticated with check ((select auth.uid()) = provider_id);
create policy capability_provider_delete on public.provider_capability for delete
  to authenticated using ((select auth.uid()) = provider_id);

create policy weekly_slot_read on public.provider_weekly_slot for select
  to authenticated using (true);
create policy weekly_slot_insert on public.provider_weekly_slot for insert
  to authenticated with check ((select auth.uid()) = provider_id);
create policy weekly_slot_update on public.provider_weekly_slot for update
  to authenticated using ((select auth.uid()) = provider_id)
  with check ((select auth.uid()) = provider_id);
create policy weekly_slot_delete on public.provider_weekly_slot for delete
  to authenticated using ((select auth.uid()) = provider_id);

create policy unavailable_date_read on public.provider_unavailable_date
  for select to authenticated using (true);
create policy unavailable_date_insert on public.provider_unavailable_date
  for insert to authenticated with check ((select auth.uid()) = provider_id);
create policy unavailable_date_delete on public.provider_unavailable_date
  for delete to authenticated using ((select auth.uid()) = provider_id);

create policy booking_participant_read on public.booking for select
  to authenticated using (
    (select auth.uid()) = owner_id or (select auth.uid()) = provider_id
  );
create policy booking_owner_insert on public.booking for insert
  to authenticated with check (
    (select auth.uid()) = owner_id and current_status = 'Pending' and
    exists (select 1 from public.property p
            where p.property_id = public.booking.property_id and
                  p.owner_id = public.booking.owner_id)
  );
create policy booking_owner_update on public.booking for update
  to authenticated using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy booking_history_participant_read
  on public.booking_status_history for select to authenticated
  using (exists (
    select 1 from public.booking b
    where b.booking_id = public.booking_status_history.booking_id and
      (b.owner_id = (select auth.uid()) or
       b.provider_id = (select auth.uid()))
  ));

-- The first Pending history row is inserted together with the request.
create function public.record_initial_booking_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.booking_status_history
    (booking_id, changed_by_user_id, previous_status, new_status)
  values (new.booking_id, new.owner_id, null, 'Pending');
  return new;
end;
$$;
create trigger record_initial_booking_status_after
after insert on public.booking for each row
execute function public.record_initial_booking_status();

-- Self-managed account/profile fields must not let a client change its role,
-- approve itself, or forge computed provider statistics.
create function public.guard_account_client_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    new.user_id is distinct from old.user_id or
    new.role is distinct from old.role or
    new.email is distinct from old.email
  ) then
    raise exception 'Account identity and role cannot be edited directly'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard_account_client_update_before
before update on public.user_account for each row
execute function public.guard_account_client_update();

create function public.guard_property_client_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    new.property_id is distinct from old.property_id or
    new.owner_id is distinct from old.owner_id or
    new.created_at is distinct from old.created_at
  ) then
    raise exception 'Property identity cannot be edited directly'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard_property_client_update_before
before update on public.property for each row
execute function public.guard_property_client_update();

create function public.guard_provider_profile_client_write()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    (tg_op = 'INSERT' and (
      new.approval_status <> 'pending' or
      new.rating_average is not null or
      new.completed_job_count <> 0
    )) or
    (tg_op = 'UPDATE' and (
      new.provider_id is distinct from old.provider_id or
      new.approval_status is distinct from old.approval_status or
      new.rating_average is distinct from old.rating_average or
      new.completed_job_count is distinct from old.completed_job_count
    ))
  ) then
    raise exception 'Provider approval and statistics are system-managed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard_provider_profile_client_write_before
before insert or update on public.provider_profile for each row
execute function public.guard_provider_profile_client_write();

-- Direct client updates may change instructions only. Transition and interval
-- changes must go through server functions with a protected lock order.
create function public.guard_booking_client_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    new.booking_id is distinct from old.booking_id or
    new.owner_id is distinct from old.owner_id or
    new.provider_id is distinct from old.provider_id or
    new.property_id is distinct from old.property_id or
    new.service_type_id is distinct from old.service_type_id or
    new.requested_start_at is distinct from old.requested_start_at or
    new.requested_end_at is distinct from old.requested_end_at or
    new.current_status is distinct from old.current_status or
    new.created_at is distinct from old.created_at
  ) then
    raise exception 'Use an authorised booking operation'
      using errcode = '42501';
  end if;
  if current_user <> 'postgres' and old.current_status <> 'Pending' then
    raise exception 'Only a Pending request can be edited'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger guard_booking_client_update_before
before update on public.booking for each row
execute function public.guard_booking_client_update();

-- Serialise provider availability changes with acceptance checks. For slot
-- edits, modifying provider_id itself is forbidden to preserve the lock key.
create function public.lock_provider_availability_change()
returns trigger language plpgsql set search_path = '' as $$
declare v_provider_id uuid;
begin
  if tg_op = 'DELETE' then
    v_provider_id := old.provider_id;
  else
    v_provider_id := new.provider_id;
  end if;
  if tg_op = 'UPDATE' and new.provider_id <> old.provider_id then
    raise exception 'Availability slot provider cannot change';
  end if;
  perform 1 from public.provider_profile
    where provider_id = v_provider_id for update;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger lock_weekly_slot_before
before insert or update or delete on public.provider_weekly_slot
for each row execute function public.lock_provider_availability_change();
create trigger lock_unavailable_date_before
before insert or delete on public.provider_unavailable_date
for each row execute function public.lock_provider_availability_change();

-- A provider may change future availability, but not in a way that invalidates
-- an already confirmed future booking. The preceding trigger holds the same
-- provider lock used by acceptance until the availability transaction ends.
create function public.check_confirmed_after_availability_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_provider_id uuid;
  v_booking record;
  v_start timestamp;
  v_end timestamp;
begin
  if tg_op = 'DELETE' then
    v_provider_id := old.provider_id;
  else
    v_provider_id := new.provider_id;
  end if;
  for v_booking in
    select b.requested_start_at, b.requested_end_at
    from public.booking b
    where b.provider_id = v_provider_id and
          b.current_status in ('Accepted', 'In Progress') and
          b.requested_end_at > now()
  loop
    v_start := v_booking.requested_start_at at time zone 'Asia/Kuala_Lumpur';
    v_end := v_booking.requested_end_at at time zone 'Asia/Kuala_Lumpur';
    if exists (
      select 1 from public.provider_unavailable_date d
      where d.provider_id = v_provider_id and
            d.unavailable_on = v_start::date
    ) or not exists (
      select 1 from public.provider_weekly_slot s
      where s.provider_id = v_provider_id and
            s.weekday = extract(isodow from v_start)::integer and
            s.start_time <= v_start::time and
            s.end_time >= v_end::time
    ) then
      raise exception 'Availability change conflicts with a confirmed booking'
        using errcode = '23514';
    end if;
  end loop;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger check_confirmed_weekly_slot_after
after insert or update or delete on public.provider_weekly_slot
for each row execute function public.check_confirmed_after_availability_change();
create trigger check_confirmed_unavailable_date_after
after insert or delete on public.provider_unavailable_date
for each row execute function public.check_confirmed_after_availability_change();

-- Property window edits must serialise with acceptance of requests for this
-- property. Provider locks are acquired in a stable order.
create function public.lock_property_window_change()
returns trigger language plpgsql set search_path = '' as $$
declare v_provider_id uuid;
begin
  if new.cleaning_window_start is distinct from old.cleaning_window_start or
     new.cleaning_window_end is distinct from old.cleaning_window_end then
    for v_provider_id in
      select distinct b.provider_id from public.booking b
      where b.property_id = old.property_id and
            b.current_status in ('Pending', 'Accepted', 'In Progress')
      order by b.provider_id
    loop
      perform 1 from public.provider_profile
      where provider_id = v_provider_id for update;
    end loop;
    if exists (
      select 1 from public.booking b
      where b.property_id = old.property_id and
            b.current_status in ('Accepted', 'In Progress') and
            b.requested_end_at > now() and
            (
              (b.requested_start_at at time zone 'Asia/Kuala_Lumpur')::time
                < new.cleaning_window_start or
              (b.requested_end_at at time zone 'Asia/Kuala_Lumpur')::time
                > new.cleaning_window_end
            )
    ) then
      raise exception 'Cleaning window change conflicts with a confirmed booking'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger lock_property_window_before
before update on public.property for each row
execute function public.lock_property_window_change();

-- Authenticated provider only. PostgreSQL executes the function call in one
-- transaction. Lock provider first, then booking, then re-read current data.
create function public.accept_pending_booking(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_provider_id uuid;
  v_booking public.booking%rowtype;
  v_property public.property%rowtype;
  v_local_start timestamp;
  v_local_end timestamp;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select b.provider_id into v_provider_id from public.booking b
  where b.booking_id = p_booking_id;
  if v_provider_id is null or v_provider_id <> v_actor then
    raise exception 'Booking is not assigned to this provider'
      using errcode = '42501';
  end if;

  perform 1 from public.provider_profile p
  where p.provider_id = v_provider_id for update;
  select * into v_booking from public.booking b
  where b.booking_id = p_booking_id for update;
  if not found or v_booking.provider_id <> v_actor or
     v_booking.current_status <> 'Pending' then
    return jsonb_build_object('accepted', false, 'reason', 'not_pending');
  end if;

  select * into v_property from public.property p
  where p.property_id = v_booking.property_id;
  if not found or v_property.owner_id <> v_booking.owner_id then
    return jsonb_build_object('accepted', false, 'reason', 'property');
  end if;

  v_local_start := v_booking.requested_start_at at time zone 'Asia/Kuala_Lumpur';
  v_local_end := v_booking.requested_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_booking.requested_start_at <= now() or
     v_local_start::date <> v_local_end::date or
     v_local_start::time < v_property.cleaning_window_start or
     v_local_end::time > v_property.cleaning_window_end then
    return jsonb_build_object('accepted', false, 'reason', 'rental_window');
  end if;

  if exists (
    select 1 from public.provider_unavailable_date d
    where d.provider_id = v_provider_id and
          d.unavailable_on = v_local_start::date
  ) or not exists (
    select 1 from public.provider_weekly_slot s
    where s.provider_id = v_provider_id and
          s.weekday = extract(isodow from v_local_start)::integer and
          s.start_time <= v_local_start::time and
          s.end_time >= v_local_end::time
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'availability');
  end if;

  if not exists (
    select 1 from public.provider_capability c
    where c.provider_id = v_provider_id and
          c.service_type_id = v_booking.service_type_id
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'service_type');
  end if;

  if exists (
    select 1 from public.booking other
    where other.provider_id = v_provider_id and
          other.booking_id <> p_booking_id and
          other.current_status in ('Accepted', 'In Progress') and
          other.requested_start_at < v_booking.requested_end_at and
          v_booking.requested_start_at < other.requested_end_at
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'slot_conflict');
  end if;

  update public.booking set current_status = 'Accepted'
  where booking_id = p_booking_id;
  insert into public.booking_status_history
    (booking_id, changed_by_user_id, previous_status, new_status)
  values (p_booking_id, v_actor, 'Pending', 'Accepted');
  return jsonb_build_object('accepted', true, 'status', 'Accepted');
end;
$$;

revoke execute on function public.accept_pending_booking(uuid)
  from public, anon;
grant execute on function public.accept_pending_booking(uuid)
  to authenticated;
revoke execute on function public.guard_booking_client_update()
  from public, anon, authenticated;
revoke execute on function public.lock_provider_availability_change()
  from public, anon, authenticated;
revoke execute on function public.lock_property_window_change()
  from public, anon, authenticated;
revoke execute on function public.guard_account_client_update()
  from public, anon, authenticated;
revoke execute on function public.guard_provider_profile_client_write()
  from public, anon, authenticated;
revoke execute on function public.guard_property_client_update()
  from public, anon, authenticated;
revoke execute on function public.record_initial_booking_status()
  from public, anon, authenticated;
revoke execute on function public.check_confirmed_after_availability_change()
  from public, anon, authenticated;


-- MIGRATION 20261123000015_owner_lifecycle_evidence_realtime.sql
-- Apply only after 202609270001_core_booking.sql in a disposable project.
-- This remains unverified until PostgreSQL/RLS integration tests run.

alter table public.property
  add column bedrooms integer not null default 1 check (bedrooms > 0),
  add column size_sqft integer not null default 1 check (size_sqft > 0);

create table public.booking_evidence (
  booking_id uuid primary key references public.booking(booking_id)
    on delete cascade,
  before_path text,
  after_path text,
  completion_remarks text not null default '',
  updated_at timestamptz not null default now(),
  constraint evidence_before_in_booking_folder check (
    before_path is null or before_path like booking_id::text || '/%'
  ),
  constraint evidence_after_in_booking_folder check (
    after_path is null or after_path like booking_id::text || '/%'
  )
);

alter table public.booking_evidence enable row level security;
create policy evidence_participant_read on public.booking_evidence
  for select to authenticated using (exists (
    select 1 from public.booking b
    where b.booking_id = booking_evidence.booking_id and
      (b.owner_id = (select auth.uid()) or
       b.provider_id = (select auth.uid()))
  ));
create policy evidence_provider_insert on public.booking_evidence
  for insert to authenticated with check (exists (
    select 1 from public.booking b
    where b.booking_id = booking_evidence.booking_id and
      b.provider_id = (select auth.uid()) and
      b.current_status in ('Accepted', 'In Progress')
  ));
create policy evidence_provider_update on public.booking_evidence
  for update to authenticated
  using (exists (
    select 1 from public.booking b
    where b.booking_id = booking_evidence.booking_id and
      b.provider_id = (select auth.uid()) and
      b.current_status in ('Accepted', 'In Progress')
  ))
  with check (exists (
    select 1 from public.booking b
    where b.booking_id = booking_evidence.booking_id and
      b.provider_id = (select auth.uid()) and
      b.current_status in ('Accepted', 'In Progress')
  ));

insert into storage.buckets
  (id, name, public, file_size_limit, allowed_mime_types)
values
  ('cleaning-evidence', 'cleaning-evidence', false, 5242880,
   array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

-- Object names have the form booking_id/random_name.jpg or .png.
-- Only the assigned provider may upload while the booking is active.
create policy evidence_object_provider_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'cleaning-evidence' and
    lower(storage.extension(name)) in ('jpg', 'jpeg', 'png') and
    exists (
      select 1 from public.booking b
      where b.booking_id::text = (storage.foldername(name))[1] and
        b.provider_id = (select auth.uid()) and
        b.current_status in ('Accepted', 'In Progress')
    )
  );
create policy evidence_object_participant_read on storage.objects
  for select to authenticated using (
    bucket_id = 'cleaning-evidence' and
    exists (
      select 1 from public.booking b
      where b.booking_id::text = (storage.foldername(name))[1] and
        (b.owner_id = (select auth.uid()) or
         b.provider_id = (select auth.uid()))
    )
  );

-- The accepted transition is deliberately excluded: only
-- accept_pending_booking performs its atomic availability recheck.
create function public.transition_booking(
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
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select b.provider_id into v_provider_id from public.booking b
  where b.booking_id = p_booking_id;
  if v_provider_id is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;

  -- Match the provider-then-booking lock order of acceptance.
  perform 1 from public.provider_profile p
    where p.provider_id = v_provider_id for update;
  select * into v_booking from public.booking b
    where b.booking_id = p_booking_id for update;

  if not (
    (v_booking.current_status = 'Pending' and
      p_new_status = 'Declined' and v_actor = v_booking.provider_id) or
    (v_booking.current_status = 'Pending' and
      p_new_status = 'Cancelled' and v_actor = v_booking.owner_id) or
    (v_booking.current_status = 'Accepted' and
      p_new_status = 'In Progress' and v_actor = v_booking.provider_id) or
    (v_booking.current_status = 'In Progress' and
      p_new_status = 'Completed' and v_actor = v_booking.provider_id)
  ) then
    raise exception 'Transition or actor is not permitted'
      using errcode = '42501';
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
          nullif(btrim(p_reason), ''));
  return jsonb_build_object('status', p_new_status::text);
end;
$$;
revoke execute on function public.transition_booking(
  uuid, public.booking_status_enum, text) from public, anon;
grant execute on function public.transition_booking(
  uuid, public.booking_status_enum, text) to authenticated;

-- Revisions keep the state Pending and recheck the latest restrictions.
-- A failed revision leaves the original interval unchanged.
create function public.revise_pending_booking(
  p_booking_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_instructions text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_provider_id uuid;
  v_booking public.booking%rowtype;
  v_property public.property%rowtype;
  v_start timestamp;
  v_end timestamp;
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
  if v_booking.owner_id <> v_actor or
     v_booking.current_status <> 'Pending' then
    raise exception 'Only the owner can revise a Pending booking'
      using errcode = '42501';
  end if;
  if p_start_at is null or p_end_at is null or
     p_start_at <= now() or p_end_at <= p_start_at then
    return jsonb_build_object('revised', false, 'reason', 'invalid_interval');
  end if;
  select * into v_property from public.property p
    where p.property_id = v_booking.property_id;
  v_start := p_start_at at time zone 'Asia/Kuala_Lumpur';
  v_end := p_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_start::date <> v_end::date or
     v_start::time < v_property.cleaning_window_start or
     v_end::time > v_property.cleaning_window_end then
    return jsonb_build_object('revised', false, 'reason', 'rental_window');
  end if;
  if exists (
    select 1 from public.provider_unavailable_date d
    where d.provider_id = v_provider_id and
          d.unavailable_on = v_start::date
  ) or not exists (
    select 1 from public.provider_weekly_slot s
    where s.provider_id = v_provider_id and
          s.weekday = extract(isodow from v_start)::integer and
          s.start_time <= v_start::time and
          s.end_time >= v_end::time
  ) then
    return jsonb_build_object('revised', false, 'reason', 'availability');
  end if;
  if not exists (
    select 1 from public.provider_capability c
    where c.provider_id = v_provider_id and
          c.service_type_id = v_booking.service_type_id
  ) then
    return jsonb_build_object('revised', false, 'reason', 'service_type');
  end if;
  if exists (
    select 1 from public.booking other
    where other.provider_id = v_provider_id and
          other.booking_id <> p_booking_id and
          other.current_status in ('Accepted', 'In Progress') and
          other.requested_start_at < p_end_at and
          p_start_at < other.requested_end_at
  ) then
    return jsonb_build_object('revised', false, 'reason', 'slot_conflict');
  end if;
  update public.booking
    set requested_start_at = p_start_at,
        requested_end_at = p_end_at,
        instructions = coalesce(p_instructions, '')
    where booking_id = p_booking_id;
  return jsonb_build_object('revised', true, 'status', 'Pending');
end;
$$;
revoke execute on function public.revise_pending_booking(
  uuid, timestamptz, timestamptz, text) from public, anon;
grant execute on function public.revise_pending_booking(
  uuid, timestamptz, timestamptz, text) to authenticated;

-- New tables are not automatically published for Realtime.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and
            schemaname = 'public' and tablename = 'booking'
    ) then
      alter publication supabase_realtime add table public.booking;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and
            schemaname = 'public' and tablename = 'booking_status_history'
    ) then
      alter publication supabase_realtime add table public.booking_status_history;
    end if;
  end if;
end;
$$;


-- MIGRATION 20261123000016_owner_cancel_before_start.sql
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


-- MIGRATION 20261123000017_owner_provider_setup.sql
-- Connected provider setup. Apply only after reviewing existing live rows.
-- The service catalogue follows the five names already used in the app.
insert into public.service_type (name, description) values
  ('Standard cleaning', 'Routine cleaning of a rental unit.'),
  ('Deep cleaning', 'Detailed cleaning of a rental unit.'),
  ('Move-in cleaning', 'Cleaning before a tenant moves in.'),
  ('Move-out cleaning', 'Cleaning after a tenant moves out.'),
  ('Window cleaning', 'Cleaning of accessible windows.')
on conflict (name) do nothing;

-- Existing short slots are left untouched for explicit review, while every
-- new or edited slot must cover at least two hours.
alter table public.provider_weekly_slot
  add constraint provider_slot_minimum_two_hours
  check (end_time - start_time >= interval '2 hours') not valid;

create function public.validate_provider_weekly_slot()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Serialise concurrent edits for one provider before checking overlap.
  perform 1 from public.provider_profile p
    where p.provider_id = new.provider_id for update;
  if exists (
    select 1 from public.provider_weekly_slot s
    where s.provider_id = new.provider_id and s.weekday = new.weekday and
          s.slot_id <> new.slot_id and
          s.start_time < new.end_time and new.start_time < s.end_time
  ) then
    raise exception 'Working slots for one day cannot overlap'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger z_validate_provider_weekly_slot_before
before insert or update on public.provider_weekly_slot
for each row execute function public.validate_provider_weekly_slot();
revoke execute on function public.validate_provider_weekly_slot()
  from public, anon, authenticated;

-- Replace the provider's service types in one transaction. Direct client
-- inserts/deletes are removed so a partial multi-request save cannot leave
-- an unintended capability set.
drop policy if exists capability_provider_insert on public.provider_capability;
drop policy if exists capability_provider_delete on public.provider_capability;
create function public.replace_provider_capabilities(p_service_type_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_count integer;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_service_type_ids is null or cardinality(p_service_type_ids) = 0 or
     array_position(p_service_type_ids, null) is not null then
    raise exception 'Select at least one valid service type'
      using errcode = '23514';
  end if;
  perform 1 from public.provider_profile p
    where p.provider_id = v_actor for update;
  if not found then
    raise exception 'Provider profile is required'
      using errcode = '42501';
  end if;
  select count(*) into v_count from public.service_type s
    where s.service_type_id = any(p_service_type_ids);
  if v_count <> (select count(distinct x.service_type_id)
                  from unnest(p_service_type_ids) as x(service_type_id))
  then
    raise exception 'Unknown service type' using errcode = '23514';
  end if;

  if exists (
    select 1 from public.booking b
    where b.provider_id = v_actor and
          b.current_status in ('Accepted', 'In Progress') and
          b.requested_end_at > now() and
          not (b.service_type_id = any(p_service_type_ids))
  ) then
    raise exception 'A confirmed job still requires this service type'
      using errcode = '23514';
  end if;

  delete from public.provider_capability c
    where c.provider_id = v_actor and
          not (c.service_type_id = any(p_service_type_ids));
  insert into public.provider_capability(provider_id, service_type_id)
    select v_actor, x.service_type_id
      from unnest(p_service_type_ids) as x(service_type_id)
    on conflict (provider_id, service_type_id) do nothing;
  return v_count;
end;
$$;
revoke execute on function public.replace_provider_capabilities(uuid[])
  from public, anon;
grant execute on function public.replace_provider_capabilities(uuid[])
  to authenticated;

-- Acceptance remains one protected transaction. Approval is a hard filter,
-- never a ranking score or a decision made only by the mobile client.
create or replace function public.accept_pending_booking(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_provider_id uuid;
  v_approval_status text;
  v_booking public.booking%rowtype;
  v_property public.property%rowtype;
  v_local_start timestamp;
  v_local_end timestamp;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select b.provider_id into v_provider_id from public.booking b
    where b.booking_id = p_booking_id;
  if v_provider_id is null or v_provider_id <> v_actor then
    raise exception 'Booking is not assigned to this provider'
      using errcode = '42501';
  end if;

  select p.approval_status into v_approval_status
    from public.provider_profile p
    where p.provider_id = v_provider_id for update;
  if v_approval_status is distinct from 'approved' then
    return jsonb_build_object('accepted', false,
                              'reason', 'provider_not_approved');
  end if;
  select * into v_booking from public.booking b
    where b.booking_id = p_booking_id for update;
  if not found or v_booking.provider_id <> v_actor or
     v_booking.current_status <> 'Pending' then
    return jsonb_build_object('accepted', false, 'reason', 'not_pending');
  end if;

  select * into v_property from public.property p
    where p.property_id = v_booking.property_id;
  if not found or v_property.owner_id <> v_booking.owner_id then
    return jsonb_build_object('accepted', false, 'reason', 'property');
  end if;
  v_local_start := v_booking.requested_start_at at time zone 'Asia/Kuala_Lumpur';
  v_local_end := v_booking.requested_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_booking.requested_start_at <= now() or
     v_local_start::date <> v_local_end::date or
     v_local_start::time < v_property.cleaning_window_start or
     v_local_end::time > v_property.cleaning_window_end then
    return jsonb_build_object('accepted', false, 'reason', 'rental_window');
  end if;

  if exists (
    select 1 from public.provider_unavailable_date d
    where d.provider_id = v_provider_id and
          d.unavailable_on = v_local_start::date
  ) or not exists (
    select 1 from public.provider_weekly_slot s
    where s.provider_id = v_provider_id and
          s.weekday = extract(isodow from v_local_start)::integer and
          s.end_time - s.start_time >= interval '2 hours' and
          s.start_time <= v_local_start::time and
          s.end_time >= v_local_end::time
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'availability');
  end if;
  if not exists (
    select 1 from public.provider_capability c
    where c.provider_id = v_provider_id and
          c.service_type_id = v_booking.service_type_id
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'service_type');
  end if;
  if exists (
    select 1 from public.booking other
    where other.provider_id = v_provider_id and
          other.booking_id <> p_booking_id and
          other.current_status in ('Accepted', 'In Progress') and
          other.requested_start_at < v_booking.requested_end_at and
          v_booking.requested_start_at < other.requested_end_at
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'slot_conflict');
  end if;

  update public.booking set current_status = 'Accepted'
    where booking_id = p_booking_id;
  insert into public.booking_status_history
    (booking_id, changed_by_user_id, previous_status, new_status)
  values (p_booking_id, v_actor, 'Pending', 'Accepted');
  return jsonb_build_object('accepted', true, 'status', 'Accepted');
end;
$$;
revoke execute on function public.accept_pending_booking(uuid)
  from public, anon;
grant execute on function public.accept_pending_booking(uuid)
  to authenticated;


-- MIGRATION 20261123000018_owner_provider_data_visibility.sql
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


-- MIGRATION 20261123000019_owner_secure_booking_creation.sql
-- Server-authoritative creation of Pending cleaning requests.
-- Apply after 202610220005_provider_data_visibility.sql in a backed-up
-- staging project, then exercise RLS and concurrency with distinct accounts.

-- Existing rows remain null. New RPC-created requests carry a stable token
-- so a network retry cannot produce a second booking.
alter table public.booking add column client_request_id uuid;
alter table public.booking add constraint booking_owner_request_id_unique
  unique (owner_id, client_request_id);

-- The existing direct-update guard predates this column. A client may still
-- edit Pending instructions, but cannot replace the request's identity key.
create function public.guard_booking_request_id_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and
     new.client_request_id is distinct from old.client_request_id then
    raise exception 'Booking request identity cannot be edited directly'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard_booking_request_id_change_before
before update on public.booking for each row
execute function public.guard_booking_request_id_change();
revoke execute on function public.guard_booking_request_id_change()
  from public, anon, authenticated;

-- RLS alone previously allowed an Owner to insert any provider/service/time
-- combination. All new requests must go through the validated RPC below.
drop policy if exists booking_owner_insert on public.booking;
revoke insert on public.booking from public, anon, authenticated;

create function public.create_pending_booking(
  p_client_request_id uuid,
  p_provider_id uuid,
  p_property_id uuid,
  p_service_type_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_instructions text default ''
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_existing public.booking%rowtype;
  v_property public.property%rowtype;
  v_provider_status text;
  v_local_start timestamp;
  v_local_end timestamp;
  v_instructions text := coalesce(p_instructions, '');
  v_booking_id uuid;
begin
  if v_actor is null or not exists (
    select 1 from public.user_account a
    where a.user_id = v_actor and a.role = 'owner'
  ) then
    raise exception 'Property Owner authentication is required'
      using errcode = '42501';
  end if;
  if p_client_request_id is null or p_provider_id is null or
     p_property_id is null or p_service_type_id is null or
     p_start_at is null or p_end_at is null then
    raise exception 'Required booking fields are missing'
      using errcode = '23514';
  end if;

  -- An already committed request wins even if availability or approval has
  -- changed since submission. A reused token with a different payload fails.
  select * into v_existing from public.booking b
  where b.owner_id = v_actor and
        b.client_request_id = p_client_request_id;
  if found then
    if v_existing.provider_id <> p_provider_id or
       v_existing.property_id <> p_property_id or
       v_existing.service_type_id <> p_service_type_id or
       v_existing.requested_start_at <> p_start_at or
       v_existing.requested_end_at <> p_end_at or
       v_existing.instructions <> v_instructions then
      raise exception 'Request token was reused with different details'
        using errcode = '23514';
    end if;
    return jsonb_build_object('created', true,
                              'booking_id', v_existing.booking_id,
                              'reused', true);
  end if;

  if p_start_at <= now() or p_end_at <= p_start_at then
    return jsonb_build_object('created', false,
                              'reason', 'invalid_interval');
  end if;

  -- The provider lock serialises this initial check with capability and
  -- availability edits. Pending still does not reserve capacity; acceptance
  -- performs the authoritative recheck in its own protected transaction.
  select p.approval_status into v_provider_status
  from public.provider_profile p
  where p.provider_id = p_provider_id for update;
  if v_provider_status is distinct from 'approved' then
    return jsonb_build_object('created', false,
                              'reason', 'provider_not_approved');
  end if;

  select * into v_property from public.property p
  where p.property_id = p_property_id and p.owner_id = v_actor;
  if not found then
    return jsonb_build_object('created', false, 'reason', 'property');
  end if;

  v_local_start := p_start_at at time zone 'Asia/Kuala_Lumpur';
  v_local_end := p_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_local_start::date <> v_local_end::date or
     v_local_start::time < v_property.cleaning_window_start or
     v_local_end::time > v_property.cleaning_window_end then
    return jsonb_build_object('created', false,
                              'reason', 'rental_window');
  end if;

  if not exists (
    select 1 from public.provider_capability c
    where c.provider_id = p_provider_id and
          c.service_type_id = p_service_type_id
  ) then
    return jsonb_build_object('created', false, 'reason', 'service_type');
  end if;
  if exists (
    select 1 from public.provider_unavailable_date d
    where d.provider_id = p_provider_id and
          d.unavailable_on = v_local_start::date
  ) or not exists (
    select 1 from public.provider_weekly_slot s
    where s.provider_id = p_provider_id and
          s.weekday = extract(isodow from v_local_start)::integer and
          s.end_time - s.start_time >= interval '2 hours' and
          s.start_time <= v_local_start::time and
          s.end_time >= v_local_end::time
  ) then
    return jsonb_build_object('created', false, 'reason', 'availability');
  end if;
  if exists (
    select 1 from public.booking other
    where other.provider_id = p_provider_id and
          other.current_status in ('Accepted', 'In Progress') and
          other.requested_start_at < p_end_at and
          p_start_at < other.requested_end_at
  ) then
    return jsonb_build_object('created', false, 'reason', 'slot_conflict');
  end if;

  insert into public.booking (
    owner_id, provider_id, property_id, service_type_id,
    requested_start_at, requested_end_at, instructions,
    current_status, client_request_id
  ) values (
    v_actor, p_provider_id, p_property_id, p_service_type_id,
    p_start_at, p_end_at, v_instructions,
    'Pending', p_client_request_id
  ) on conflict (owner_id, client_request_id) do nothing
  returning booking_id into v_booking_id;

  if v_booking_id is null then
    -- A concurrent call with the same token committed first. Reject a
    -- mismatched payload; otherwise return that one original request.
    select * into v_existing from public.booking b
    where b.owner_id = v_actor and
          b.client_request_id = p_client_request_id;
    if not found or v_existing.provider_id <> p_provider_id or
       v_existing.property_id <> p_property_id or
       v_existing.service_type_id <> p_service_type_id or
       v_existing.requested_start_at <> p_start_at or
       v_existing.requested_end_at <> p_end_at or
       v_existing.instructions <> v_instructions then
      raise exception 'Request token was reused with different details'
        using errcode = '23514';
    end if;
    return jsonb_build_object('created', true,
                              'booking_id', v_existing.booking_id,
                              'reused', true);
  end if;
  return jsonb_build_object('created', true,
                            'booking_id', v_booking_id,
                            'reused', false);
end;
$$;
revoke execute on function public.create_pending_booking(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, text
) from public, anon;
grant execute on function public.create_pending_booking(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, text
) to authenticated;


-- MIGRATION 20261123000020_owner_property_window_lock_visibility.sql
-- Keep property-window edits serialised with provider acceptance after
-- 202610220005_provider_data_visibility.sql made raw provider rows own-only.
-- An Owner's ordinary RLS context can see their Booking but cannot SELECT
-- another user's ProviderProfile, so the original invoker-rights trigger
-- silently skipped its FOR UPDATE lock.

create or replace function public.lock_property_window_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_provider_id uuid;
begin
  if new.cleaning_window_start is distinct from old.cleaning_window_start or
     new.cleaning_window_end is distinct from old.cleaning_window_end then
    -- Property UPDATE remains Owner-only by table RLS. Take the same provider
    -- lock as accept_pending_booking before checking confirmed intervals.
    for v_provider_id in
      select distinct b.provider_id from public.booking b
      where b.property_id = old.property_id and
            b.current_status in ('Pending', 'Accepted', 'In Progress')
      order by b.provider_id
    loop
      perform 1 from public.provider_profile p
      where p.provider_id = v_provider_id for update;
    end loop;
    if exists (
      select 1 from public.booking b
      where b.property_id = old.property_id and
            b.current_status in ('Accepted', 'In Progress') and
            b.requested_end_at > now() and
            (
              (b.requested_start_at at time zone 'Asia/Kuala_Lumpur')::time
                < new.cleaning_window_start or
              (b.requested_end_at at time zone 'Asia/Kuala_Lumpur')::time
                > new.cleaning_window_end
            )
    ) then
      raise exception 'Cleaning window change conflicts with a confirmed booking'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

-- A trigger executes automatically; authenticated users must not call its
-- elevated body directly. The trigger remains attached from migration 001.
revoke execute on function public.lock_property_window_change()
  from public, anon, authenticated;


-- MIGRATION 20261123000021_owner_eligible_provider_search.sql
-- Request-specific hard filtering for Owner booking search. This is NOT the
-- distance/rating/workload ranking algorithm. Keep private origin addresses
-- and raw Provider availability out of the response.

create function public.find_eligible_providers(
  p_property_id uuid,
  p_service_type_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns table (
  provider_id uuid,
  bio text,
  service_area text,
  hourly_rate numeric,
  daily_rate numeric,
  rating_average numeric,
  completed_job_count integer
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_property public.property%rowtype;
  v_start timestamp;
  v_end timestamp;
begin
  if v_actor is null or not exists (
    select 1 from public.user_account a
    where a.user_id = v_actor and a.role = 'owner'
  ) then
    raise exception 'Property Owner authentication is required'
      using errcode = '42501';
  end if;
  if p_property_id is null or p_service_type_id is null or
     p_start_at is null or p_end_at is null or
     p_start_at <= now() or p_end_at <= p_start_at then
    raise exception 'Select a valid future cleaning interval'
      using errcode = '23514';
  end if;
  select * into v_property from public.property p
  where p.property_id = p_property_id and p.owner_id = v_actor;
  if not found then
    raise exception 'Rental unit is not owned by this account'
      using errcode = '42501';
  end if;
  v_start := p_start_at at time zone 'Asia/Kuala_Lumpur';
  v_end := p_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_start::date <> v_end::date or
     v_start::time < v_property.cleaning_window_start or
     v_end::time > v_property.cleaning_window_end then
    return;
  end if;

  return query
  select p.provider_id, p.bio, p.service_area, p.hourly_rate,
         p.daily_rate, p.rating_average, p.completed_job_count
  from public.provider_profile p
  where p.approval_status = 'approved'
    and exists (
      select 1 from public.provider_capability c
      where c.provider_id = p.provider_id and
            c.service_type_id = p_service_type_id
    )
    and not exists (
      select 1 from public.provider_unavailable_date d
      where d.provider_id = p.provider_id and
            d.unavailable_on = v_start::date
    )
    and exists (
      select 1 from public.provider_weekly_slot s
      where s.provider_id = p.provider_id and
            s.weekday = extract(isodow from v_start)::integer and
            s.end_time - s.start_time >= interval '2 hours' and
            s.start_time <= v_start::time and s.end_time >= v_end::time
    )
    and not exists (
      select 1 from public.booking b
      where b.provider_id = p.provider_id and
            b.current_status in ('Accepted', 'In Progress') and
            b.requested_start_at < p_end_at and
            p_start_at < b.requested_end_at
    )
  order by p.provider_id;
end;
$$;

revoke execute on function public.find_eligible_providers(
  uuid, uuid, timestamptz, timestamptz
) from public, anon;
grant execute on function public.find_eligible_providers(
  uuid, uuid, timestamptz, timestamptz
) to authenticated;


-- MIGRATION 20261123000022_owner_booking_quote_snapshot.sql
-- Authoritative MYR quote for cleaning requests. Apply after migration 008.
-- The quote is fixed when Pending is created; paying is still permitted only
-- after Completed and requires a separate trusted payment implementation.
-- Existing pre-migration bookings remain unpriced for explicit review.

alter table public.booking
  add column quote_currency text not null default 'MYR'
    check (quote_currency = 'MYR'),
  add column quote_basis text check (quote_basis in ('hourly', 'daily')),
  add column quoted_rate numeric(10,2),
  add column quoted_duration_minutes integer,
  add column quoted_amount numeric(12,2),
  add constraint booking_quote_complete check (
    (quote_basis is null and quoted_rate is null and
     quoted_duration_minutes is null and quoted_amount is null) or
    (quote_basis is not null and quoted_rate is not null and
     quoted_duration_minutes is not null and quoted_amount is not null and
     quoted_rate > 0 and quoted_amount > 0 and
     quoted_duration_minutes between 1 and 480 and
     extract(epoch from (requested_end_at - requested_start_at)) =
       quoted_duration_minutes * 60 and
     (quote_basis <> 'daily' or quoted_duration_minutes = 480))
  );

-- Invoker updates may still edit Pending instructions but cannot forge a
-- quoted price. The duration invariant applies even to protected RPCs:
-- changing duration requires a newly priced request, not a silent revision.
create function public.guard_booking_quote_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    new.quote_currency is distinct from old.quote_currency or
    new.quote_basis is distinct from old.quote_basis or
    new.quoted_rate is distinct from old.quoted_rate or
    new.quoted_duration_minutes is distinct from old.quoted_duration_minutes or
    new.quoted_amount is distinct from old.quoted_amount
  ) then
    raise exception 'Booking quote cannot be edited directly'
      using errcode = '42501';
  end if;
  if new.quoted_duration_minutes is not null and
     extract(epoch from (new.requested_end_at - new.requested_start_at))
       <> new.quoted_duration_minutes * 60 then
    raise exception 'Changing duration requires a new priced request'
      using errcode = '23514';
  end if;
  if old.current_status = 'Pending' and new.current_status = 'Accepted' and
     new.quoted_amount is null then
    raise exception 'Unpriced legacy request cannot be accepted'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger guard_booking_quote_change_before
before update on public.booking for each row
execute function public.guard_booking_quote_change();
revoke execute on function public.guard_booking_quote_change()
  from public, anon, authenticated;

-- No old seven-argument creation endpoint may remain callable: it could
-- otherwise create a Pending request without displaying a price to Owner.
drop function public.create_pending_booking(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, text
);

create function public.create_pending_booking(
  p_client_request_id uuid,
  p_provider_id uuid,
  p_property_id uuid,
  p_service_type_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_expected_amount numeric,
  p_expected_basis text,
  p_instructions text default ''
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_existing public.booking%rowtype;
  v_property public.property%rowtype;
  v_provider_status text;
  v_hourly_rate numeric;
  v_daily_rate numeric;
  v_rate numeric;
  v_basis text;
  v_amount numeric(12,2);
  v_seconds numeric;
  v_minutes integer;
  v_local_start timestamp;
  v_local_end timestamp;
  v_instructions text := coalesce(p_instructions, '');
  v_booking_id uuid;
begin
  if v_actor is null or not exists (
    select 1 from public.user_account a
    where a.user_id = v_actor and a.role = 'owner'
  ) then
    raise exception 'Property Owner authentication is required'
      using errcode = '42501';
  end if;
  if p_client_request_id is null or p_provider_id is null or
     p_property_id is null or p_service_type_id is null or
     p_start_at is null or p_end_at is null or
     p_expected_amount is null or p_expected_basis is null then
    raise exception 'Required booking fields are missing'
      using errcode = '23514';
  end if;

  select * into v_existing from public.booking b
  where b.owner_id = v_actor and
        b.client_request_id = p_client_request_id;
  if found then
    if v_existing.provider_id <> p_provider_id or
       v_existing.property_id <> p_property_id or
       v_existing.service_type_id <> p_service_type_id or
       v_existing.requested_start_at <> p_start_at or
       v_existing.requested_end_at <> p_end_at or
       v_existing.instructions <> v_instructions or
       v_existing.quoted_amount is distinct from p_expected_amount or
       v_existing.quote_basis is distinct from p_expected_basis then
      raise exception 'Request token was reused with different details'
        using errcode = '23514';
    end if;
    return jsonb_build_object('created', true,
      'booking_id', v_existing.booking_id, 'reused', true,
      'quoted_amount', v_existing.quoted_amount,
      'quote_basis', v_existing.quote_basis,
      'quote_currency', v_existing.quote_currency);
  end if;

  if p_start_at <= now() or p_end_at <= p_start_at then
    return jsonb_build_object('created', false, 'reason', 'invalid_interval');
  end if;
  v_seconds := extract(epoch from (p_end_at - p_start_at));
  if mod(v_seconds, 60) <> 0 or v_seconds < 60 or v_seconds > 28800 then
    return jsonb_build_object('created', false, 'reason', 'invalid_duration');
  end if;
  v_minutes := (v_seconds / 60)::integer;

  -- Lock the Provider before reading their current rate and operational data.
  -- A later provider-rate edit does not alter this Booking's snapshot.
  select p.approval_status, p.hourly_rate, p.daily_rate
    into v_provider_status, v_hourly_rate, v_daily_rate
  from public.provider_profile p
  where p.provider_id = p_provider_id for update;
  if v_provider_status is distinct from 'approved' then
    return jsonb_build_object('created', false,
                              'reason', 'provider_not_approved');
  end if;

  if v_minutes = 480 and v_daily_rate > 0 then
    v_basis := 'daily';
    v_rate := v_daily_rate;
    v_amount := v_daily_rate;
  elsif v_hourly_rate > 0 then
    v_basis := 'hourly';
    v_rate := v_hourly_rate;
    v_amount := round(v_hourly_rate * v_minutes / 60, 2);
  else
    return jsonb_build_object('created', false,
                              'reason', 'rate_unavailable');
  end if;
  if v_amount <= 0 or p_expected_amount <> v_amount or
     p_expected_basis <> v_basis then
    return jsonb_build_object('created', false, 'reason', 'price_changed');
  end if;

  select * into v_property from public.property p
  where p.property_id = p_property_id and p.owner_id = v_actor;
  if not found then
    return jsonb_build_object('created', false, 'reason', 'property');
  end if;
  v_local_start := p_start_at at time zone 'Asia/Kuala_Lumpur';
  v_local_end := p_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_local_start::date <> v_local_end::date or
     v_local_start::time < v_property.cleaning_window_start or
     v_local_end::time > v_property.cleaning_window_end then
    return jsonb_build_object('created', false, 'reason', 'rental_window');
  end if;
  if not exists (
    select 1 from public.provider_capability c
    where c.provider_id = p_provider_id and
          c.service_type_id = p_service_type_id
  ) then
    return jsonb_build_object('created', false, 'reason', 'service_type');
  end if;
  if exists (
    select 1 from public.provider_unavailable_date d
    where d.provider_id = p_provider_id and
          d.unavailable_on = v_local_start::date
  ) or not exists (
    select 1 from public.provider_weekly_slot s
    where s.provider_id = p_provider_id and
          s.weekday = extract(isodow from v_local_start)::integer and
          s.end_time - s.start_time >= interval '2 hours' and
          s.start_time <= v_local_start::time and
          s.end_time >= v_local_end::time
  ) then
    return jsonb_build_object('created', false, 'reason', 'availability');
  end if;
  if exists (
    select 1 from public.booking other
    where other.provider_id = p_provider_id and
          other.current_status in ('Accepted', 'In Progress') and
          other.requested_start_at < p_end_at and
          p_start_at < other.requested_end_at
  ) then
    return jsonb_build_object('created', false, 'reason', 'slot_conflict');
  end if;

  insert into public.booking (
    owner_id, provider_id, property_id, service_type_id,
    requested_start_at, requested_end_at, instructions,
    current_status, client_request_id, quote_basis, quoted_rate,
    quoted_duration_minutes, quoted_amount
  ) values (
    v_actor, p_provider_id, p_property_id, p_service_type_id,
    p_start_at, p_end_at, v_instructions,
    'Pending', p_client_request_id, v_basis, v_rate,
    v_minutes, v_amount
  ) on conflict (owner_id, client_request_id) do nothing
  returning booking_id into v_booking_id;

  if v_booking_id is null then
    select * into v_existing from public.booking b
    where b.owner_id = v_actor and
          b.client_request_id = p_client_request_id;
    if not found or v_existing.provider_id <> p_provider_id or
       v_existing.property_id <> p_property_id or
       v_existing.service_type_id <> p_service_type_id or
       v_existing.requested_start_at <> p_start_at or
       v_existing.requested_end_at <> p_end_at or
       v_existing.instructions <> v_instructions or
       v_existing.quoted_amount is distinct from p_expected_amount or
       v_existing.quote_basis is distinct from p_expected_basis then
      raise exception 'Request token was reused with different details'
        using errcode = '23514';
    end if;
    return jsonb_build_object('created', true,
      'booking_id', v_existing.booking_id, 'reused', true,
      'quoted_amount', v_existing.quoted_amount,
      'quote_basis', v_existing.quote_basis,
      'quote_currency', v_existing.quote_currency);
  end if;
  return jsonb_build_object('created', true,
    'booking_id', v_booking_id, 'reused', false,
    'quoted_amount', v_amount, 'quote_basis', v_basis,
    'quote_currency', 'MYR');
end;
$$;
revoke execute on function public.create_pending_booking(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, numeric, text, text
) from public, anon;
grant execute on function public.create_pending_booking(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, numeric, text, text
) to authenticated;

-- The old search return type cannot be changed in-place. Replace it with a
-- version that includes the server-calculated quote displayed before Submit.
drop function public.find_eligible_providers(
  uuid, uuid, timestamptz, timestamptz
);
create function public.find_eligible_providers(
  p_property_id uuid,
  p_service_type_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns table (
  provider_id uuid,
  bio text,
  service_area text,
  hourly_rate numeric,
  daily_rate numeric,
  rating_average numeric,
  completed_job_count integer,
  quote_basis text,
  quoted_amount numeric
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_property public.property%rowtype;
  v_start timestamp;
  v_end timestamp;
  v_seconds numeric;
  v_minutes integer;
begin
  if v_actor is null or not exists (
    select 1 from public.user_account a
    where a.user_id = v_actor and a.role = 'owner'
  ) then
    raise exception 'Property Owner authentication is required'
      using errcode = '42501';
  end if;
  if p_property_id is null or p_service_type_id is null or
     p_start_at is null or p_end_at is null or
     p_start_at <= now() or p_end_at <= p_start_at then
    raise exception 'Select a valid future cleaning interval'
      using errcode = '23514';
  end if;
  v_seconds := extract(epoch from (p_end_at - p_start_at));
  if mod(v_seconds, 60) <> 0 or v_seconds < 60 or v_seconds > 28800 then
    raise exception 'Select a service duration up to eight hours'
      using errcode = '23514';
  end if;
  v_minutes := (v_seconds / 60)::integer;
  select * into v_property from public.property p
  where p.property_id = p_property_id and p.owner_id = v_actor;
  if not found then
    raise exception 'Rental unit is not owned by this account'
      using errcode = '42501';
  end if;
  v_start := p_start_at at time zone 'Asia/Kuala_Lumpur';
  v_end := p_end_at at time zone 'Asia/Kuala_Lumpur';
  if v_start::date <> v_end::date or
     v_start::time < v_property.cleaning_window_start or
     v_end::time > v_property.cleaning_window_end then
    return;
  end if;

  return query
  select p.provider_id, p.bio, p.service_area, p.hourly_rate,
         p.daily_rate, p.rating_average, p.completed_job_count,
         case when v_minutes = 480 and p.daily_rate > 0
           then 'daily' else 'hourly' end,
         case when v_minutes = 480 and p.daily_rate > 0
           then p.daily_rate
           else round(p.hourly_rate * v_minutes / 60, 2) end
  from public.provider_profile p
  where p.approval_status = 'approved'
    and (
      (v_minutes = 480 and (p.daily_rate > 0 or p.hourly_rate > 0)) or
      (v_minutes < 480 and p.hourly_rate > 0 and
        round(p.hourly_rate * v_minutes / 60, 2) > 0)
    )
    and exists (
      select 1 from public.provider_capability c
      where c.provider_id = p.provider_id and
            c.service_type_id = p_service_type_id
    )
    and not exists (
      select 1 from public.provider_unavailable_date d
      where d.provider_id = p.provider_id and
            d.unavailable_on = v_start::date
    )
    and exists (
      select 1 from public.provider_weekly_slot s
      where s.provider_id = p.provider_id and
            s.weekday = extract(isodow from v_start)::integer and
            s.end_time - s.start_time >= interval '2 hours' and
            s.start_time <= v_start::time and s.end_time >= v_end::time
    )
    and not exists (
      select 1 from public.booking b
      where b.provider_id = p.provider_id and
            b.current_status in ('Accepted', 'In Progress') and
            b.requested_start_at < p_end_at and
            p_start_at < b.requested_end_at
    )
  order by p.provider_id;
end;
$$;
revoke execute on function public.find_eligible_providers(
  uuid, uuid, timestamptz, timestamptz
) from public, anon;
grant execute on function public.find_eligible_providers(
  uuid, uuid, timestamptz, timestamptz
) to authenticated;


-- MIGRATION 20261123000023_owner_booking_messages.sql
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


-- MIGRATION 20261123000024_owner_booking_reviews.sql
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


-- MIGRATION 20261123000025_owner_booking_contexts.sql
-- Participant-only booking presentation data. Provider access to a rental
-- address must be scoped to their assigned booking, not to all properties.
create function public.list_booking_contexts()
returns table (
  booking_id uuid,
  unit_name text,
  building_name text,
  property_address text,
  service_name text,
  instructions text
)
language sql stable security definer set search_path = '' as $$
  select b.booking_id, p.unit_name, p.building_name,
         p.address as property_address, s.name as service_name,
         b.instructions
  from public.booking b
  join public.property p on p.property_id = b.property_id
  join public.service_type s on s.service_type_id = b.service_type_id
  where auth.uid() is not null
    and (b.owner_id = auth.uid() or b.provider_id = auth.uid());
$$;
revoke execute on function public.list_booking_contexts()
  from public, anon;
grant execute on function public.list_booking_contexts()
  to authenticated;


-- MIGRATION 20261123000026_owner_deployment_environment.sql
-- Administrator-owned environment identity. Applying migrations must NOT
-- silently label an existing project as staging or production.
create table public.app_deployment_environment (
  singleton boolean primary key default true check (singleton),
  environment text not null default 'unassigned'
    check (environment in ('unassigned', 'staging', 'production')),
  project_ref text,
  configured_at timestamptz not null default now(),
  constraint deployment_environment_assignment check (
    (environment = 'unassigned' and project_ref is null) or
    (environment in ('staging', 'production') and project_ref ~ '^[a-z]{20}$'
      and project_ref is not null)
  )
);
insert into public.app_deployment_environment(singleton) values (true);
alter table public.app_deployment_environment enable row level security;
revoke all on public.app_deployment_environment from public, anon, authenticated;

-- No user data, keys or credentials are exposed. Login is deliberately not
-- needed: the app must check this before restoring any saved Auth session.
create function public.get_app_environment()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('environment', environment, 'project_ref', project_ref)
  from public.app_deployment_environment where singleton;
$$;
revoke all on function public.get_app_environment() from public;
grant execute on function public.get_app_environment() to anon, authenticated;


-- MIGRATION 20261123000027_owner_evidence_upload_lifecycle.sql
-- Register immutable objects before upload. Only RPCs can attach evidence;
-- cleanup tombstones cannot ever become attachable again. No Storage object
-- is deleted by SQL: the authenticated client must use the Storage API.
create table public.evidence_upload (
  upload_id uuid primary key,
  booking_id uuid not null references public.booking(booking_id),
  provider_id uuid not null references public.user_account(user_id),
  kind text not null check (kind in ('before', 'after')),
  object_path text not null unique,
  expected_previous_path text,
  byte_size integer check (byte_size between 1 and 5242880),
  sha256 text check (sha256 ~ '^[a-f0-9]{64}$'),
  state text not null default 'pending'
    check (state in ('pending', 'attached', 'retired', 'deleting', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index evidence_upload_booking_state on public.evidence_upload(booking_id, state, created_at);
create index evidence_upload_cleanup_candidates on public.evidence_upload(state, created_at, booking_id);
create index booking_evidence_before_path on public.booking_evidence(before_path) where before_path is not null;
create index booking_evidence_after_path on public.booking_evidence(after_path) where after_path is not null;
alter table public.evidence_upload enable row level security;
revoke all on public.evidence_upload from public, anon, authenticated;
grant select on public.evidence_upload to authenticated;
create policy evidence_upload_provider_read on public.evidence_upload
  for select to authenticated using (provider_id = (select auth.uid()));

-- Serialize photo/remarks writes against completion, using the lifecycle's
-- provider-then-booking lock order. No caller-provided Owner/Provider IDs.
create function public.lock_evidence_booking(p_booking_id uuid)
returns public.booking language plpgsql security definer set search_path = '' as $$
declare v_booking public.booking%rowtype; v_provider uuid;
begin
  select provider_id into v_provider from public.booking where booking_id = p_booking_id;
  if auth.uid() is null or v_provider is distinct from auth.uid() then
    raise exception 'Assigned provider required' using errcode = '42501';
  end if;
  perform 1 from public.provider_profile where provider_id = v_provider for update;
  select * into v_booking from public.booking where booking_id = p_booking_id for update;
  if not found then raise exception 'Booking not found' using errcode = 'P0002'; end if;
  return v_booking;
end $$;
revoke all on function public.lock_evidence_booking(uuid) from public, anon, authenticated;

create function public.begin_evidence_upload(
  p_booking_id uuid, p_upload_id uuid, p_kind text,
  p_extension text, p_byte_size integer, p_sha256 text, p_expected_previous_path text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_booking public.booking%rowtype; v_upload public.evidence_upload%rowtype; v_previous text;
begin
  v_booking := public.lock_evidence_booking(p_booking_id);
  if p_upload_id is null or p_kind is null or p_kind not in ('before','after') or
     p_extension is null or p_extension not in ('jpg','png') or
     p_byte_size is null or p_byte_size not between 1 and 5242880 or
     p_sha256 is null or p_sha256 !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid image manifest' using errcode = '23514';
  end if;
  select * into v_upload from public.evidence_upload where upload_id = p_upload_id for update;
  if found then
    if v_upload.provider_id <> auth.uid() or v_upload.booking_id <> p_booking_id or
       v_upload.kind <> p_kind or v_upload.byte_size is distinct from p_byte_size or
       v_upload.sha256 is distinct from p_sha256 or
       v_upload.expected_previous_path is distinct from p_expected_previous_path or
       v_upload.object_path <> p_booking_id::text || '/' || p_kind || '_' || p_upload_id::text || '.' || p_extension then
      raise exception 'Upload token cannot be reused for different content' using errcode = '23514';
    end if;
  else
    if v_booking.current_status <> 'In Progress' then
      return jsonb_build_object('state','closed');
    end if;
    select case when p_kind = 'before' then before_path else after_path end into v_previous
      from public.booking_evidence where booking_id = p_booking_id;
    if v_previous is distinct from p_expected_previous_path then
      return jsonb_build_object('state','photo_changed');
    end if;
    insert into public.evidence_upload(upload_id,booking_id,provider_id,kind,
      object_path,expected_previous_path,byte_size,sha256)
    values(p_upload_id,p_booking_id,auth.uid(),p_kind,
      p_booking_id::text || '/' || p_kind || '_' || p_upload_id::text || '.' || p_extension,
      v_previous,p_byte_size,p_sha256) returning * into v_upload;
  end if;
  if v_upload.state = 'pending' and
     (v_booking.current_status <> 'In Progress' or v_upload.created_at <= now() - interval '24 hours') then
    return jsonb_build_object('state','expired_or_closed');
  end if;
  return jsonb_build_object('state',v_upload.state,'path',v_upload.object_path,
    'uploaded',exists(select 1 from storage.objects
      where bucket_id = 'cleaning-evidence' and name = v_upload.object_path));
end $$;

create function public.attach_evidence_upload(p_booking_id uuid, p_upload_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_booking public.booking%rowtype; v_upload public.evidence_upload%rowtype; v_previous text;
begin
  v_booking := public.lock_evidence_booking(p_booking_id);
  select * into v_upload from public.evidence_upload where upload_id = p_upload_id
    and booking_id = p_booking_id and provider_id = auth.uid() for update;
  if not found then raise exception 'Upload not found' using errcode = '42501'; end if;
  select case when v_upload.kind = 'before' then before_path else after_path end into v_previous
    from public.booking_evidence where booking_id = p_booking_id;
  if v_upload.state = 'attached' and v_previous = v_upload.object_path then
    return jsonb_build_object('attached',true,'path',v_upload.object_path);
  end if;
  if v_upload.state <> 'pending' or v_upload.created_at <= now() - interval '24 hours' or
     v_booking.current_status <> 'In Progress' then
    return jsonb_build_object('attached',false,'reason','expired_or_closed');
  end if;
  if not exists(select 1 from storage.objects where bucket_id = 'cleaning-evidence'
    and name = v_upload.object_path and metadata->>'size' = v_upload.byte_size::text
    and metadata->>'mimetype' = case when right(v_upload.object_path,4) = '.jpg'
      then 'image/jpeg' else 'image/png' end) then
    return jsonb_build_object('attached',false,'reason','upload_not_confirmed');
  end if;
  -- Compare-and-set prevents two devices silently replacing each other's work.
  if v_previous is distinct from v_upload.expected_previous_path then
    update public.evidence_upload set state = 'retired', updated_at = now() where upload_id = p_upload_id;
    return jsonb_build_object('attached',false,'reason','photo_changed');
  end if;
  insert into public.booking_evidence(booking_id) values(p_booking_id) on conflict do nothing;
  if v_upload.kind = 'before' then
    update public.booking_evidence set before_path = v_upload.object_path, updated_at = now()
      where booking_id = p_booking_id;
  else
    update public.booking_evidence set after_path = v_upload.object_path, updated_at = now()
      where booking_id = p_booking_id;
  end if;
  if v_previous is not null then
    -- Only known, previously referenced legacy objects are adopted. Unknown
    -- historical files are never guessed to be safe to delete.
    insert into public.evidence_upload(upload_id,booking_id,provider_id,kind,object_path,state)
      values(gen_random_uuid(),p_booking_id,auth.uid(),v_upload.kind,v_previous,'retired')
      on conflict(object_path) do update set state = 'retired', updated_at = now();
  end if;
  update public.evidence_upload set state = 'attached', updated_at = now() where upload_id = p_upload_id;
  return jsonb_build_object('attached',true,'path',v_upload.object_path);
end $$;

create function public.save_evidence_remarks(p_booking_id uuid, p_remarks text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_booking public.booking%rowtype;
begin
  v_booking := public.lock_evidence_booking(p_booking_id);
  if v_booking.current_status <> 'In Progress' or p_remarks is null or char_length(btrim(p_remarks)) > 1000 then
    raise exception 'Remarks cannot be changed' using errcode = '23514';
  end if;
  insert into public.booking_evidence(booking_id,completion_remarks) values(p_booking_id,btrim(p_remarks))
  on conflict(booking_id) do update set completion_remarks = excluded.completion_remarks, updated_at = now();
end $$;

-- A bounded, booking-scoped outbox. A crashed/failed deletion can be retried.
-- Pending uploads have a 24-hour grace period. Cleanup never uses device time.
create function public.claim_evidence_cleanup(p_booking_id uuid)
returns table(object_path text) language plpgsql security definer set search_path = '' as $$
begin
  perform public.lock_evidence_booking(p_booking_id);
  return query
    with candidates as (
      select u.upload_id from public.evidence_upload u
      where u.booking_id = p_booking_id and u.provider_id = auth.uid()
        and (u.state in ('retired','deleting') or
          (u.state = 'pending' and u.created_at <= now() - interval '24 hours'))
        and not exists(select 1 from public.booking_evidence e
          where e.before_path = u.object_path or e.after_path = u.object_path)
      order by u.created_at,u.upload_id limit 20 for update
    )
    update public.evidence_upload u set state = 'deleting', updated_at = now()
    from candidates c where u.upload_id = c.upload_id returning u.object_path;
end $$;

create function public.finish_evidence_cleanup(p_booking_id uuid, p_path text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  perform public.lock_evidence_booking(p_booking_id);
  if exists(select 1 from storage.objects where bucket_id = 'cleaning-evidence' and name = p_path) then
    return false;
  end if;
  update public.evidence_upload set state = 'deleted', updated_at = now()
    where booking_id = p_booking_id and provider_id = auth.uid()
      and object_path = p_path and state = 'deleting';
  if found then return true; end if;
  return exists(select 1 from public.evidence_upload where booking_id=p_booking_id
    and provider_id=auth.uid() and object_path=p_path and state='deleted');
end $$;

-- All client evidence writes now use locking RPCs, including remarks.
revoke insert,update,delete on public.booking_evidence from anon, authenticated;
drop policy evidence_provider_insert on public.booking_evidence;
drop policy evidence_provider_update on public.booking_evidence;

create function public.can_upload_evidence_object(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.evidence_upload u join public.booking b using(booking_id)
    where u.object_path = p_path and u.provider_id = auth.uid() and u.state = 'pending'
      and u.created_at > now() - interval '24 hours' and b.current_status = 'In Progress');
$$;
create function public.can_delete_evidence_object(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.evidence_upload u
    where u.object_path = p_path and u.provider_id = auth.uid() and u.state = 'deleting')
    and not exists(select 1 from public.booking_evidence e where e.before_path = p_path or e.after_path = p_path);
$$;
create function public.can_read_evidence_object(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.booking_evidence e join public.booking b using(booking_id)
    where (e.before_path = p_path or e.after_path = p_path)
      and auth.uid() in (b.owner_id,b.provider_id))
    or exists(select 1 from public.evidence_upload u where u.object_path = p_path and u.provider_id = auth.uid());
$$;
drop policy evidence_object_provider_insert on storage.objects;
drop policy evidence_object_participant_read on storage.objects;
create policy evidence_registered_upload on storage.objects for insert to authenticated
  with check(bucket_id = 'cleaning-evidence' and public.can_upload_evidence_object(name));
create policy evidence_private_read on storage.objects for select to authenticated
  using(bucket_id = 'cleaning-evidence' and public.can_read_evidence_object(name));
create policy evidence_obsolete_delete on storage.objects for delete to authenticated
  using(bucket_id = 'cleaning-evidence' and public.can_delete_evidence_object(name));
grant delete on storage.objects to authenticated;

revoke all on function public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text) from public,anon;
revoke all on function public.attach_evidence_upload(uuid,uuid) from public,anon;
revoke all on function public.save_evidence_remarks(uuid,text) from public,anon;
revoke all on function public.claim_evidence_cleanup(uuid) from public,anon;
revoke all on function public.finish_evidence_cleanup(uuid,text) from public,anon;
revoke all on function public.can_upload_evidence_object(text) from public,anon;
revoke all on function public.can_delete_evidence_object(text) from public,anon;
revoke all on function public.can_read_evidence_object(text) from public,anon;
grant execute on function public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text),
  public.attach_evidence_upload(uuid,uuid), public.save_evidence_remarks(uuid,text),
  public.claim_evidence_cleanup(uuid), public.finish_evidence_cleanup(uuid,text),
  public.can_upload_evidence_object(text), public.can_delete_evidence_object(text),
  public.can_read_evidence_object(text) to authenticated;

-- Maintenance worker: the service credential stays outside Flutter. This
-- handles abandoned bookings without depending on a Provider reopening them.
create function public.list_evidence_cleanup_batch()
returns table(booking_id uuid,object_path text)
language sql stable security definer set search_path = '' as $$
  select u.booking_id,u.object_path from public.evidence_upload u
  where (u.state in ('retired','deleting') or
    (u.state='pending' and u.created_at <= now()-interval '24 hours'))
    and not exists(select 1 from public.booking_evidence e
      where e.before_path=u.object_path or e.after_path=u.object_path)
  order by u.created_at,u.upload_id limit 20;
$$;

create function public.claim_evidence_cleanup_batch()
returns table(booking_id uuid,object_path text)
language plpgsql security definer set search_path = '' as $$
declare v_booking record; v_count integer := 0; v_added integer;
begin
  for v_booking in
    select distinct b.provider_id,b.booking_id from public.booking b
    join public.evidence_upload u on u.booking_id=b.booking_id
    where u.state in ('retired','deleting') or
      (u.state='pending' and u.created_at <= now()-interval '24 hours')
    order by b.provider_id,b.booking_id limit 20
  loop
    -- Match the booking lifecycle's lock order; never stall an active write.
    perform 1 from public.provider_profile p where p.provider_id=v_booking.provider_id for update skip locked;
    if not found then continue; end if;
    perform 1 from public.booking b where b.booking_id=v_booking.booking_id for update skip locked;
    if not found then continue; end if;
    return query with candidates as (
      select u.upload_id from public.evidence_upload u
      where u.booking_id=v_booking.booking_id and
        (u.state in ('retired','deleting') or (u.state='pending' and u.created_at<=now()-interval '24 hours'))
        and not exists(select 1 from public.booking_evidence e
          where e.before_path=u.object_path or e.after_path=u.object_path)
      order by u.created_at,u.upload_id limit (20-v_count) for update
    ) update public.evidence_upload u set state='deleting',updated_at=now()
      from candidates c where u.upload_id=c.upload_id returning u.booking_id,u.object_path;
    get diagnostics v_added = row_count;
    v_count := v_count + v_added;
    exit when v_count >= 20;
  end loop;
end $$;

create function public.finish_evidence_cleanup_batch(p_booking_id uuid,p_path text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if exists(select 1 from storage.objects where bucket_id='cleaning-evidence' and name=p_path)
    or exists(select 1 from public.booking_evidence where before_path=p_path or after_path=p_path) then
    return false;
  end if;
  update public.evidence_upload set state='deleted',updated_at=now()
    where booking_id=p_booking_id and object_path=p_path and state='deleting';
  if found then return true; end if;
  return exists(select 1 from public.evidence_upload where booking_id=p_booking_id
    and object_path=p_path and state='deleted');
end $$;
revoke all on function public.list_evidence_cleanup_batch() from public,anon,authenticated;
revoke all on function public.claim_evidence_cleanup_batch() from public,anon,authenticated;
revoke all on function public.finish_evidence_cleanup_batch(uuid,text) from public,anon,authenticated;
grant execute on function public.list_evidence_cleanup_batch(),
  public.claim_evidence_cleanup_batch(), public.finish_evidence_cleanup_batch(uuid,text),
  public.get_app_environment() to service_role;


-- MIGRATION 20261123000028_owner_cursor_pagination.sql
-- Read-only, participant-scoped keyset pages. Timestamps retain PostgreSQL
-- precision; UUID is the tie breaker. A page never returns more than 50 rows.
create index booking_owner_cursor_idx on public.booking(owner_id,created_at desc,booking_id desc);
create index booking_provider_cursor_idx on public.booking(provider_id,created_at desc,booking_id desc);
create index booking_history_cursor_idx on public.booking_status_history(booking_id,changed_at desc,status_history_id desc);

create function public.pack_cursor_page(p_rows jsonb,p_limit integer,p_time_field text,p_id_field text)
returns jsonb language sql immutable set search_path='' as $$
  select jsonb_build_object('items',coalesce((select jsonb_agg(value order by ordinal)
    from jsonb_array_elements(p_rows) with ordinality as r(value,ordinal) where ordinal<=p_limit),'[]'::jsonb),
    'has_more',jsonb_array_length(p_rows)>p_limit,
    'next_cursor',case when jsonb_array_length(p_rows)>p_limit then
      jsonb_build_object('timestamp',p_rows->(p_limit-1)->p_time_field,'id',p_rows->(p_limit-1)->p_id_field) else null end);
$$;
revoke all on function public.pack_cursor_page(jsonb,integer,text,text) from public,anon,authenticated;

create function public.page_my_bookings(p_limit integer default 20,p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_limit is null or p_limit not between 1 and 50 or (p_before_at is null)<>(p_before_id is null) then
    raise exception 'Invalid pagination request' using errcode='22023'; end if;
  select coalesce(jsonb_agg(card order by created_at desc,booking_id desc),'[]'::jsonb) into rows from (
    select b.created_at,b.booking_id,to_jsonb(b)||jsonb_build_object(
      'unit_name',p.unit_name,'building_name',p.building_name,'property_address',p.address,'service_name',s.name) as card
    from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
    where (b.owner_id=auth.uid() or b.provider_id=auth.uid()) and
      (p_before_at is null or (b.created_at,b.booking_id)<(p_before_at,p_before_id))
    order by b.created_at desc,b.booking_id desc limit p_limit+1
  ) bounded;
  return public.pack_cursor_page(rows,p_limit,'created_at','booking_id');
end $$;

create function public.booking_cards_by_ids(p_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_ids is null or cardinality(p_ids) not between 1 and 50 then
    raise exception 'Request 1 to 50 IDs' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('unit_name',p.unit_name,
    'building_name',p.building_name,'property_address',p.address,'service_name',s.name)),'[]'::jsonb) into rows
  from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
  where b.booking_id=any(p_ids) and (b.owner_id=auth.uid() or b.provider_id=auth.uid());
  return rows;
end $$;

create function public.page_booking_messages(p_booking_id uuid,p_limit integer default 20,
  p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
  if auth.uid() is null or not exists(select 1 from public.booking where booking_id=p_booking_id
    and auth.uid() in (owner_id,provider_id)) then
    raise exception 'Booking participant required' using errcode='42501'; end if;
  if p_limit is null or p_limit not between 1 and 50 or (p_before_at is null)<>(p_before_id is null) then
    raise exception 'Invalid pagination request' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at desc,m.message_id desc),'[]'::jsonb) into rows from (
    select message_id,booking_id,sender_user_id,body,created_at from public.booking_message
    where booking_id=p_booking_id and (p_before_at is null or (created_at,message_id)<(p_before_at,p_before_id))
    order by created_at desc,message_id desc limit p_limit+1
  ) m;
  return public.pack_cursor_page(rows,p_limit,'created_at','message_id');
end $$;

create function public.page_booking_history(p_booking_id uuid,p_limit integer default 20,
  p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
  if auth.uid() is null or not exists(select 1 from public.booking where booking_id=p_booking_id
    and auth.uid() in (owner_id,provider_id)) then
    raise exception 'Booking participant required' using errcode='42501'; end if;
  if p_limit is null or p_limit not between 1 and 50 or (p_before_at is null)<>(p_before_id is null) then
    raise exception 'Invalid pagination request' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(h) order by h.changed_at desc,h.status_history_id desc),'[]'::jsonb) into rows from (
    select * from public.booking_status_history where booking_id=p_booking_id and
      (p_before_at is null or (changed_at,status_history_id)<(p_before_at,p_before_id))
    order by changed_at desc,status_history_id desc limit p_limit+1
  ) h;
  return public.pack_cursor_page(rows,p_limit,'changed_at','status_history_id');
end $$;

create function public.owner_dashboard_summary()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if auth.uid() is null or not exists(select 1 from public.user_account where user_id=auth.uid() and role='owner') then
    raise exception 'Owner required' using errcode='42501'; end if;
  select jsonb_build_object('property_count',(select count(*) from public.property where owner_id=auth.uid()),
    'pending_count',count(*) filter(where current_status='Pending'),
    'active_count',count(*) filter(where current_status in ('Accepted','In Progress')),
    'completed_count',count(*) filter(where current_status='Completed')) into result
  from public.booking where owner_id=auth.uid();
  return result;
end $$;

revoke all on function public.page_my_bookings(integer,timestamptz,uuid) from public,anon;
revoke all on function public.booking_cards_by_ids(uuid[]) from public,anon;
revoke all on function public.page_booking_messages(uuid,integer,timestamptz,uuid) from public,anon;
revoke all on function public.page_booking_history(uuid,integer,timestamptz,uuid) from public,anon;
revoke all on function public.owner_dashboard_summary() from public,anon;
grant execute on function public.page_my_bookings(integer,timestamptz,uuid),public.booking_cards_by_ids(uuid[]),
  public.page_booking_messages(uuid,integer,timestamptz,uuid),public.page_booking_history(uuid,integer,timestamptz,uuid),
  public.owner_dashboard_summary() to authenticated;


-- MIGRATION 20261123000029_owner_test_data_management.sql
-- Staging-only, administrator-invoked fixtures. No Auth accounts, mail, files,
-- payment events or Completed bookings are fabricated by this migration.
-- Do not rely on hosted default function ACLs for the admin tool's probe.
grant execute on function public.get_app_environment() to service_role;

create table public.test_data_run (
  run_id uuid primary key,
  project_ref text not null check (project_ref ~ '^[a-z]{20}$'),
  data_source text not null default 'SYNTHETIC TEST DATA - NOT A REAL USER'
    check (data_source = 'SYNTHETIC TEST DATA - NOT A REAL USER'),
  owner_id uuid not null unique references auth.users(id),
  provider_id uuid not null unique references auth.users(id),
  fixture_date date not null,
  created_at timestamptz not null default now(),
  review_after timestamptz not null default now() + interval '14 days',
  check (owner_id <> provider_id)
);
alter table public.test_data_run enable row level security;
revoke all on public.test_data_run from public, anon, authenticated, service_role;

-- Holds a shared marker lock for the calling transaction: an administrator's
-- environment reassignment cannot race an already-validated fixture write.
create function public.require_test_environment(p_project_ref text)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.app_deployment_environment%rowtype;
begin
  select * into v from public.app_deployment_environment where singleton for share;
  if v.environment is distinct from 'staging' or
     p_project_ref is null or v.project_ref is distinct from p_project_ref then
    raise exception 'Verified staging project required' using errcode = '42501';
  end if;
end;
$$;
revoke all on function public.require_test_environment(text)
  from public, anon, authenticated, service_role;

-- Used for BOTH dry run and creation; ordinary app accounts cannot call it.
-- New fixture accounts must be explicitly provisioned by the administrator in
-- Auth first, with these reserved, undeliverable addresses and no business data.
create function public.preview_test_fixture(
  p_project_ref text, p_run_id uuid, p_owner_id uuid, p_provider_id uuid,
  p_fixture_date date
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_run public.test_data_run%rowtype; v_owner_email text; v_provider_email text;
begin
  perform public.require_test_environment(p_project_ref);
  if p_run_id is null or p_owner_id is null or p_provider_id is null or
     p_owner_id = p_provider_id or p_fixture_date is null then
    raise exception 'Distinct test accounts and complete run parameters required'
      using errcode = '22023';
  end if;
  select * into v_run from public.test_data_run where run_id = p_run_id;
  if found then
    if v_run.owner_id <> p_owner_id or v_run.provider_id <> p_provider_id or
       v_run.fixture_date <> p_fixture_date or v_run.project_ref <> p_project_ref then
      raise exception 'Existing run parameters cannot be changed' using errcode = '22023';
    end if;
    return jsonb_build_object('run_id', p_run_id, 'already_seeded', true);
  end if;
  if p_fixture_date < (now() at time zone 'Asia/Kuala_Lumpur')::date + 1 or
     p_fixture_date > (now() at time zone 'Asia/Kuala_Lumpur')::date + 90 then
    raise exception 'Fixture date must be 1 to 90 Malaysian calendar days ahead'
      using errcode = '22023';
  end if;
  -- Lock Auth rows so deletion/reassignment cannot race creation. Auth itself
  -- is managed through its admin service, never inserted/updated by this RPC.
  select lower(email) into v_owner_email from auth.users where id = p_owner_id for share;
  select lower(email) into v_provider_email from auth.users where id = p_provider_id for share;
  if v_owner_email is distinct from 'owner.' || p_run_id::text || '@rental-test.invalid' or
     v_provider_email is distinct from 'provider.' || p_run_id::text || '@rental-test.invalid' then
    raise exception 'Use only the exact reserved test account emails for this run'
      using errcode = '42501';
  end if;
  if exists (select 1 from public.user_account where user_id in (p_owner_id, p_provider_id)) or
     exists (select 1 from public.test_data_run where
       owner_id in (p_owner_id, p_provider_id) or provider_id in (p_owner_id, p_provider_id)) then
    raise exception 'Test accounts must not already own business data or another run'
      using errcode = '42501';
  end if;
  if (select count(*) from public.service_type
      where name in ('Standard cleaning', 'Deep cleaning')) <> 2 then
    raise exception 'Required service catalogue missing' using errcode = '23514';
  end if;
  return jsonb_build_object('run_id', p_run_id, 'already_seeded', false,
    'planned_accounts', 2, 'planned_properties', 2, 'planned_pending_bookings', 1,
    'planned_weekly_slots', 7, 'deletion_supported', false);
end;
$$;
revoke all on function public.preview_test_fixture(text,uuid,uuid,uuid,date)
  from public, anon, authenticated;
grant execute on function public.preview_test_fixture(text,uuid,uuid,uuid,date) to service_role;

create function public.seed_test_fixture(
  p_project_ref text, p_run_id uuid, p_owner_id uuid, p_provider_id uuid,
  p_fixture_date date
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_plan jsonb; v_property uuid; v_service uuid; v_booking uuid;
begin
  -- Concurrent retries of one run serialize. Account PK/FKs protect other runs.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_run_id::text, 16));
  v_plan := public.preview_test_fixture(p_project_ref, p_run_id, p_owner_id,
    p_provider_id, p_fixture_date);
  if (v_plan->>'already_seeded')::boolean then return v_plan; end if;
  insert into public.test_data_run(run_id,project_ref,owner_id,provider_id,fixture_date)
    values (p_run_id,p_project_ref,p_owner_id,p_provider_id,p_fixture_date);
  insert into public.user_account(user_id,email,role) values
    (p_owner_id,'owner.' || p_run_id::text || '@rental-test.invalid','owner'),
    (p_provider_id,'provider.' || p_run_id::text || '@rental-test.invalid','provider');
  insert into public.provider_profile(provider_id,bio,service_area,service_origin_address,
    hourly_rate,daily_rate,approval_status) values
    (p_provider_id,'[TEST] Synthetic provider - not a real service business',
     'Kuala Lumpur','[TEST] No real origin configured',40,280,'approved');
  insert into public.provider_capability(provider_id,service_type_id)
    select p_provider_id,service_type_id from public.service_type
      where name in ('Standard cleaning','Deep cleaning');
  insert into public.provider_weekly_slot(provider_id,weekday,start_time,end_time)
    select p_provider_id,d,time '08:00',time '18:00' from generate_series(1,7) as d;
  insert into public.property(owner_id,unit_name,building_name,address,bedrooms,size_sqft)
    values (p_owner_id,'[TEST] Unit A','[TEST] Fixture Building',
      '[TEST] Synthetic address - not a real rental unit',2,750)
    returning property_id into v_property;
  insert into public.property(owner_id,unit_name,building_name,address,bedrooms,size_sqft)
    values (p_owner_id,'[TEST] Unit B','[TEST] Fixture Building',
      '[TEST] Synthetic address - not a real rental unit',3,1000);
  select service_type_id into v_service from public.service_type where name = 'Standard cleaning';
  insert into public.booking(owner_id,provider_id,property_id,service_type_id,
    requested_start_at,requested_end_at,instructions,client_request_id,
    quote_basis,quoted_rate,quoted_duration_minutes,quoted_amount)
    values (p_owner_id,p_provider_id,v_property,v_service,
      (p_fixture_date + time '10:00') at time zone 'Asia/Kuala_Lumpur',
      (p_fixture_date + time '12:00') at time zone 'Asia/Kuala_Lumpur',
      '[TEST] Synthetic cleaning request. No real service or payment.',p_run_id,
      'hourly',40,120,80) returning booking_id into v_booking;
  -- Existing initial-status trigger records Pending. Never invent evidence,
  -- Completed histories, ratings, payments or successful external operations.
  return v_plan || jsonb_build_object('created',true,'booking_id',v_booking);
end;
$$;
revoke all on function public.seed_test_fixture(text,uuid,uuid,uuid,date)
  from public, anon, authenticated;
grant execute on function public.seed_test_fixture(text,uuid,uuid,uuid,date) to service_role;

-- Read-only review, NOT a deletion authorization/plan. Includes later manual
-- activity for either registered actor. Mixed-account dependencies are flagged;
-- prefix labels alone are NEVER evidence that a record is safe to delete.
create function public.inspect_test_run(p_project_ref text, p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_run public.test_data_run%rowtype; v_counts jsonb; v_samples jsonb; v_mixed bigint;
begin
  perform public.require_test_environment(p_project_ref);
  select * into v_run from public.test_data_run where run_id = p_run_id;
  if not found then raise exception 'Unknown test run' using errcode = '22023'; end if;
  with related as (select b.* from public.booking b where
      b.owner_id in (v_run.owner_id,v_run.provider_id) or
      b.provider_id in (v_run.owner_id,v_run.provider_id) or
      b.property_id in (select property_id from public.property where owner_id = v_run.owner_id))
  select jsonb_build_object(
    'accounts',(select count(*) from public.user_account where user_id in (v_run.owner_id,v_run.provider_id)),
    'properties',(select count(*) from public.property where owner_id = v_run.owner_id),
    'weekly_slots',(select count(*) from public.provider_weekly_slot where provider_id = v_run.provider_id),
    'unavailable_dates',(select count(*) from public.provider_unavailable_date where provider_id = v_run.provider_id),
    'capabilities',(select count(*) from public.provider_capability where provider_id = v_run.provider_id),
    'bookings',(select count(*) from related),
    'status_history',(select count(*) from public.booking_status_history where booking_id in (select booking_id from related)),
    'messages',(select count(*) from public.booking_message where booking_id in (select booking_id from related)),
    'reviews',(select count(*) from public.booking_review where booking_id in (select booking_id from related)),
    'evidence',(select count(*) from public.booking_evidence where booking_id in (select booking_id from related)),
    'upload_tickets',(select count(*) from public.evidence_upload where booking_id in (select booking_id from related)),
    'storage_metadata_objects',(select count(*) from storage.objects s where
       s.bucket_id = 'cleaning-evidence' and split_part(s.name,'/',1) in
         (select booking_id::text from related))) into v_counts;
  select count(*) into v_mixed from public.booking b left join public.property p using(property_id)
    where (b.owner_id in (v_run.owner_id,v_run.provider_id) or
      b.provider_id in (v_run.owner_id,v_run.provider_id) or p.owner_id = v_run.owner_id)
    and (b.owner_id <> v_run.owner_id or b.provider_id <> v_run.provider_id or
      p.owner_id is distinct from v_run.owner_id);
  select coalesce(jsonb_agg(booking_id),'[]'::jsonb) into v_samples from
    (select booking_id from public.booking where owner_id = v_run.owner_id or
      provider_id = v_run.provider_id order by created_at,booking_id limit 20) as sample;
  return jsonb_build_object('run_id',p_run_id,'data_source',v_run.data_source,
    'fixture_date',v_run.fixture_date,'review_after',v_run.review_after,
    'review_due',now() >= v_run.review_after,'counts',v_counts,'booking_id_sample',v_samples,
    'mixed_account_bookings',v_mixed,'deletion_supported',false,
    'requires_manual_review',true);
end;
$$;
revoke all on function public.inspect_test_run(text,uuid) from public, anon, authenticated;
grant execute on function public.inspect_test_run(text,uuid) to service_role;


-- MIGRATION 20261123000030_owner_booking_communication_limits.sql
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


-- MIGRATION 20261123000031_owner_verified_evidence.sql
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


-- MIGRATION 20261123000032_owner_explicit_app_privileges.sql
-- Least-privilege closure after migrations 001-018. Staging first.
-- Do not apply to an unreconciled legacy/shared schema. No data is deleted.
-- Supabase-managed auth/storage/extension privileges are deliberately untouched.
-- Execute in a transaction (the staged bundle and local runner enforce this).
set local search_path = pg_catalog;

-- Default privileges belong to the role that CREATES the object, not roles
-- it inherits. Our migration runner must always create as postgres. Do not
-- impersonate the platform-internal supabase_admin role to change its defaults.
alter default privileges for role postgres
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres
  revoke all on sequences from public, anon, authenticated, service_role;
-- Global PUBLIC EXECUTE cannot be removed with a schema-only REVOKE.
alter default privileges for role postgres
  revoke all on functions from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from public, anon, authenticated, service_role;

revoke create on schema public from public, anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

do $privileges$
declare
  v_table text;
  v_columns text;
  v_function record;
  v_tables constant text[] := array[
    'admin','tenant','rental_unit','tenancy','electricity_device','electricity_reading','tariff_plan','tariff_rate','bill','bill_tariff_detail','payment_transaction','maintenance_request','maintenance_update','announcement','announcement_recipient','conversation','message','audit_log','tenant_registration','chat_attachment_cleanup_queue',
    'user_account','property','provider_profile','service_type',
    'provider_capability','provider_weekly_slot','provider_unavailable_date',
    'booking','booking_status_history','booking_evidence','booking_message',
    'booking_review','app_deployment_environment','evidence_upload','test_data_run'
  ];
begin
  if current_user <> 'postgres' then
    raise exception 'App migrations must run as postgres' using errcode='42501';
  end if;
  -- Fail closed on schema drift instead of changing unrelated tables.
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in ('r','p','v','m','f','S')
      and not (c.relname=any(v_tables))
      and not exists(select 1 from pg_depend d where d.classid='pg_class'::regclass
        and d.objid=c.oid and d.deptype='e')
  ) then
    raise exception 'Unexpected public relation: reconcile schema before migration 019';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proowner<>'postgres'::regrole
      and not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass
        and d.objid=p.oid and d.deptype='e')) then
    raise exception 'Unexpected application function owner: reconcile before migration 019';
  end if;
  foreach v_table in array v_tables loop
    if v_table=any(array['admin','tenant','rental_unit','tenancy','electricity_device','electricity_reading','tariff_plan','tariff_rate','bill','bill_tariff_detail','payment_transaction','maintenance_request','maintenance_update','announcement','announcement_recipient','conversation','message','audit_log','tenant_registration','chat_attachment_cleanup_queue']) then continue; end if;
    if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=v_table and c.relkind in ('r','p')
        and c.relowner='postgres'::regrole) then
      raise exception 'Expected postgres-owned application table: %',v_table;
    end if;
    execute format('alter table public.%I enable row level security',v_table);
    execute format('revoke all on table public.%I from public,anon,authenticated,service_role',v_table);
    -- Table REVOKE does not remove old column-level grants.
    select string_agg(format('%I',attname),',') into v_columns from pg_attribute
      where attrelid=format('public.%I',v_table)::regclass and attnum>0 and not attisdropped;
    execute format('revoke all (%s) on table public.%I from public,anon,authenticated,service_role',v_columns,v_table);
  end loop;

  -- Reset only migration-owned, non-extension functions. Internal helpers
  -- stay uncallable; exact RPC signatures are explicitly granted below.
  for v_function in
    select p.oid::regprocedure as signature from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proowner='postgres'::regrole and p.prokind='f'
      and p.oid not in (select oid from integration_tenant_functions)
      and not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass
        and d.objid=p.oid and d.deptype='e')
  loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',v_function.signature);
  end loop;
end;
$privileges$;

-- Private internal state/functions have no client or service-role table API.
revoke all on schema app_private from public,anon,authenticated,service_role;
revoke all on all tables in schema app_private from public,anon,authenticated,service_role;
revoke all on all functions in schema app_private from public,anon,authenticated,service_role;
alter default privileges for role postgres in schema app_private
  revoke all on tables from public,anon,authenticated,service_role;
alter default privileges for role postgres in schema app_private
  revoke all on sequences from public,anon,authenticated,service_role;
alter default privileges for role postgres in schema app_private
  revoke all on functions from public,anon,authenticated,service_role;

-- SELECT is needed by RLS, Realtime and current direct read repositories.
-- RLS still limits own rows/booking participants; catalogue is authenticated.
grant select on public.user_account,public.property,public.provider_profile,
  public.service_type,public.provider_capability,public.provider_weekly_slot,
  public.provider_unavailable_date,public.booking,public.booking_status_history,
  public.booking_evidence,public.booking_message,public.booking_review,
  public.evidence_upload to authenticated;

grant insert(user_id,email,contact_number,role) on public.user_account to authenticated;
grant update(contact_number) on public.user_account to authenticated;
grant insert(owner_id,unit_name,building_name,address,bedrooms,size_sqft,
  cleaning_window_start,cleaning_window_end) on public.property to authenticated;
grant update(unit_name,building_name,address,bedrooms,size_sqft,
  cleaning_window_start,cleaning_window_end) on public.property to authenticated;
grant insert(provider_id,bio,service_area,service_origin_address,hourly_rate,daily_rate)
  on public.provider_profile to authenticated;
grant update(bio,service_area,service_origin_address,hourly_rate,daily_rate)
  on public.provider_profile to authenticated;
grant insert(provider_id,weekday,start_time,end_time)
  on public.provider_weekly_slot to authenticated;
grant update(weekday,start_time,end_time) on public.provider_weekly_slot to authenticated;
grant delete on public.provider_weekly_slot to authenticated;
grant insert(provider_id,unavailable_on) on public.provider_unavailable_date to authenticated;
grant delete on public.provider_unavailable_date to authenticated;
-- Preserve Pending Owner instructions edits; interval/status/quote use RPCs.
grant update(instructions) on public.booking to authenticated;

-- Do not leave an obsolete permissive creation policy behind a denied grant.
drop policy if exists booking_owner_insert on public.booking;

grant execute on function
  public.accept_pending_booking(uuid),
  public.transition_booking(uuid,public.booking_status_enum,text),
  public.revise_pending_booking(uuid,timestamptz,timestamptz,text),
  public.replace_provider_capabilities(uuid[]),
  public.list_approved_provider_directory(),
  public.find_eligible_providers(uuid,uuid,timestamptz,timestamptz),
  public.create_pending_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,text,text),
  public.send_booking_message(uuid,uuid,text),
  public.save_booking_review(uuid,integer,text),
  public.list_booking_contexts(),
  public.page_my_bookings(integer,timestamptz,uuid),
  public.booking_cards_by_ids(uuid[]),
  public.page_booking_messages(uuid,integer,timestamptz,uuid),
  public.page_booking_history(uuid,integer,timestamptz,uuid),
  public.owner_dashboard_summary(),
  public.begin_evidence_upload(uuid,uuid,text,text,integer,text,text),
  public.attach_evidence_upload(uuid,uuid),
  public.save_evidence_remarks(uuid,text),
  public.claim_evidence_cleanup(uuid),
  public.finish_evidence_cleanup(uuid,text),
  public.can_read_evidence_object(text),
  public.can_delete_evidence_object(text)
to authenticated;

-- Only non-sensitive deployment identity is readable before login.
grant execute on function public.get_app_environment() to anon,authenticated,service_role;

-- Server-only endpoint/maintenance tools; no broad direct business-table access.
grant execute on function
  public.claim_evidence_validation(uuid,uuid,uuid),
  public.finish_evidence_validation(uuid,uuid,text,text,integer,integer,integer,text),
  public.fail_evidence_validation(uuid,uuid,boolean),
  public.list_evidence_cleanup_batch(),
  public.claim_evidence_cleanup_batch(),
  public.finish_evidence_cleanup_batch(uuid,text),
  public.preview_test_fixture(text,uuid,uuid,uuid,date),
  public.seed_test_fixture(text,uuid,uuid,uuid,date),
  public.inspect_test_run(text,uuid)
to service_role;

-- App PKs are UUIDs, not sequences. Existing public sequences are not part of
-- this contract; the preflight must inventory any non-extension sequences.


-- MIGRATION 20261123000033_owner_provider_earnings.sql
-- Read-only earnings reporting. Quotes are NOT payments or net settlements.
-- No fee is invented and no historical quote is repriced/backfilled.
create index booking_provider_completed_report_idx on public.booking(provider_id)
  where current_status = 'Completed';
create index booking_completion_report_idx on public.booking_status_history(booking_id,changed_at)
  where new_status = 'Completed';

create function public.provider_earnings(
  p_period text default 'thisMonth',
  p_before_at timestamptz default null,
  p_before_id uuid default null,
  p_as_of timestamptz default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_as_of timestamptz := coalesce(p_as_of,statement_timestamp());
  v_today date;
  v_start date;
  v_result jsonb;
begin
  if v_actor is null or not exists(select 1 from public.user_account
    where user_id=v_actor and role='provider') then
    raise exception 'Provider authentication required' using errcode='42501';
  end if;
  if p_period is null or p_period not in ('last30','thisMonth','allTime') or
     (p_before_at is null) <> (p_before_id is null) or
     (p_before_at is not null and p_as_of is null) or
     not isfinite(v_as_of) or v_as_of > statement_timestamp() or
     (p_before_at is not null and (not isfinite(p_before_at) or p_before_at > v_as_of)) then
    raise exception 'Invalid earnings range or cursor' using errcode='22023';
  end if;
  v_today := (v_as_of at time zone 'Asia/Kuala_Lumpur')::date;
  v_start := case p_period when 'last30' then v_today-29
    when 'thisMonth' then date_trunc('month',v_today)::date else null end;
  with completed as materialized (
    select b.booking_id,b.quoted_amount,b.quote_basis,b.quoted_rate,
      b.quoted_duration_minutes,b.requested_start_at,b.requested_end_at,
      p.unit_name,p.building_name,s.name as service_name,h.completed_at
    from public.booking b
    join public.property p on p.property_id=b.property_id
    join public.service_type s on s.service_type_id=b.service_type_id
    left join lateral (
      select min(changed_at) as completed_at from public.booking_status_history
      where booking_id=b.booking_id and new_status='Completed'
    ) h on true
    where b.provider_id=v_actor and b.current_status='Completed'
  ), scoped as materialized (
    select * from completed where completed_at<=v_as_of and
      (v_start is null or completed_at >= (v_start::timestamp at time zone 'Asia/Kuala_Lumpur'))
  ), settings as (
    select coalesce(v_start,(min(completed_at) at time zone 'Asia/Kuala_Lumpur')::date,v_today) as first_day,
      case when p_period='allTime' and
        min(completed_at) < ((v_today-interval '10 years')::timestamp at time zone 'Asia/Kuala_Lumpur')
        then 'year' else 'month' end as long_unit
    from scoped
  ), bucket_settings as (
    select case when p_period='allTime' then date_trunc(long_unit,first_day)::date else first_day end as first_day,
      long_unit from settings
  ), bucket_days as (
    select distinct case p_period when 'last30' then first_day+((day::date-first_day)/7)*7
      when 'thisMonth' then greatest(first_day,date_trunc('week',day)::date)
      else date_trunc(long_unit,day)::date end as bucket_start
    from bucket_settings, lateral generate_series(first_day::timestamp,v_today::timestamp,
      case when p_period='allTime' and long_unit='year' then interval '1 year'
        when p_period='allTime' then interval '1 month' else interval '1 day' end) day
  ), bucket_ranges as (
    select bucket_start,coalesce(lead(bucket_start) over(order by bucket_start),v_today+1) as bucket_end
    from bucket_days
  ), buckets as (
    select r.bucket_start,r.bucket_end,count(s.booking_id) as jobs,
      count(s.booking_id) filter(where s.quoted_amount is null) as unpriced_jobs,
      coalesce(sum(s.quoted_amount),0) as gross
    from bucket_ranges r left join scoped s on
      s.completed_at >= (r.bucket_start::timestamp at time zone 'Asia/Kuala_Lumpur') and
      s.completed_at < (r.bucket_end::timestamp at time zone 'Asia/Kuala_Lumpur')
    group by r.bucket_start,r.bucket_end
  ), candidates as materialized (
    select * from scoped where p_before_at is null or
      (completed_at,booking_id)<(p_before_at,p_before_id)
    order by completed_at desc,booking_id desc limit 21
  ), page as materialized (
    select * from candidates order by completed_at desc,booking_id desc limit 20
  )
  select jsonb_build_object(
    'provider_id',v_actor,'currency','MYR','period',p_period,'as_of',v_as_of,
    'start_day',(select first_day from settings),'end_day',v_today,
    'bucket_unit',case p_period when 'last30' then 'sevenDays' when 'thisMonth' then 'week'
      else (select long_unit from settings) end,
    'jobs', (select count(*) from scoped),
    'unpriced_jobs',(select count(*) from scoped where quoted_amount is null),
    'undated_jobs',(select count(*) from completed where completed_at is null),
    'gross',(select coalesce(sum(quoted_amount),0) from scoped),
    'buckets',coalesce((select jsonb_agg(to_jsonb(buckets) order by bucket_start) from buckets),'[]'::jsonb),
    'items',coalesce((select jsonb_agg(to_jsonb(page) order by completed_at desc,booking_id desc) from page),'[]'::jsonb),
    'next_cursor',case when (select count(*) from candidates)>20 then
      (select jsonb_build_object('timestamp',completed_at,'id',booking_id)
       from page order by completed_at,booking_id limit 1) else null end
  ) into v_result;
  return v_result;
end;
$$;
revoke all on function public.provider_earnings(text,timestamptz,uuid,timestamptz)
  from public,anon,authenticated,service_role;
grant execute on function public.provider_earnings(text,timestamptz,uuid,timestamptz) to authenticated;


-- MIGRATION 20261123000034_owner_provider_profile_editor.sql
-- Own-profile editor, explicit mutable fields, no role/approval/score writes.
alter table public.provider_profile
  add column full_name text check(full_name is null or length(btrim(full_name)) between 2 and 60),
  add column avatar_color_index smallint not null default 0 check(avatar_color_index between 0 and 5),
  add column show_phone_to_owners boolean not null default false,
  add column profile_revision bigint not null default 1;

create function app_private.bump_provider_profile_revision()
returns trigger language plpgsql set search_path='' as $$
begin new.profile_revision:=old.profile_revision+1;return new;end;
$$;
revoke all on function app_private.bump_provider_profile_revision() from public,anon,authenticated,service_role;
create trigger bump_provider_profile_revision before update on public.provider_profile
  for each row execute function app_private.bump_provider_profile_revision();

-- Capability edits through the pre-existing setup route also invalidate drafts.
create function app_private.bump_capability_profile_revision()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  update public.provider_profile set profile_revision=profile_revision
    where provider_id=coalesce(new.provider_id,old.provider_id);
  return null;
end;
$$;
revoke all on function app_private.bump_capability_profile_revision() from public,anon,authenticated,service_role;
create trigger bump_capability_profile_revision after insert or delete on public.provider_capability
  for each row execute function app_private.bump_capability_profile_revision();

create function public.my_provider_profile()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_result jsonb;
begin
  if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor and role='provider') then
    raise exception 'Provider authentication required' using errcode='42501';
  end if;
  select jsonb_build_object(
    'provider_id',p.provider_id,'full_name',p.full_name,'bio',p.bio,
    'hourly_rate',p.hourly_rate,'daily_rate',p.daily_rate,'service_area',p.service_area,
    'service_origin_address',p.service_origin_address,'avatar_color_index',p.avatar_color_index,
    'show_phone_to_owners',p.show_phone_to_owners,'revision',p.profile_revision,
    'contact_number',a.contact_number,'email',u.email,'approval_status',p.approval_status,
    'rating_average',(select round(avg(rating),2) from public.booking_review where provider_id=v_actor),
    'review_count',(select count(*) from public.booking_review where provider_id=v_actor),
    'completed_jobs',(select count(*) from public.booking where provider_id=v_actor and current_status='Completed'),
    'active_jobs',(select count(*) from public.booking where provider_id=v_actor and
      current_status in ('Accepted','In Progress') and requested_start_at<statement_timestamp()+interval '7 days'
      and requested_end_at>statement_timestamp()),
    'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.service_type_id,'name',s.name,
      'selected',exists(select 1 from public.provider_capability c where c.provider_id=v_actor and c.service_type_id=s.service_type_id))
      order by s.name) from public.service_type s),'[]'::jsonb),
    'weekly_slots',coalesce((select jsonb_agg(jsonb_build_object('weekday',weekday,'start_time',start_time,'end_time',end_time)
      order by weekday,start_time) from public.provider_weekly_slot where provider_id=v_actor),'[]'::jsonb)
  ) into v_result from public.provider_profile p join public.user_account a on a.user_id=p.provider_id
    join auth.users u on u.id=p.provider_id where p.provider_id=v_actor;
  if v_result is null then raise exception 'Provider profile required' using errcode='P0002';end if;
  return v_result;
end;
$$;
revoke all on function public.my_provider_profile() from public,anon,authenticated,service_role;
grant execute on function public.my_provider_profile() to authenticated;

create function public.save_my_provider_profile(p_input jsonb,p_expected_revision bigint,p_expected_contact text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid:=auth.uid(); v_profile public.provider_profile%rowtype;
  v_contact text; v_phone text;v_hourly numeric;v_daily numeric;v_services uuid[];
begin
  if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor and role='provider') then
    raise exception 'Provider authentication required' using errcode='42501';
  end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' or
    exists(select 1 from jsonb_object_keys(p_input) k where k not in
      ('full_name','bio','service_area','service_origin_address','hourly_rate','daily_rate',
       'avatar_color_index','show_phone_to_owners','contact_number','service_type_ids')) or
    not (p_input ?& array['full_name','bio','service_area','service_origin_address','hourly_rate','daily_rate',
       'avatar_color_index','show_phone_to_owners','contact_number','service_type_ids']) then
    raise exception 'Only explicit editable profile fields are accepted' using errcode='22023';
  end if;
  if jsonb_typeof(p_input->'full_name')<>'string' or length(btrim(p_input->>'full_name')) not between 2 and 60 or
    jsonb_typeof(p_input->'bio')<>'string' or length(p_input->>'bio')>200 or
    jsonb_typeof(p_input->'service_area')<>'string' or length(btrim(p_input->>'service_area')) not between 1 and 200 or
    jsonb_typeof(p_input->'service_origin_address')<>'string' or length(btrim(p_input->>'service_origin_address')) not between 1 and 500 or
    jsonb_typeof(p_input->'show_phone_to_owners')<>'boolean' or
    jsonb_typeof(p_input->'avatar_color_index')<>'number' or
    (p_input->>'avatar_color_index')::numeric <> trunc((p_input->>'avatar_color_index')::numeric) or
    (p_input->>'avatar_color_index')::integer not between 0 and 5 or
    jsonb_typeof(p_input->'contact_number') not in ('null','string') or
    jsonb_typeof(p_input->'hourly_rate') not in ('number','null') or
    jsonb_typeof(p_input->'daily_rate') not in ('number','null') or
    jsonb_typeof(p_input->'service_type_ids')<>'array' or
    jsonb_array_length(p_input->'service_type_ids') not between 1 and 50 then
    raise exception 'Invalid profile fields' using errcode='22023';
  end if;
  v_phone:=nullif(btrim(p_input->>'contact_number'),'');
  if (v_phone is not null and (v_phone !~ '^\+?[0-9 ()-]+$' or
      length(regexp_replace(v_phone,'[^0-9]','','g')) not between 9 and 15)) or
      ((p_input->>'show_phone_to_owners')::boolean and v_phone is null) then
    raise exception 'Valid phone required when sharing contact' using errcode='22023';
  end if;
  v_hourly:=(p_input->>'hourly_rate')::numeric;v_daily:=(p_input->>'daily_rate')::numeric;
  if (v_hourly is null and v_daily is null) or
    (v_hourly is not null and (v_hourly<=0 or v_hourly>99999999.99 or round(v_hourly,2)<>v_hourly)) or
    (v_daily is not null and (v_daily<=0 or v_daily>99999999.99 or round(v_daily,2)<>v_daily)) then
    raise exception 'Positive hourly or daily rate with at most two decimals required' using errcode='22023';
  end if;
  select array_agg(value::uuid) into v_services from jsonb_array_elements_text(p_input->'service_type_ids');
  select * into v_profile from public.provider_profile where provider_id=v_actor for update;
  if not found then raise exception 'Provider profile required' using errcode='P0002';end if;
  select contact_number into v_contact from public.user_account where user_id=v_actor for update;
  if p_expected_revision is null or v_profile.profile_revision<>p_expected_revision or
    v_contact is distinct from p_expected_contact then
    raise exception 'Profile changed; reload before saving' using errcode='40001';
  end if;
  -- Existing capability operation serialises and protects confirmed bookings.
  -- Any failure rolls back contact, appearance, rates and capabilities together.
  perform public.replace_provider_capabilities(v_services);
  update public.user_account set contact_number=v_phone where user_id=v_actor;
  update public.provider_profile set full_name=btrim(p_input->>'full_name'),bio=btrim(p_input->>'bio'),
    service_area=btrim(p_input->>'service_area'),service_origin_address=btrim(p_input->>'service_origin_address'),
    hourly_rate=v_hourly,daily_rate=v_daily,avatar_color_index=(p_input->>'avatar_color_index')::smallint,
    show_phone_to_owners=(p_input->>'show_phone_to_owners')::boolean where provider_id=v_actor;
  return public.my_provider_profile();
end;
$$;
revoke all on function public.save_my_provider_profile(jsonb,bigint,text) from public,anon,authenticated,service_role;
grant execute on function public.save_my_provider_profile(jsonb,bigint,text) to authenticated;

-- Phone sharing is enforced by server, never by a widget-only privacy switch.
-- No directory-wide contacts, email or private origin are exposed.
create function public.booking_provider_contact(p_booking_id uuid)
returns text language sql stable security definer set search_path='' as $$
  select a.contact_number from public.booking b
    join public.provider_profile p on p.provider_id=b.provider_id
    join public.user_account a on a.user_id=p.provider_id
  where auth.uid() is not null and b.booking_id=p_booking_id and b.owner_id=auth.uid()
    and b.current_status in ('Accepted','In Progress') and p.show_phone_to_owners;
$$;
revoke all on function public.booking_provider_contact(uuid) from public,anon,authenticated,service_role;
grant execute on function public.booking_provider_contact(uuid) to authenticated;


-- MIGRATION 20261123000035_owner_booking_notifications.sql
-- In-app notifications are real, existing booking events, not fabricated alerts.
-- Receipts are private per user; no direct client table grants or write events.
create table app_private.notification_read (
  user_id uuid not null references public.user_account(user_id) on delete cascade,
  event_id uuid not null references public.booking_status_history(status_history_id) on delete cascade,
  read_at timestamptz not null default statement_timestamp(),
  primary key(user_id,event_id)
);
alter table app_private.notification_read enable row level security;
revoke all on table app_private.notification_read from public,anon,authenticated,service_role;

create function app_private.notification_events(p_actor uuid)
returns table(id uuid,booking_id uuid,event_status text,happened_at timestamptz,
  unit_name text,building_name text,service_name text,is_read boolean,actionable boolean)
language sql stable set search_path='' as $$
  select h.status_history_id,b.booking_id,h.new_status::text,h.changed_at,
    p.unit_name,p.building_name,s.name,(r.event_id is not null),
    ((b.provider_id=p_actor and b.current_status='Pending' and h.new_status='Pending') or
     (b.owner_id=p_actor and b.current_status='Completed' and h.new_status='Completed' and
      not exists(select 1 from public.booking_review v where v.booking_id=b.booking_id)))
  from public.booking_status_history h join public.booking b on b.booking_id=h.booking_id
  join public.property p on p.property_id=b.property_id
  join public.service_type s on s.service_type_id=b.service_type_id
  left join app_private.notification_read r on r.user_id=p_actor and r.event_id=h.status_history_id
  where (b.owner_id=p_actor or b.provider_id=p_actor) and h.changed_by_user_id<>p_actor;
$$;
revoke all on function app_private.notification_events(uuid) from public,anon,authenticated,service_role;

create function public.page_my_notifications(p_filter text default 'all',p_limit integer default 20,
  p_before_at timestamptz default null,p_before_id uuid default null,p_as_of timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_as_of timestamptz;v_result jsonb;
begin
  if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor) then
    raise exception 'Authentication required' using errcode='42501';end if;
  if p_filter is null or p_filter not in ('all','unread','action') or p_limit is null or p_limit not between 1 and 50 or
     ((p_before_at is null)<>(p_before_id is null)) then
    raise exception 'Invalid notification page' using errcode='22023';end if;
  v_as_of:=least(coalesce(p_as_of,statement_timestamp()),statement_timestamp());
  with eligible as materialized (
    select * from app_private.notification_events(v_actor) where happened_at<=v_as_of
  ), candidates as materialized (
    select * from eligible where (p_filter='all' or (p_filter='unread' and not is_read) or
      (p_filter='action' and actionable)) and
      (p_before_at is null or (happened_at,id)<(p_before_at,p_before_id))
    order by happened_at desc,id desc limit p_limit+1
  ), visible as materialized (
    select * from candidates order by happened_at desc,id desc limit p_limit
  ) select jsonb_build_object('recipient_id',v_actor,'as_of',v_as_of,'filter',p_filter,
    'total_count',(select count(*) from eligible),
    'unread_count',(select count(*) from eligible where not is_read),
    'action_count',(select count(*) from eligible where actionable),
    'items',coalesce((select jsonb_agg(to_jsonb(v) order by happened_at desc,id desc) from visible v),'[]'::jsonb),
    'next_cursor',case when (select count(*) from candidates)>p_limit then
      (select jsonb_build_object('timestamp',happened_at,'id',id) from visible order by happened_at,id limit 1)
      else null end) into v_result;
  return v_result;
end;
$$;
revoke all on function public.page_my_notifications(text,integer,timestamptz,uuid,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.page_my_notifications(text,integer,timestamptz,uuid,timestamptz) to authenticated;

create function public.read_my_notifications(p_ids uuid[] default null,p_through_at timestamptz default null)
returns integer language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_count integer;
begin
  if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor) then
    raise exception 'Authentication required' using errcode='42501';end if;
  -- Explicit IDs OR a server-snapshot boundary; never a recipient supplied by App.
  if (p_ids is null)=(p_through_at is null) or
     (p_ids is not null and (cardinality(p_ids) not between 1 and 100 or array_position(p_ids,null) is not null)) then
    raise exception 'Specify notification IDs or a snapshot boundary' using errcode='22023';end if;
  if p_ids is not null and exists(select 1 from unnest(p_ids) i where
    not exists(select 1 from app_private.notification_events(v_actor) e where e.id=i)) then
    raise exception 'Notification unavailable' using errcode='42501';end if;
  insert into app_private.notification_read(user_id,event_id)
    select v_actor,id from app_private.notification_events(v_actor)
    where not is_read and ((p_ids is not null and id=any(p_ids)) or
      (p_through_at is not null and happened_at<=least(p_through_at,statement_timestamp())))
    on conflict do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function public.read_my_notifications(uuid[],timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.read_my_notifications(uuid[],timestamptz) to authenticated;


-- MIGRATION 20261123000036_owner_conversation_inbox.sql
-- One thread per booking, not per display name. No contact/email/address leaks.
-- Active bookings can start an empty chat; closed bookings retain existing chat.
create function public.page_my_conversations(p_limit integer default 20,
  p_before_at timestamptz default null,p_before_id uuid default null,
  p_as_of timestamptz default null,p_search text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_as_of timestamptz;v_search text;v_result jsonb;
begin
  if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor) then
    raise exception 'Authentication required' using errcode='42501';end if;
  if p_limit is null or p_limit not between 1 and 50 or p_search is null or
     length(p_search)>80 or ((p_before_at is null)<>(p_before_id is null)) or
     (p_before_at is not null and p_as_of is null) then
    raise exception 'Invalid conversation page' using errcode='22023';end if;
  v_search:=lower(btrim(p_search));
  v_as_of:=least(coalesce(p_as_of,statement_timestamp()),statement_timestamp());
  if p_before_at>v_as_of then raise exception 'Invalid cursor' using errcode='22023';end if;
  with eligible as (
    select b.booking_id,b.current_status::text as status,
      case when b.owner_id=v_actor then coalesce(nullif(btrim(pp.full_name),''),'Cleaning Service Provider')
        else 'Property Owner' end as counterpart_name,
      p.unit_name,p.building_name,s.name as service_name,
      left(coalesce(m.body,''),160) as last_message,
      coalesce(m.created_at,b.created_at) as last_at
    from public.booking b join public.property p on p.property_id=b.property_id
      join public.service_type s on s.service_type_id=b.service_type_id
      left join public.provider_profile pp on pp.provider_id=b.provider_id
      left join lateral (
        select body,created_at from public.booking_message
        where booking_id=b.booking_id and created_at<=v_as_of
        order by created_at desc,message_id desc limit 1
      ) m on true
    where (b.owner_id=v_actor or b.provider_id=v_actor) and b.created_at<=v_as_of
      and (b.current_status in ('Accepted','In Progress') or m.created_at is not null)
  ), candidates as materialized (
    select * from eligible where (p_before_at is null or (last_at,booking_id)<(p_before_at,p_before_id))
      and (v_search='' or position(v_search in lower(counterpart_name||' '||unit_name||' '||building_name||' '||service_name))>0)
    order by last_at desc,booking_id desc limit p_limit+1
  ), visible as materialized (
    select * from candidates order by last_at desc,booking_id desc limit p_limit
  ) select jsonb_build_object('recipient_id',v_actor,'as_of',v_as_of,'search',btrim(p_search),
    'items',coalesce((select jsonb_agg(to_jsonb(v) order by last_at desc,booking_id desc) from visible v),'[]'::jsonb),
    'has_more',(select count(*) from candidates)>p_limit,
    'next_cursor',case when (select count(*) from candidates)>p_limit then
      (select jsonb_build_object('timestamp',last_at,'id',booking_id) from visible order by last_at,booking_id limit 1)
      else null end) into v_result;
  return v_result;
end;
$$;
revoke all on function public.page_my_conversations(integer,timestamptz,uuid,timestamptz,text)
  from public,anon,authenticated,service_role;
grant execute on function public.page_my_conversations(integer,timestamptz,uuid,timestamptz,text) to authenticated;


-- MIGRATION 20261123000037_owner_owner_workspace.sql
-- Owner profile and property management: explicit actor scope + revision checks.
alter table public.user_account add column account_revision bigint not null default 1;
alter table public.property add column property_revision bigint not null default 1;

create function app_private.bump_workspace_revision() returns trigger
language plpgsql set search_path='' as $$
begin
 if tg_table_name='user_account' then new.account_revision:=old.account_revision+1;
 else new.property_revision:=old.property_revision+1;end if;
 return new;
end;$$;
revoke all on function app_private.bump_workspace_revision() from public,anon,authenticated,service_role;
create trigger bump_account_revision before update on public.user_account
 for each row execute function app_private.bump_workspace_revision();
create trigger bump_property_revision before update on public.property
 for each row execute function app_private.bump_workspace_revision();

create function public.my_owner_profile() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_result jsonb;
begin
 select jsonb_build_object('actor_id',a.user_id,'full_name',a.full_name,
  'email',u.email,'contact_number',a.contact_number,'revision',a.account_revision,
  'property_count',(select count(*) from public.property where owner_id=v_actor))
 into v_result from public.user_account a join auth.users u on u.id=a.user_id
 where a.user_id=v_actor and a.role='owner';
 if v_result is null then raise exception 'Owner authentication required' using errcode='42501';end if;
 return v_result;
end;$$;
revoke all on function public.my_owner_profile() from public,anon,authenticated,service_role;
grant execute on function public.my_owner_profile() to authenticated;

create function public.save_my_owner_profile(p_input jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_revision bigint;v_name text;v_phone text;
begin
 if jsonb_typeof(p_input) is distinct from 'object' or p_revision is null or p_revision<1 or
  not(p_input ?& array['full_name','contact_number']) or
  exists(select 1 from jsonb_object_keys(p_input) k where k not in ('full_name','contact_number')) or
  jsonb_typeof(p_input->'full_name') is distinct from 'string' or
  jsonb_typeof(p_input->'contact_number') not in ('string','null') then
  raise exception 'Invalid owner profile fields' using errcode='22023';end if;
 v_name:=btrim(p_input->>'full_name');v_phone:=nullif(btrim(p_input->>'contact_number'),'');
 if length(v_name) not between 2 and 60 or
  (v_phone is not null and (length(v_phone)>25 or v_phone !~ '^\+?[0-9 ()-]{7,25}$')) then
  raise exception 'Invalid name or contact number' using errcode='22023';end if;
 select account_revision into v_revision from public.user_account
 where user_id=v_actor and role='owner' for update;
 if not found then raise exception 'Owner authentication required' using errcode='42501';end if;
 if v_revision<>p_revision then raise exception 'Profile changed. Reload before saving' using errcode='40001';end if;
 update public.user_account set full_name=v_name,contact_number=v_phone where user_id=v_actor;
 return public.my_owner_profile();
end;$$;
revoke all on function public.save_my_owner_profile(jsonb,bigint) from public,anon,authenticated,service_role;
grant execute on function public.save_my_owner_profile(jsonb,bigint) to authenticated;

create function public.page_my_properties(p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_result jsonb;
begin
 if v_actor is null or not exists(select 1 from public.user_account where user_id=v_actor and role='owner') then
  raise exception 'Owner authentication required' using errcode='42501';end if;
 if (p_before_at is null)<>(p_before_id is null) then raise exception 'Invalid property cursor' using errcode='22023';end if;
 with candidates as materialized (
  select p.*, (select count(*) from public.booking b where b.property_id=p.property_id and b.owner_id=v_actor) as total,
   (select count(*) from public.booking b where b.property_id=p.property_id and b.owner_id=v_actor and b.current_status in ('Pending','Accepted','In Progress')) as open,
   (select count(*) from public.booking b where b.property_id=p.property_id and b.owner_id=v_actor and b.current_status='Completed') as done
  from public.property p where owner_id=v_actor and
   (p_before_at is null or (p.created_at,p.property_id)<(p_before_at,p_before_id))
  order by created_at desc,property_id desc limit 21
 ), page as materialized (select * from candidates order by created_at desc,property_id desc limit 20)
 select jsonb_build_object('actor_id',v_actor,
  'total_count',(select count(*) from public.property where owner_id=v_actor),
  'items',coalesce((select jsonb_agg(to_jsonb(page)-'owner_id' order by created_at desc,property_id desc) from page),'[]'::jsonb),
  'next_cursor',case when (select count(*) from candidates)>20 then
   (select jsonb_build_object('timestamp',created_at,'id',property_id) from page order by created_at,property_id limit 1) else null end)
 into v_result;
 return v_result;
end;$$;
revoke all on function public.page_my_properties(timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.page_my_properties(timestamptz,uuid) to authenticated;

create function public.my_property(p_property_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_result jsonb;
begin
 select to_jsonb(p)-'owner_id'||jsonb_build_object('actor_id',v_actor,
  'total',(select count(*) from public.booking where property_id=p.property_id and owner_id=v_actor))
 into v_result from public.property p join public.user_account a on a.user_id=p.owner_id
 where p.property_id=p_property_id and p.owner_id=v_actor and a.role='owner';
 if v_result is null then raise exception 'Property unavailable' using errcode='42501';end if;
 return v_result;
end;$$;
revoke all on function public.my_property(uuid) from public,anon,authenticated,service_role;
grant execute on function public.my_property(uuid) to authenticated;

create function public.save_my_property(p_property_id uuid,p_revision bigint,p_input jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_revision bigint;
begin
 if p_revision is null or p_revision<1 or jsonb_typeof(p_input) is distinct from 'object' or
  not(p_input ?& array['unit_name','building_name','address','bedrooms','size_sqft','cleaning_window_start','cleaning_window_end']) or
  exists(select 1 from jsonb_object_keys(p_input) k where k not in
    ('unit_name','building_name','address','bedrooms','size_sqft','cleaning_window_start','cleaning_window_end')) then
   raise exception 'Invalid property fields' using errcode='22023';end if;
 if jsonb_typeof(p_input->'unit_name') is distinct from 'string' or
  jsonb_typeof(p_input->'building_name') is distinct from 'string' or
  jsonb_typeof(p_input->'address') is distinct from 'string' or
  jsonb_typeof(p_input->'bedrooms') is distinct from 'number' or
  jsonb_typeof(p_input->'size_sqft') is distinct from 'number' or
  jsonb_typeof(p_input->'cleaning_window_start') is distinct from 'string' or
  jsonb_typeof(p_input->'cleaning_window_end') is distinct from 'string' or
  length(btrim(p_input->>'unit_name')) not between 1 and 100 or
  length(btrim(p_input->>'building_name')) not between 1 and 150 or
  length(btrim(p_input->>'address')) not between 1 and 500 or
  (p_input->>'bedrooms') !~ '^[0-9]+$' or (p_input->>'size_sqft') !~ '^[0-9]+$' or
  (p_input->>'bedrooms')::numeric not between 1 and 100 or
  (p_input->>'size_sqft')::numeric not between 1 and 1000000 or
  (p_input->>'cleaning_window_start') !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:00)?$' or
  (p_input->>'cleaning_window_end') !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:00)?$' then
   raise exception 'Invalid property values' using errcode='22023';end if;
 if (p_input->>'cleaning_window_start')::time>=(p_input->>'cleaning_window_end')::time then
  raise exception 'Invalid cleaning window' using errcode='22023';end if;
 select property_revision into v_revision from public.property where property_id=p_property_id and owner_id=v_actor
  and exists(select 1 from public.user_account where user_id=v_actor and role='owner') for update;
 if not found then raise exception 'Property unavailable' using errcode='42501';end if;
 if v_revision<>p_revision then raise exception 'Property changed. Reload before saving' using errcode='40001';end if;
 update public.property set unit_name=btrim(p_input->>'unit_name'),building_name=btrim(p_input->>'building_name'),
  address=btrim(p_input->>'address'),bedrooms=(p_input->>'bedrooms')::integer,size_sqft=(p_input->>'size_sqft')::integer,
  cleaning_window_start=(p_input->>'cleaning_window_start')::time,cleaning_window_end=(p_input->>'cleaning_window_end')::time
  where property_id=p_property_id and owner_id=v_actor;
 -- Existing property-window lock/confirmed-booking guard still applies.
 return public.my_property(p_property_id);
end;$$;
revoke all on function public.save_my_property(uuid,bigint,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.save_my_property(uuid,bigint,jsonb) to authenticated;

create index property_owner_cursor_idx on public.property(owner_id,created_at desc,property_id desc);
create index booking_owner_property_cursor_idx on public.booking(owner_id,property_id,created_at desc,booking_id desc);
create function public.page_my_property_bookings(p_property_id uuid,p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_rows jsonb;
begin
 if not exists(select 1 from public.property where property_id=p_property_id and owner_id=v_actor) then
  raise exception 'Property unavailable' using errcode='42501';end if;
 if (p_before_at is null)<>(p_before_id is null) then raise exception 'Invalid booking cursor' using errcode='22023';end if;
 select coalesce(jsonb_agg(card order by created_at desc,booking_id desc),'[]'::jsonb) into v_rows from (
  select b.created_at,b.booking_id,to_jsonb(b)||jsonb_build_object('unit_name',p.unit_name,
   'building_name',p.building_name,'service_name',s.name) as card
  from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
  where b.property_id=p_property_id and b.owner_id=v_actor and
   (p_before_at is null or (b.created_at,b.booking_id)<(p_before_at,p_before_id))
  order by b.created_at desc,b.booking_id desc limit 21) bounded;
 return public.pack_cursor_page(v_rows,20,'created_at','booking_id')||jsonb_build_object('actor_id',v_actor);
end;$$;
revoke all on function public.page_my_property_bookings(uuid,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.page_my_property_bookings(uuid,timestamptz,uuid) to authenticated;


-- MIGRATION 20261123000038_owner_workspace_reports.sql
-- Read-only reports. Saved completed quote value is not a paid transaction.
create function public.owner_spending(p_period text default 'allTime',p_before_at timestamptz default null,
 p_before_id uuid default null,p_as_of timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_as_of timestamptz:=coalesce(p_as_of,statement_timestamp());v_start date;v_month date;v_result jsonb;
begin
 if not exists(select 1 from public.user_account where user_id=v_actor and role='owner') then
  raise exception 'Owner authentication required' using errcode='42501';end if;
 if p_period is null or p_period not in ('last30','thisMonth','allTime') or
  (p_before_at is null)<>(p_before_id is null) or (p_before_at is not null and p_as_of is null) or
  not isfinite(v_as_of) or v_as_of>statement_timestamp() or p_before_at>v_as_of then
  raise exception 'Invalid spending range' using errcode='22023';end if;
 v_month:=date_trunc('month',v_as_of at time zone 'Asia/Kuala_Lumpur')::date;
 v_start:=case p_period when 'thisMonth' then v_month when 'last30' then (v_as_of at time zone 'Asia/Kuala_Lumpur')::date-29 else null end;
 with completed as materialized (
  select b.booking_id,b.provider_id,b.quoted_amount,p.unit_name,p.building_name,s.name as service_name,
   coalesce(nullif(btrim(pp.full_name),''),'Cleaning Service Provider') as provider_name,h.completed_at
  from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
   left join public.provider_profile pp on pp.provider_id=b.provider_id
   left join lateral (select min(changed_at) as completed_at from public.booking_status_history
    where booking_id=b.booking_id and new_status='Completed') h on true
  where b.owner_id=v_actor and b.current_status='Completed'
 ), dated as materialized (select * from completed where completed_at<=v_as_of),
 scoped as materialized (select * from dated where v_start is null or completed_at>=(v_start::timestamp at time zone 'Asia/Kuala_Lumpur')),
 candidates as materialized (select * from scoped where p_before_at is null or (completed_at,booking_id)<(p_before_at,p_before_id)
  order by completed_at desc,booking_id desc limit 21),
 page as materialized (select * from candidates order by completed_at desc,booking_id desc limit 20),
 providers as (select provider_id,provider_name,count(*) as jobs,coalesce(sum(quoted_amount),0) as gross
  from scoped group by provider_id,provider_name order by gross desc,provider_id limit 10)
 select jsonb_build_object('actor_id',v_actor,'as_of',v_as_of,'period',p_period,'currency','MYR',
  'gross',(select coalesce(sum(quoted_amount),0) from scoped),'jobs',(select count(*) from scoped),
  'unpriced',(select count(*) from scoped where quoted_amount is null),'undated',(select count(*) from completed where completed_at is null),
  'this_month',(select coalesce(sum(quoted_amount),0) from dated where completed_at>=(v_month::timestamp at time zone 'Asia/Kuala_Lumpur')),
  'last_month',(select coalesce(sum(quoted_amount),0) from dated where completed_at>=((v_month-interval '1 month')::timestamp at time zone 'Asia/Kuala_Lumpur')
   and completed_at<(v_month::timestamp at time zone 'Asia/Kuala_Lumpur')),
  'providers',coalesce((select jsonb_agg(to_jsonb(providers) order by gross desc,provider_id) from providers),'[]'::jsonb),
  'items',coalesce((select jsonb_agg(to_jsonb(page) order by completed_at desc,booking_id desc) from page),'[]'::jsonb),
  'next_cursor',case when (select count(*) from candidates)>20 then
   (select jsonb_build_object('timestamp',completed_at,'id',booking_id) from page order by completed_at,booking_id limit 1) else null end)
 into v_result;return v_result;
end;$$;
revoke all on function public.owner_spending(text,timestamptz,uuid,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.owner_spending(text,timestamptz,uuid,timestamptz) to authenticated;

create function public.my_provider_statistics() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_as_of timestamptz:=statement_timestamp();v_week date;v_result jsonb;
begin
 if not exists(select 1 from public.user_account where user_id=v_actor and role='provider') then
  raise exception 'Provider authentication required' using errcode='42501';end if;
 v_week:=date_trunc('week',v_as_of at time zone 'Asia/Kuala_Lumpur')::date;
 with jobs as materialized (
  select b.booking_id,b.owner_id,b.current_status,b.created_at,
   (select min(changed_at) from public.booking_status_history where booking_id=b.booking_id and new_status='Completed' and changed_at<=v_as_of) as completed_at,
   exists(select 1 from public.booking_status_history where booking_id=b.booking_id and new_status='Accepted' and changed_at<=v_as_of) as ever_accepted,
   d.new_status as decision,d.changed_at as decided_at
  from public.booking b left join lateral (
   select new_status,changed_at from public.booking_status_history where booking_id=b.booking_id and
    changed_by_user_id=v_actor and new_status in ('Accepted','Declined') and changed_at<=v_as_of
   order by changed_at,status_history_id limit 1) d on true
  where b.provider_id=v_actor and b.created_at<=v_as_of
 ), weeks as (
  select (v_week-n*7)::date as week_start,(select count(*) from jobs where current_status='Completed' and
    completed_at>=((v_week-n*7)::timestamp at time zone 'Asia/Kuala_Lumpur') and
    completed_at<((v_week-n*7+7)::timestamp at time zone 'Asia/Kuala_Lumpur')) as jobs
  from generate_series(7,0,-1) n
 ), ratings as (select rating,count(*) as count from public.booking_review where provider_id=v_actor group by rating)
 select jsonb_build_object('actor_id',v_actor,'as_of',v_as_of,'total',(select count(*) from jobs),
  'accepted',(select count(*) from jobs where ever_accepted),'completed',(select count(*) from jobs where current_status='Completed'),
  'closed_other',(select count(*) from jobs where current_status in ('Cancelled','Declined')),
  'decisions',(select count(*) from jobs where decision is not null),'accepted_decisions',(select count(*) from jobs where decision='Accepted'),
  'response_minutes',(select round(avg(extract(epoch from(decided_at-created_at))/60),1) from jobs where decided_at>=created_at),
  'repeat_jobs',(select coalesce(sum(greatest(n-1,0)),0) from (select count(*) as n from jobs where current_status='Completed' group by owner_id) r),
  'weeks',(select jsonb_agg(to_jsonb(weeks) order by week_start) from weeks),
  'ratings',coalesce((select jsonb_object_agg(rating,count) from ratings),'{}'::jsonb),
  'undated_completions',(select count(*) from jobs where current_status='Completed' and completed_at is null)) into v_result;
 return v_result;
end;$$;
revoke all on function public.my_provider_statistics() from public,anon,authenticated,service_role;
grant execute on function public.my_provider_statistics() to authenticated;


-- MIGRATION 20261123000039_owner_test_fixture_cleanup.sql
-- Administrator-only, preview/confirm cleanup of an EXACT registered test run.
-- Does not delete Auth identities, Storage objects, or any worked-on booking.
create function public.preview_test_fixture_cleanup(p_project_ref text,p_run_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_run public.test_data_run%rowtype;v_inventory jsonb;v_reasons text[]:='{}';v_digest jsonb;
begin
 perform public.require_test_environment(p_project_ref);
 select * into v_run from public.test_data_run where run_id=p_run_id;
 if not found then raise exception 'Unknown test run' using errcode='22023';end if;
 v_inventory:=public.inspect_test_run(p_project_ref,p_run_id);
 if not exists(select 1 from auth.users where id=v_run.owner_id and email='owner.'||p_run_id::text||'@rental-test.invalid') or
  not exists(select 1 from auth.users where id=v_run.provider_id and email='provider.'||p_run_id::text||'@rental-test.invalid') or
  not exists(select 1 from public.user_account where user_id=v_run.owner_id and role='owner' and email='owner.'||p_run_id::text||'@rental-test.invalid') or
  not exists(select 1 from public.user_account where user_id=v_run.provider_id and role='provider' and email='provider.'||p_run_id::text||'@rental-test.invalid') then
  v_reasons:=array_append(v_reasons,'Test identity changed');end if;
 if (v_inventory->>'mixed_account_bookings')::bigint<>0 then v_reasons:=array_append(v_reasons,'Mixed-account bookings');end if;
 if exists(select 1 from public.booking where (owner_id=v_run.owner_id or provider_id=v_run.provider_id) and
  current_status not in ('Pending','Declined','Cancelled')) or
  exists(select 1 from public.booking_status_history h join public.booking b using(booking_id)
   where (b.owner_id=v_run.owner_id or b.provider_id=v_run.provider_id) and h.new_status in ('Accepted','In Progress','Completed')) then
  v_reasons:=array_append(v_reasons,'Accepted or worked-on booking history');end if;
 if (v_inventory->'counts'->>'messages')::bigint>0 or (v_inventory->'counts'->>'reviews')::bigint>0 or
  (v_inventory->'counts'->>'evidence')::bigint>0 or (v_inventory->'counts'->>'upload_tickets')::bigint>0 or
  (v_inventory->'counts'->>'storage_metadata_objects')::bigint>0 then
  v_reasons:=array_append(v_reasons,'Chat, reviews, evidence or files require manual review');end if;
 if (v_inventory->'counts'->>'bookings')::bigint>100 or (v_inventory->'counts'->>'properties')::bigint>100 or
  (v_inventory->'counts'->>'status_history')::bigint>500 then
  v_reasons:=array_append(v_reasons,'Run exceeds small fixture cleanup limits');end if;
 -- Bounded eligible runs only. Never return private row content to the caller.
 if cardinality(v_reasons)=0 then
  select jsonb_build_object('run',to_jsonb(v_run),
   'accounts',(select jsonb_agg(to_jsonb(a) order by user_id) from public.user_account a where user_id in (v_run.owner_id,v_run.provider_id)),
   'profile',(select to_jsonb(p) from public.provider_profile p where provider_id=v_run.provider_id),
   'properties',(select jsonb_agg(to_jsonb(p) order by property_id) from public.property p where owner_id=v_run.owner_id),
   'slots',(select jsonb_agg(to_jsonb(s) order by slot_id) from public.provider_weekly_slot s where provider_id=v_run.provider_id),
   'dates',(select jsonb_agg(to_jsonb(d) order by unavailable_on) from public.provider_unavailable_date d where provider_id=v_run.provider_id),
   'capabilities',(select jsonb_agg(to_jsonb(c) order by service_type_id) from public.provider_capability c where provider_id=v_run.provider_id),
   'bookings',(select jsonb_agg(to_jsonb(b) order by booking_id) from public.booking b where owner_id=v_run.owner_id or provider_id=v_run.provider_id),
   'history',(select jsonb_agg(to_jsonb(h) order by status_history_id) from public.booking_status_history h join public.booking b using(booking_id)
    where b.owner_id=v_run.owner_id or b.provider_id=v_run.provider_id)) into v_digest;
 end if;
 return jsonb_build_object('run_id',p_run_id,'project_ref',p_project_ref,'counts',v_inventory->'counts',
  'eligible',cardinality(v_reasons)=0,'blockers',to_jsonb(v_reasons),
  'fingerprint',case when v_digest is not null then md5(v_digest::text) else null end,
  'auth_users_deleted',false,'storage_objects_deleted',false);
end;$$;
revoke all on function public.preview_test_fixture_cleanup(text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.preview_test_fixture_cleanup(text,uuid) to service_role;

create function public.cleanup_test_fixture(p_project_ref text,p_run_id uuid,p_fingerprint text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_run public.test_data_run%rowtype;v_plan jsonb;
begin
 perform public.require_test_environment(p_project_ref);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_run_id::text,16));
 select * into v_run from public.test_data_run where run_id=p_run_id for update;
 if not found then raise exception 'Unknown test run. Nothing deleted' using errcode='22023';end if;
 -- Prevent new FK-linked bookings/messages/uploads or reassigned identities
 -- between scope validation and removal. Re-check with fresh READ COMMITTED
 -- statements AFTER acquiring locks, not the earlier operator preview.
 if current_setting('transaction_isolation')<>'read committed' then
  raise exception 'Cleanup requires read committed' using errcode='25000';end if;
 perform id from auth.users where id in (v_run.owner_id,v_run.provider_id) order by id for update;
 perform user_id from public.user_account where user_id in (v_run.owner_id,v_run.provider_id) order by user_id for update;
 perform provider_id from public.provider_profile where provider_id=v_run.provider_id for update;
 perform property_id from public.property where owner_id=v_run.owner_id order by property_id for update;
 perform booking_id from public.booking where owner_id=v_run.owner_id or provider_id=v_run.provider_id order by booking_id for update;
 v_plan:=public.preview_test_fixture_cleanup(p_project_ref,p_run_id);
 if not (v_plan->>'eligible')::boolean then raise exception 'Test run is not safe for automatic cleanup' using errcode='42501';end if;
 if p_fingerprint is null or p_fingerprint is distinct from v_plan->>'fingerprint' then
  raise exception 'Test run changed. Review a fresh cleanup preview' using errcode='40001';end if;
 -- Only pending/never-accepted, file-free, unmixed records reached this point.
 delete from public.booking where owner_id=v_run.owner_id and provider_id=v_run.provider_id;
 delete from public.property where owner_id=v_run.owner_id;
 delete from public.provider_unavailable_date where provider_id=v_run.provider_id;
 delete from public.provider_weekly_slot where provider_id=v_run.provider_id;
 delete from public.provider_capability where provider_id=v_run.provider_id;
 delete from public.provider_profile where provider_id=v_run.provider_id;
 delete from public.user_account where user_id in (v_run.owner_id,v_run.provider_id);
 delete from public.test_data_run where run_id=p_run_id;
 return v_plan||jsonb_build_object('cleaned',true,'auth_users_retained',2,'reseed_supported',true);
end;$$;
revoke all on function public.cleanup_test_fixture(text,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.cleanup_test_fixture(text,uuid,text) to service_role;


-- MIGRATION 20261123000040_owner_message_read_receipts.sql
-- Own-account receipts only. No peer read-status disclosure or new table grants.
create table app_private.message_read_receipt (
 recipient_id uuid not null references public.user_account(user_id) on delete cascade,
 message_id uuid not null references public.booking_message(message_id) on delete cascade,
 read_at timestamptz not null default clock_timestamp(),
 primary key(recipient_id,message_id)
);
alter table app_private.message_read_receipt enable row level security;
revoke all on app_private.message_read_receipt from public,anon,authenticated,service_role;
create index booking_message_thread_inbound on public.booking_message(booking_id,sender_user_id,created_at,message_id);

create function public.read_booking_messages(p_booking_id uuid,p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); n integer;
begin
 if actor is null or not exists(select 1 from public.booking where booking_id=p_booking_id
  and actor in(owner_id,provider_id)) then
  raise exception 'Booking participant required' using errcode='42501';end if;
 if p_ids is null or cardinality(p_ids) not between 1 and 50 or array_position(p_ids,null) is not null or
  cardinality(p_ids)<>(select count(distinct id) from unnest(p_ids) id) then
  raise exception 'Select up to 50 distinct received messages' using errcode='22023';end if;
 select count(*) into n from public.booking_message where booking_id=p_booking_id
  and message_id=any(p_ids) and sender_user_id<>actor;
 if n<>cardinality(p_ids) then
  raise exception 'Only received messages in this booking can be read' using errcode='42501';end if;
 insert into app_private.message_read_receipt(recipient_id,message_id)
  select actor,message_id from public.booking_message where booking_id=p_booking_id and message_id=any(p_ids)
  on conflict do nothing;
 return jsonb_build_object('recipient_id',actor,'booking_id',p_booking_id,'acknowledged',n);
end;$$;
revoke all on function public.read_booking_messages(uuid,uuid[]) from public,anon,authenticated,service_role;
grant execute on function public.read_booking_messages(uuid,uuid[]) to authenticated;

create function public.my_message_unread()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 if actor is null or not exists(select 1 from public.user_account where user_id=actor) then
  raise exception 'Authentication required' using errcode='42501';end if;
 select jsonb_build_object('recipient_id',actor,'messages',count(*),'threads',count(distinct m.booking_id)) into result
 from public.booking_message m join public.booking b using(booking_id)
 where actor in(b.owner_id,b.provider_id) and m.sender_user_id<>actor
  and not exists(select 1 from app_private.message_read_receipt r where r.recipient_id=actor and r.message_id=m.message_id);
 return result;
end;$$;
revoke all on function public.my_message_unread() from public,anon,authenticated,service_role;
grant execute on function public.my_message_unread() to authenticated;

-- Retain the original five-argument RPC contract. A separate unread endpoint
-- avoids ambiguous defaulted overloads; both use the same private projection.
alter function public.page_my_conversations(integer,timestamptz,uuid,timestamptz,text) set schema app_private;
alter function app_private.page_my_conversations(integer,timestamptz,uuid,timestamptz,text) rename to page_conversations_v23;
revoke all on function app_private.page_conversations_v23(integer,timestamptz,uuid,timestamptz,text)
 from public,anon,authenticated,service_role;
create function app_private.page_conversations_with_reads(p_limit integer,p_before_at timestamptz,p_before_id uuid,
 p_as_of timestamptz,p_search text,p_unread_only boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); boundary timestamptz; term text; result jsonb;
begin
 if actor is null or not exists(select 1 from public.user_account where user_id=actor) then
  raise exception 'Authentication required' using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 50 or p_search is null or length(p_search)>80 or
  ((p_before_at is null)<>(p_before_id is null)) or (p_before_at is not null and p_as_of is null) or
  (p_as_of is not null and (not isfinite(p_as_of) or p_as_of>statement_timestamp())) then
  raise exception 'Invalid conversation page' using errcode='22023';end if;
 boundary:=coalesce(p_as_of,statement_timestamp()); term:=lower(btrim(p_search));
 if p_before_at>boundary then raise exception 'Invalid cursor' using errcode='22023';end if;
 with eligible as (
  select b.booking_id,b.current_status::text as status,
   case when b.owner_id=actor then coalesce(nullif(btrim(pp.full_name),''),'Cleaning Service Provider')
    else 'Property Owner' end as counterpart_name,p.unit_name,p.building_name,s.name as service_name,
   left(coalesce(last.body,''),160) as last_message,coalesce(last.created_at,b.created_at) as last_at,
   (select count(*) from public.booking_message m where m.booking_id=b.booking_id and m.sender_user_id<>actor
     and m.created_at<=boundary and not exists(select 1 from app_private.message_read_receipt r
      where r.recipient_id=actor and r.message_id=m.message_id and r.read_at<=boundary)) as unread_count
  from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
   left join public.provider_profile pp on pp.provider_id=b.provider_id
   left join lateral(select body,created_at from public.booking_message where booking_id=b.booking_id
    and created_at<=boundary order by created_at desc,message_id desc limit 1) last on true
  where actor in(b.owner_id,b.provider_id) and b.created_at<=boundary
   and (b.current_status in('Accepted','In Progress') or last.created_at is not null)
 ), candidates as materialized (
  select * from eligible where (p_before_at is null or (last_at,booking_id)<(p_before_at,p_before_id))
   and (not p_unread_only or unread_count>0)
   and (term='' or position(term in lower(counterpart_name||' '||unit_name||' '||building_name||' '||service_name))>0)
  order by last_at desc,booking_id desc limit p_limit+1
 ), visible as materialized(select * from candidates order by last_at desc,booking_id desc limit p_limit)
 select jsonb_build_object('recipient_id',actor,'as_of',boundary,'search',btrim(p_search),'unread_only',p_unread_only,
  'items',coalesce((select jsonb_agg(to_jsonb(v) order by last_at desc,booking_id desc) from visible v),'[]'::jsonb),
  'has_more',(select count(*) from candidates)>p_limit,
  'next_cursor',case when (select count(*) from candidates)>p_limit then
    (select jsonb_build_object('timestamp',last_at,'id',booking_id) from visible order by last_at,booking_id limit 1) else null end,
  'unread_total',(select coalesce(sum(unread_count),0) from eligible)) into result;
 return result;
end;$$;
revoke all on function app_private.page_conversations_with_reads(integer,timestamptz,uuid,timestamptz,text,boolean)
 from public,anon,authenticated,service_role;
create function public.page_my_conversations(p_limit integer default 20,p_before_at timestamptz default null,
 p_before_id uuid default null,p_as_of timestamptz default null,p_search text default '')
returns jsonb language sql stable security definer set search_path='' as $$
 select app_private.page_conversations_with_reads(p_limit,p_before_at,p_before_id,p_as_of,p_search,false);
$$;
create function public.page_my_unread_conversations(p_limit integer default 20,p_before_at timestamptz default null,
 p_before_id uuid default null,p_as_of timestamptz default null,p_search text default '')
returns jsonb language sql stable security definer set search_path='' as $$
 select app_private.page_conversations_with_reads(p_limit,p_before_at,p_before_id,p_as_of,p_search,true);
$$;
revoke all on function public.page_my_conversations(integer,timestamptz,uuid,timestamptz,text),
 public.page_my_unread_conversations(integer,timestamptz,uuid,timestamptz,text) from public,anon,authenticated,service_role;
grant execute on function public.page_my_conversations(integer,timestamptz,uuid,timestamptz,text),
 public.page_my_unread_conversations(integer,timestamptz,uuid,timestamptz,text) to authenticated;


-- MIGRATION 20261123000041_owner_owner_uat_identity_portfolio.sql
-- Additive UAT changes: seed user-selected names on first profile creation,
-- and aggregate the complete Owner portfolio independently of page size.
create function app_private.seed_registration_full_name() returns trigger
language plpgsql security definer set search_path='' as $$
declare requested text; actor uuid;
begin
 if tg_table_name='user_account' then actor:=new.user_id;
 else actor:=new.provider_id; end if;
 select u.raw_user_meta_data->>'requested_full_name' into requested
 from auth.users u where u.id=actor;
 if requested is not null then
  requested:=btrim(requested);
  if length(requested) not between 2 and 60 then
   raise exception 'Enter a name of 2-60 characters' using errcode='22023';
  end if;
  if nullif(new.full_name,'') is null then new.full_name:=requested; end if;
 end if;
 return new;
end;$$;
revoke all on function app_private.seed_registration_full_name() from public,anon,authenticated,service_role;
create trigger seed_account_full_name before insert on public.user_account
 for each row execute function app_private.seed_registration_full_name();
create trigger seed_provider_full_name before insert on public.provider_profile
 for each row execute function app_private.seed_registration_full_name();

create function public.my_owner_portfolio_summary() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 if actor is null or not exists(select 1 from public.user_account a where a.user_id=actor and a.role='owner') then
  raise exception 'Owner authentication required' using errcode='42501';
 end if;
 select jsonb_build_object('actor_id',actor,
  'property_count',(select count(*) from public.property where owner_id=actor),
  'building_count',(select count(distinct building_name) from public.property where owner_id=actor),
  'size_sqft',(select coalesce(sum(size_sqft),0) from public.property where owner_id=actor),
  'open',(select count(*) from public.booking where owner_id=actor and current_status in ('Pending','Accepted','In Progress')),
  'done',(select count(*) from public.booking where owner_id=actor and current_status='Completed'),
  'total',(select count(*) from public.booking where owner_id=actor)) into result;
 return result;
end;$$;
revoke all on function public.my_owner_portfolio_summary() from public,anon,authenticated,service_role;
grant execute on function public.my_owner_portfolio_summary() to authenticated;


-- MIGRATION 20261123000042_owner_owner_navigation_pages.sql
-- Owner navigation reads. Filter before paging; expose only approved directory
-- profile fields. No new table grants or changes to booking write operations.
create function public.page_owner_booking_search(
 p_query text default '', p_group text default 'all', p_limit integer default 20,
 p_before_at timestamptz default null, p_before_id uuid default null,
 p_oldest boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); rows jsonb; term text:=lower(btrim(coalesce(p_query,'')));
begin
 if actor is null or not exists(select 1 from public.user_account where user_id=actor and role='owner') then
  raise exception 'Owner authentication required' using errcode='42501'; end if;
 if length(term)>80 or p_group is null or p_group not in ('all','pending','ongoing','history','completed','cancelled','declined')
  or p_limit is null or p_limit not between 1 and 50 or p_oldest is null
  or (p_before_at is null)<>(p_before_id is null) then
  raise exception 'Invalid search request' using errcode='22023'; end if;
 select coalesce(jsonb_agg(card order by
  case when p_oldest then created_at end asc,case when not p_oldest then created_at end desc,
  case when p_oldest then booking_id end asc,case when not p_oldest then booking_id end desc),'[]'::jsonb)
 into rows from (
  select b.created_at,b.booking_id,to_jsonb(b)||jsonb_build_object('unit_name',p.unit_name,
   'building_name',p.building_name,'property_address',p.address,'service_name',s.name) card
  from public.booking b join public.property p using(property_id) join public.service_type s using(service_type_id)
  where b.owner_id=actor and (p_group='all'
   or (p_group='pending' and b.current_status='Pending')
   or (p_group='ongoing' and b.current_status in ('Accepted','In Progress'))
   or (p_group='history' and b.current_status in ('Completed','Cancelled','Declined'))
   or (p_group='completed' and b.current_status='Completed')
   or (p_group='cancelled' and b.current_status='Cancelled')
   or (p_group='declined' and b.current_status='Declined'))
  and (term='' or strpos(lower(p.unit_name||' '||p.building_name||' '||s.name),term)>0)
  and (p_before_at is null or (not p_oldest and (b.created_at,b.booking_id)<(p_before_at,p_before_id))
    or (p_oldest and (b.created_at,b.booking_id)>(p_before_at,p_before_id)))
  order by case when p_oldest then b.created_at end asc,case when not p_oldest then b.created_at end desc,
   case when p_oldest then b.booking_id end asc,case when not p_oldest then b.booking_id end desc
  limit p_limit+1
 ) bounded;
 return public.pack_cursor_page(rows,p_limit,'created_at','booking_id')||jsonb_build_object('actor_id',actor);
end;$$;

create function public.page_approved_provider_directory(
 p_query text default '', p_limit integer default 20,
 p_before_at timestamptz default null, p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); rows jsonb; term text:=lower(btrim(coalesce(p_query,'')));
begin
 if actor is null or not exists(select 1 from public.user_account where user_id=actor and role='owner') then
  raise exception 'Owner authentication required' using errcode='42501'; end if;
 if length(term)>80 or p_limit is null or p_limit not between 1 and 50
  or (p_before_at is null)<>(p_before_id is null) then
  raise exception 'Invalid directory request' using errcode='22023'; end if;
 select coalesce(jsonb_agg(card order by listed_at desc,provider_id desc),'[]'::jsonb) into rows from (
  select a.created_at listed_at,p.provider_id,jsonb_build_object(
   'provider_id',p.provider_id,'listed_at',a.created_at,'full_name',p.full_name,
   'bio',p.bio,'service_area',p.service_area,'hourly_rate',p.hourly_rate,'daily_rate',p.daily_rate,
   'rating_average',p.rating_average,'completed_job_count',p.completed_job_count,
   'services',coalesce((select jsonb_agg(jsonb_build_object('name',s.name,'description',s.description) order by s.name)
    from public.provider_capability c join public.service_type s using(service_type_id)
    where c.provider_id=p.provider_id),'[]'::jsonb)) card
  from public.provider_profile p join public.user_account a on a.user_id=p.provider_id
  where p.approval_status='approved' and (term=''
   or strpos(lower(coalesce(p.full_name,'')||' '||p.service_area),term)>0
   or exists(select 1 from public.provider_capability c join public.service_type s using(service_type_id)
    where c.provider_id=p.provider_id and strpos(lower(s.name),term)>0))
  and (p_before_at is null or (a.created_at,p.provider_id)<(p_before_at,p_before_id))
  order by a.created_at desc,p.provider_id desc limit p_limit+1
 ) bounded;
 return public.pack_cursor_page(rows,p_limit,'listed_at','provider_id')||jsonb_build_object('actor_id',actor);
end;$$;
revoke all on function public.page_owner_booking_search(text,text,integer,timestamptz,uuid,boolean),
 public.page_approved_provider_directory(text,integer,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.page_owner_booking_search(text,text,integer,timestamptz,uuid,boolean),
 public.page_approved_provider_directory(text,integer,timestamptz,uuid) to authenticated;


-- MIGRATION 20261123000043_owner_evidence_photo_removal.sql
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


-- MIGRATION 20261123000044_integrated_identity_and_units.sql
-- Shared identity, lifecycle, and canonical apartment linkage.
create function app_private.initialize_integrated_profile() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.role in ('owner','provider') then
    new.account_status := 'active';
    new.full_name := coalesce(nullif(new.full_name,''), (select raw_user_meta_data->>'requested_full_name' from auth.users where id=new.user_id),'');
  end if;
  return new;
end;$$;
create trigger a_initialize_integrated_profile before insert on public.user_account
for each row execute function app_private.initialize_integrated_profile();
-- Never allow a self-registering caller to create an administrator or tenant role.
drop policy if exists account_self_insert on public.user_account;
create policy account_self_insert on public.user_account for insert to authenticated
with check (user_id=auth.uid() and role in ('owner','provider')
  and account_status='active' and lower(email)=lower(auth.jwt()->>'email'));

alter table public.rental_unit add column property_id uuid unique references public.property(property_id) on delete restrict;
create function app_private.link_property_unit() returns trigger
language plpgsql security definer set search_path='' as $$
declare code text; existing_property uuid;
begin
  code := upper(regexp_replace(btrim(new.unit_name),'[ -]','','g'));
  if code !~ '^[AB](0[1-9]|1[0-9]|2[0-5])0[1-8]$' then
    raise exception 'Use an apartment unit from A-01-01 to B-25-08 (25 floors, 8 units per floor).' using errcode='22023';
  end if;
  code := substring(code,1,1)||'-'||substring(code,2,2)||'-'||substring(code,4,2);
  if tg_op='UPDATE' and new.unit_name is distinct from old.unit_name then
    raise exception 'A registered apartment unit number cannot be changed. Contact the administrator.' using errcode='22023';
  end if;
  new.unit_name := code;
  return new;
end;$$;
create trigger validate_integrated_property_unit before insert or update on public.property
for each row execute function app_private.link_property_unit();
create function app_private.bind_property_unit() returns trigger
language plpgsql security definer set search_path='' as $$
declare existing_property uuid;
begin
  insert into public.rental_unit(unit_number,block_and_floor,property_id)
  values(new.unit_name,'Block '||left(new.unit_name,1)||' · Floor '||substring(new.unit_name,3,2),new.property_id)
  on conflict(unit_number) do update set property_id=excluded.property_id
    where rental_unit.property_id is null or rental_unit.property_id=excluded.property_id;
  if not found then raise exception 'This apartment unit is already registered to a property.' using errcode='23505'; end if;
  return new;
end;$$;
create trigger bind_integrated_property_unit after insert on public.property
for each row execute function app_private.bind_property_unit();
-- Unit is the physical apartment. Tenancy remains the dated tenant-unit association.
create index rental_unit_property_idx on public.rental_unit(property_id);

-- Invitation service needs these operations; RLS continues protecting client access.
grant all on public.user_account,public.admin,public.tenant,public.tenant_registration,public.audit_log to service_role;
grant select,insert,update on public.user_account to authenticated;
-- Prevent the broad legacy profile grant from exposing administrative fields.
revoke insert,update on public.user_account from authenticated;
grant insert(user_id,email,contact_number,role) on public.user_account to authenticated;
grant update(full_name,contact_number) on public.user_account to authenticated;
update public.app_deployment_environment set environment='staging',project_ref='myetpfavvwuevdcybdes',configured_at=now() where singleton;
notify pgrst, 'reload schema';


-- MIGRATION 20261123000045_record_integrated_migration_history.sql
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations(version text primary key, statements text[], name text);
insert into supabase_migrations.schema_migrations(version,name) values
('20261123000001','tenant_initial_schema'),
('20261123000002','tenant_tenant_account_lifecycle'),
('20261123000003','tenant_tenant_onboarding_audit'),
('20261123000004','tenant_tenant_verification_documents'),
('20261123000005','tenant_live_chat_and_testing_access'),
('20261123000006','tenant_database_announcements'),
('20261123000007','tenant_edit_draft_announcements'),
('20261123000008','tenant_hide_pre_activation_announcements'),
('20261123000009','tenant_simulated_electricity_device_registration'),
('20261123000010','tenant_meter_ingestion_evidence'),
('20261123000011','tenant_electricity_reading_realtime'),
('20261123000012','tenant_maintenance_workflow_storage_and_status_rpc'),
('20261123000013','tenant_simplify_maintenance_statuses'),
('20261123000014','owner_core_booking'),
('20261123000015','owner_lifecycle_evidence_realtime'),
('20261123000016','owner_cancel_before_start'),
('20261123000017','owner_provider_setup'),
('20261123000018','owner_provider_data_visibility'),
('20261123000019','owner_secure_booking_creation'),
('20261123000020','owner_property_window_lock_visibility'),
('20261123000021','owner_eligible_provider_search'),
('20261123000022','owner_booking_quote_snapshot'),
('20261123000023','owner_booking_messages'),
('20261123000024','owner_booking_reviews'),
('20261123000025','owner_booking_contexts'),
('20261123000026','owner_deployment_environment'),
('20261123000027','owner_evidence_upload_lifecycle'),
('20261123000028','owner_cursor_pagination'),
('20261123000029','owner_test_data_management'),
('20261123000030','owner_booking_communication_limits'),
('20261123000031','owner_verified_evidence'),
('20261123000032','owner_explicit_app_privileges'),
('20261123000033','owner_provider_earnings'),
('20261123000034','owner_provider_profile_editor'),
('20261123000035','owner_booking_notifications'),
('20261123000036','owner_conversation_inbox'),
('20261123000037','owner_owner_workspace'),
('20261123000038','owner_workspace_reports'),
('20261123000039','owner_test_fixture_cleanup'),
('20261123000040','owner_message_read_receipts'),
('20261123000041','owner_owner_uat_identity_portfolio'),
('20261123000042','owner_owner_navigation_pages'),
('20261123000043','owner_evidence_photo_removal'),
('20261123000044','integrated_identity_and_units'),
('20261123000045','record_integrated_migration_history')
on conflict(version) do nothing;

alter table supabase_migrations.schema_migrations enable row level security;
revoke all on schema supabase_migrations from public,anon,authenticated;
revoke all on supabase_migrations.schema_migrations from public,anon,authenticated;

commit;