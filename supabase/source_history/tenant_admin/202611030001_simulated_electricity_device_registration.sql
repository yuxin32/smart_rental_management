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
