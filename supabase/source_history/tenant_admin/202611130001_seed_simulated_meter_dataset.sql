-- Demonstration dataset for the Admin Module meter list and details screens.
-- The records represent DDSU666 measurements received through a simulated
-- ESP32 ingestion path. The unit records use the shared apartment inventory;
-- meter identifiers and data_source mark these as simulated readings.

do $$
declare
  v_admin_id uuid;
begin
  select admin_id
  into v_admin_id
  from public.admin
  where is_active = true
  order by created_at
  limit 1;

  if v_admin_id is null then
    raise exception 'An active administrator is required before seeding meter data.';
  end if;

  insert into public.rental_unit (
    unit_id,
    unit_number,
    block_and_floor,
    occupancy_capacity,
    unit_status
  ) values
    ('a1000000-0000-4000-8000-000000000001', 'A-01-01', 'Block A · Floor 01', 2, 'available'),
    ('a1000000-0000-4000-8000-000000000002', 'B-05-04', 'Block B · Floor 05', 3, 'available'),
    ('a1000000-0000-4000-8000-000000000003', 'B-08-08', 'Block B · Floor 08', 2, 'available')
  on conflict (unit_number) do update set
    block_and_floor = excluded.block_and_floor,
    occupancy_capacity = excluded.occupancy_capacity;

  insert into public.electricity_device (
    device_id,
    unit_id,
    registered_by_admin_id,
    device_identifier,
    meter_serial_number,
    meter_model,
    communication_type,
    modbus_slave_id,
    reading_type,
    sampling_interval_sec,
    calibration_factor,
    measurement_tolerance,
    initial_cumulative_kwh,
    installation_date,
    data_source,
    device_status,
    last_seen_at,
    registered_at
  ) values
    (
      'd6600000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      v_admin_id,
      'DDSU666-SIM-A0101',
      'SIM-DDSU666-0001',
      'CHINT DDSU666 5(80)A 2P',
      'RS485 Modbus-RTU',
      1,
      'cumulative_kwh',
      300,
      1.000000,
      0.050000,
      1250.000000,
      current_date - 30,
      'simulated',
      'active',
      now() - interval '1 minute',
      now() - interval '30 days'
    ),
    (
      'd6600000-0000-4000-8000-000000000002',
      'a1000000-0000-4000-8000-000000000002',
      v_admin_id,
      'DDSU666-SIM-B0503',
      'SIM-DDSU666-0002',
      'CHINT DDSU666 5(80)A 2P',
      'RS485 Modbus-RTU',
      2,
      'cumulative_kwh',
      300,
      1.000000,
      0.050000,
      860.000000,
      current_date - 20,
      'simulated',
      'active',
      now() - interval '2 minutes',
      now() - interval '20 days'
    ),
    (
      'd6600000-0000-4000-8000-000000000003',
      'a1000000-0000-4000-8000-000000000003',
      v_admin_id,
      'DDSU666-SIM-C0811',
      'SIM-DDSU666-0003',
      'CHINT DDSU666 5(80)A 2P',
      'RS485 Modbus-RTU',
      3,
      'cumulative_kwh',
      300,
      1.000000,
      0.050000,
      430.000000,
      current_date - 14,
      'simulated',
      'offline',
      now() - interval '8 hours',
      now() - interval '14 days'
    )
  on conflict (device_identifier) do update set
    unit_id = excluded.unit_id,
    registered_by_admin_id = excluded.registered_by_admin_id,
    meter_serial_number = excluded.meter_serial_number,
    meter_model = excluded.meter_model,
    communication_type = excluded.communication_type,
    modbus_slave_id = excluded.modbus_slave_id,
    sampling_interval_sec = excluded.sampling_interval_sec,
    calibration_factor = excluded.calibration_factor,
    measurement_tolerance = excluded.measurement_tolerance,
    initial_cumulative_kwh = excluded.initial_cumulative_kwh,
    installation_date = excluded.installation_date,
    data_source = excluded.data_source,
    device_status = excluded.device_status,
    last_seen_at = excluded.last_seen_at;

  -- Meter A: a normal, monotonic series of accepted five-minute readings.
  insert into public.electricity_reading (
    device_id,
    measurement_timestamp,
    received_at,
    cumulative_energy_kwh,
    interval_energy_kwh,
    voltage_v,
    current_a,
    power_w,
    power_factor,
    frequency_hz,
    sequence_number,
    validation_status,
    validation_reason
  )
  select
    'd6600000-0000-4000-8000-000000000001'::uuid,
    now() - ((24 - sample_no) * interval '5 minutes'),
    now() - ((24 - sample_no) * interval '5 minutes') + interval '2 seconds',
    round((1250.000000 + sample_no * 0.041000)::numeric, 6),
    0.041000,
    round((237.400 + (sample_no % 5) * 0.350)::numeric, 3),
    round((1.620 + (sample_no % 4) * 0.080)::numeric, 3),
    round((365.000 + (sample_no % 6) * 14.000)::numeric, 3),
    round((0.940 + (sample_no % 3) * 0.010)::numeric, 3),
    round((49.950 + (sample_no % 3) * 0.025)::numeric, 3),
    sample_no,
    'accepted',
    'Passed device, timestamp, sequence, range, and monotonicity checks.'
  from generate_series(1, 24) as series(sample_no)
  on conflict (device_id, measurement_timestamp) do nothing;

  -- Meter B: one high interval is flagged while the remaining records pass.
  insert into public.electricity_reading (
    device_id,
    measurement_timestamp,
    received_at,
    cumulative_energy_kwh,
    interval_energy_kwh,
    voltage_v,
    current_a,
    power_w,
    power_factor,
    frequency_hz,
    sequence_number,
    validation_status,
    validation_reason
  )
  select
    'd6600000-0000-4000-8000-000000000002'::uuid,
    now() - ((20 - sample_no) * interval '5 minutes'),
    now() - ((20 - sample_no) * interval '5 minutes') + interval '3 seconds',
    round((
      case
        when sample_no < 13 then 860.000000 + sample_no * 0.055000
        else 860.000000 + 12 * 0.055000 + 4.750000 + (sample_no - 13) * 0.060000
      end
    )::numeric, 6),
    case when sample_no = 13 then 4.750000 else 0.055000 end,
    round((238.100 + (sample_no % 4) * 0.300)::numeric, 3),
    case when sample_no = 13 then 24.800 else round((2.050 + (sample_no % 3) * 0.110)::numeric, 3) end,
    case when sample_no = 13 then 5520.000 else round((455.000 + (sample_no % 5) * 16.000)::numeric, 3) end,
    case when sample_no = 13 then 0.930 else round((0.950 + (sample_no % 2) * 0.010)::numeric, 3) end,
    round((49.960 + (sample_no % 3) * 0.020)::numeric, 3),
    sample_no,
    case when sample_no = 13 then 'flagged' else 'accepted' end,
    case
      when sample_no = 13 then 'Interval energy exceeded the configured tolerance and requires administrator review.'
      else 'Passed device, timestamp, sequence, range, and monotonicity checks.'
    end
  from generate_series(1, 20) as series(sample_no)
  on conflict (device_id, measurement_timestamp) do nothing;

  -- Meter C: valid historical records followed by an offline device state.
  insert into public.electricity_reading (
    device_id,
    measurement_timestamp,
    received_at,
    cumulative_energy_kwh,
    interval_energy_kwh,
    voltage_v,
    current_a,
    power_w,
    power_factor,
    frequency_hz,
    sequence_number,
    validation_status,
    validation_reason
  )
  select
    'd6600000-0000-4000-8000-000000000003'::uuid,
    now() - interval '8 hours' - ((12 - sample_no) * interval '5 minutes'),
    now() - interval '8 hours' - ((12 - sample_no) * interval '5 minutes') + interval '2 seconds',
    round((430.000000 + sample_no * 0.032000)::numeric, 6),
    0.032000,
    round((236.800 + (sample_no % 4) * 0.250)::numeric, 3),
    round((1.250 + (sample_no % 3) * 0.070)::numeric, 3),
    round((280.000 + (sample_no % 5) * 11.000)::numeric, 3),
    round((0.930 + (sample_no % 3) * 0.010)::numeric, 3),
    round((49.940 + (sample_no % 4) * 0.020)::numeric, 3),
    sample_no,
    'accepted',
    'Passed validation before the simulated device stopped reporting.'
  from generate_series(1, 12) as series(sample_no)
  on conflict (device_id, measurement_timestamp) do nothing;
end;
$$;
