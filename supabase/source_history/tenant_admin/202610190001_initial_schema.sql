-- Smart Rental Management - initial Supabase schema
-- The Supabase auth.users table is the identity source. This migration does
-- not duplicate it; public.user_account stores application profile data.

create extension if not exists pgcrypto;

create table if not exists public.user_account (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name varchar(100) not null,
  email varchar(254) not null,
  contact_number varchar(30),
  role varchar(20) not null check (role in ('tenant', 'admin')),
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
