import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const finiteNumber = (value: unknown): number | null =>
  typeof value === "number" && Number.isFinite(value) ? value : null;

const nonEmptyString = (value: unknown): string | null =>
  typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;

const rejection = (reason: string, extra: Record<string, unknown> = {}) =>
  json({
    stored: false,
    validation_status: "rejected",
    validation_reason: reason,
    ...extra,
  });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Only POST requests are supported." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "The meter-ingestion service is not configured." }, 500);
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // FYP simulation mode: only an authenticated active administrator may replay
  // a dataset. A future physical ESP32 can use a per-device credential while
  // retaining the validation and storage logic below.
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Authentication is required." }, 401);
  }

  const accessToken = authorization.replace("Bearer ", "");
  const { data: authData, error: authError } =
    await serviceClient.auth.getUser(accessToken);
  if (authError || !authData.user) {
    return json({ error: "The administrator session is invalid." }, 401);
  }

  const { data: administrator, error: administratorError } = await serviceClient
    .from("admin")
    .select("admin_id")
    .eq("admin_id", authData.user.id)
    .eq("is_active", true)
    .maybeSingle();

  if (administratorError || !administrator) {
    return json(
      { error: "Only an active administrator can run meter dataset tests." },
      403,
    );
  }

  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return rejection("The reading payload must be a valid JSON object.");
  }

  const payload = body as Record<string, unknown>;
  const deviceIdentifier = nonEmptyString(payload.device_identifier);
  if (!deviceIdentifier) {
    return rejection("device_identifier is required.");
  }

  const { data: device, error: deviceError } = await serviceClient
    .from("electricity_device")
    .select(
      "device_id, unit_id, device_identifier, modbus_slave_id, " +
        "sampling_interval_sec, calibration_factor, measurement_tolerance, " +
        "initial_cumulative_kwh, data_source, device_status",
    )
    .eq("device_identifier", deviceIdentifier)
    .maybeSingle();

  if (deviceError) {
    return json({ error: deviceError.message }, 400);
  }

  if (!device) {
    return rejection("The device identifier is not registered.", {
      device_identifier: deviceIdentifier,
    });
  }

  if (device.device_status === "retired") {
    return rejection("The registered meter has been retired.", {
      device_id: device.device_id,
    });
  }

  const modbusSlaveId = finiteNumber(payload.modbus_slave_id);
  const sequenceNumber = finiteNumber(payload.sequence_number);
  const cumulativeRaw = finiteNumber(payload.cumulative_energy_kwh);
  const voltage = finiteNumber(payload.voltage_v);
  const current = finiteNumber(payload.current_a);
  const power = finiteNumber(payload.power_w);
  const powerFactor = finiteNumber(payload.power_factor);
  const frequency = finiteNumber(payload.frequency_hz);
  const timestampText = nonEmptyString(payload.measurement_timestamp);
  const measurementTimestamp = timestampText ? new Date(timestampText) : null;

  if (
    modbusSlaveId === null ||
    sequenceNumber === null ||
    cumulativeRaw === null ||
    voltage === null ||
    current === null ||
    power === null ||
    powerFactor === null ||
    frequency === null ||
    !measurementTimestamp ||
    Number.isNaN(measurementTimestamp.getTime())
  ) {
    return rejection(
      "The reading is incomplete or contains a non-numeric measurement.",
      { device_id: device.device_id },
    );
  }

  if (!Number.isInteger(sequenceNumber) || sequenceNumber <= 0) {
    return rejection("The sequence number must be a positive integer.", {
      device_id: device.device_id,
    });
  }

  if (cumulativeRaw < 0) {
    return rejection("Cumulative energy cannot be negative.", {
      device_id: device.device_id,
    });
  }

  const timestampIso = measurementTimestamp.toISOString();
  const { data: duplicateRows, error: duplicateError } = await serviceClient
    .from("electricity_reading")
    .select("reading_id, measurement_timestamp, sequence_number")
    .eq("device_id", device.device_id)
    .or(
      `measurement_timestamp.eq.${timestampIso},sequence_number.eq.${sequenceNumber}`,
    )
    .limit(1);

  if (duplicateError) {
    return json({ error: duplicateError.message }, 400);
  }

  if ((duplicateRows ?? []).length > 0) {
    return json({
      stored: false,
      reading_id: duplicateRows![0].reading_id,
      validation_status: "duplicate",
      validation_reason:
        "The timestamp or sequence number has already been received.",
      device_status: device.device_status,
    });
  }

  const [{ data: latestRows }, { data: latestAcceptedRows }] =
    await Promise.all([
      serviceClient
        .from("electricity_reading")
        .select("sequence_number")
        .eq("device_id", device.device_id)
        .not("sequence_number", "is", null)
        .order("sequence_number", { ascending: false })
        .limit(1),
      serviceClient
        .from("electricity_reading")
        .select("cumulative_energy_kwh, measurement_timestamp")
        .eq("device_id", device.device_id)
        .eq("validation_status", "accepted")
        .order("measurement_timestamp", { ascending: false })
        .limit(1),
    ]);

  const latestSequence = latestRows?.[0]?.sequence_number as number | undefined;
  const previousAccepted = latestAcceptedRows?.[0];
  const calibrationFactor = Number(device.calibration_factor ?? 1);
  const cumulativeEnergy = cumulativeRaw * calibrationFactor;
  const baseline = previousAccepted
    ? Number(previousAccepted.cumulative_energy_kwh)
    : Number(device.initial_cumulative_kwh ?? 0);
  const intervalEnergy = cumulativeEnergy - baseline;

  const rejectedReasons: string[] = [];
  const flaggedReasons: string[] = [];
  const now = Date.now();
  const timestampDifference = measurementTimestamp.getTime() - now;

  if (modbusSlaveId !== Number(device.modbus_slave_id)) {
    rejectedReasons.push(
      `Modbus address ${modbusSlaveId} does not match registered address ${device.modbus_slave_id}.`,
    );
  }
  if (timestampDifference > 5 * 60 * 1000) {
    rejectedReasons.push("The measurement timestamp is too far in the future.");
  } else if (timestampDifference < -24 * 60 * 60 * 1000) {
    flaggedReasons.push("The measurement timestamp is more than 24 hours old.");
  }
  if (latestSequence !== undefined) {
    if (sequenceNumber <= latestSequence) {
      rejectedReasons.push("The sequence number is out of order.");
    } else if (sequenceNumber > latestSequence + 1) {
      flaggedReasons.push(
        `A sequence gap was detected after sequence ${latestSequence}.`,
      );
    }
  }
  if (voltage < 180 || voltage > 270) {
    rejectedReasons.push("Voltage is outside the permitted 180–270 V range.");
  }
  if (current < 0 || current > 80) {
    rejectedReasons.push("Current is outside the permitted 0–80 A range.");
  }
  if (power < 0 || power > 20000) {
    rejectedReasons.push("Active power is outside the permitted range.");
  }
  if (powerFactor < 0 || powerFactor > 1) {
    rejectedReasons.push("Power factor must be between 0 and 1.");
  }
  if (frequency < 45 || frequency > 55) {
    rejectedReasons.push("Frequency is outside the permitted 45–55 Hz range.");
  }
  if (intervalEnergy < 0) {
    rejectedReasons.push(
      "Cumulative energy is lower than the previous accepted baseline.",
    );
  }

  const samplingHours = Number(device.sampling_interval_sec) / 3600;
  const tolerance = Number(device.measurement_tolerance ?? 0.05);
  const maximumIntervalEnergy = 20 * samplingHours * (1 + tolerance);
  if (intervalEnergy > maximumIntervalEnergy) {
    flaggedReasons.push(
      `Interval energy ${intervalEnergy.toFixed(3)} kWh exceeds the configured test threshold ${maximumIntervalEnergy.toFixed(3)} kWh.`,
    );
  }

  if (
    voltage > 0 &&
    current >= 0 &&
    powerFactor >= 0 &&
    powerFactor <= 1
  ) {
    const calculatedPower = voltage * current * powerFactor;
    const denominator = Math.max(calculatedPower, 1);
    const powerDifference = Math.abs(power - calculatedPower) / denominator;
    if (powerDifference > Math.max(0.15, tolerance)) {
      flaggedReasons.push(
        "Reported active power is inconsistent with voltage, current, and power factor.",
      );
    }
  }

  const validationStatus = rejectedReasons.length > 0
    ? "rejected"
    : flaggedReasons.length > 0
    ? "flagged"
    : "accepted";
  const reasons = [...rejectedReasons, ...flaggedReasons];
  const validationReason = reasons.length > 0
    ? reasons.join(" ")
    : "Passed device, timestamp, sequence, range, consistency, and cumulative-energy checks.";

  const safePowerFactor = powerFactor >= 0 && powerFactor <= 1
    ? powerFactor
    : null;
  const safeIntervalEnergy = intervalEnergy >= 0 ? intervalEnergy : null;
  const testRunId = nonEmptyString(payload.test_run_id);

  const { data: storedReading, error: insertError } = await serviceClient
    .from("electricity_reading")
    .insert({
      device_id: device.device_id,
      measurement_timestamp: timestampIso,
      cumulative_energy_kwh: cumulativeEnergy,
      interval_energy_kwh: safeIntervalEnergy,
      voltage_v: voltage,
      current_a: current,
      power_w: power,
      power_factor: safePowerFactor,
      frequency_hz: frequency,
      sequence_number: sequenceNumber,
      validation_status: validationStatus,
      validation_reason: validationReason,
      ingestion_source: "admin_dataset_test",
      ingestion_run_id: testRunId,
      raw_payload: payload,
    })
    .select("reading_id")
    .single();

  if (insertError || !storedReading) {
    if (insertError?.code === "23505") {
      return json({
        stored: false,
        validation_status: "duplicate",
        validation_reason:
          "The timestamp or sequence number has already been received.",
        device_status: device.device_status,
      });
    }
    return json({ error: insertError?.message ?? "Unable to store reading." }, 400);
  }

  const nextDeviceStatus = validationStatus === "accepted"
    ? "active"
    : device.device_status;
  const { error: updateError } = await serviceClient
    .from("electricity_device")
    .update({
      last_seen_at: new Date().toISOString(),
      device_status: nextDeviceStatus,
    })
    .eq("device_id", device.device_id);

  if (updateError) {
    console.error("Reading stored but meter status update failed", updateError);
  }

  return json({
    stored: true,
    reading_id: storedReading.reading_id,
    validation_status: validationStatus,
    validation_reason: validationReason,
    device_status: nextDeviceStatus,
    interval_energy_kwh: safeIntervalEnergy,
  });
});
