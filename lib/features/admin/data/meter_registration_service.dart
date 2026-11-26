import 'package:supabase_flutter/supabase_flutter.dart';

class MeterUnitOption {
  const MeterUnitOption({
    required this.unitId,
    required this.unitNumber,
    required this.location,
    required this.status,
  });

  final String unitId;
  final String unitNumber;
  final String? location;
  final String status;

  String get label {
    if (location == null || location!.trim().isEmpty) return unitNumber;
    return '${location!.trim()} · $unitNumber';
  }

  factory MeterUnitOption.fromMap(Map<String, dynamic> map) {
    return MeterUnitOption(
      unitId: map['unit_id'] as String,
      unitNumber: map['unit_number'] as String? ?? '',
      location: map['block_and_floor'] as String?,
      status: map['unit_status'] as String? ?? 'available',
    );
  }
}

class RegisteredMeterRecord {
  const RegisteredMeterRecord({
    required this.deviceId,
    required this.deviceIdentifier,
    required this.serialNumber,
    required this.model,
    required this.modbusSlaveId,
    required this.samplingIntervalSec,
    required this.calibrationFactor,
    required this.measurementTolerance,
    required this.initialCumulativeKwh,
    required this.installationDate,
    required this.dataSource,
    required this.status,
    required this.lastSeenAt,
    required this.registeredAt,
    required this.unitNumber,
    required this.unitLocation,
    this.latestReading,
  });

  final String deviceId;
  final String deviceIdentifier;
  final String serialNumber;
  final String model;
  final int modbusSlaveId;
  final int samplingIntervalSec;
  final double calibrationFactor;
  final double measurementTolerance;
  final double initialCumulativeKwh;
  final DateTime installationDate;
  final String dataSource;
  final String status;
  final DateTime? lastSeenAt;
  final DateTime registeredAt;
  final String unitNumber;
  final String? unitLocation;
  final MeterReadingRecord? latestReading;

  String get unitLabel {
    if (unitLocation == null || unitLocation!.trim().isEmpty) {
      return unitNumber;
    }
    return '${unitLocation!.trim()} · $unitNumber';
  }

  factory RegisteredMeterRecord.fromMap(
    Map<String, dynamic> map, {
    MeterReadingRecord? latestReading,
  }) {
    final unit = map['rental_unit'] is Map
        ? Map<String, dynamic>.from(map['rental_unit'] as Map)
        : <String, dynamic>{};

    return RegisteredMeterRecord(
      deviceId: map['device_id'] as String,
      deviceIdentifier: map['device_identifier'] as String? ?? '',
      serialNumber: map['meter_serial_number'] as String? ?? '',
      model: map['meter_model'] as String? ?? 'CHINT DDSU666 5(80)A 2P',
      modbusSlaveId: (map['modbus_slave_id'] as num?)?.toInt() ?? 1,
      samplingIntervalSec:
          (map['sampling_interval_sec'] as num?)?.toInt() ?? 300,
      calibrationFactor: (map['calibration_factor'] as num?)?.toDouble() ?? 1,
      measurementTolerance:
          (map['measurement_tolerance'] as num?)?.toDouble() ?? 0.02,
      initialCumulativeKwh:
          (map['initial_cumulative_kwh'] as num?)?.toDouble() ?? 0,
      installationDate:
          DateTime.tryParse(map['installation_date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dataSource: map['data_source'] as String? ?? 'simulated',
      status: map['device_status'] as String? ?? 'pending',
      lastSeenAt: DateTime.tryParse(map['last_seen_at']?.toString() ?? ''),
      registeredAt:
          DateTime.tryParse(map['registered_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      unitNumber: unit['unit_number'] as String? ?? 'Unknown unit',
      unitLocation: unit['block_and_floor'] as String?,
      latestReading: latestReading,
    );
  }
}

class MeterReadingRecord {
  const MeterReadingRecord({
    required this.readingId,
    required this.deviceId,
    required this.measurementTimestamp,
    required this.receivedAt,
    required this.cumulativeEnergyKwh,
    required this.intervalEnergyKwh,
    required this.voltageV,
    required this.currentA,
    required this.powerW,
    required this.powerFactor,
    required this.frequencyHz,
    required this.sequenceNumber,
    required this.validationStatus,
    required this.validationReason,
  });

  final String readingId;
  final String deviceId;
  final DateTime measurementTimestamp;
  final DateTime receivedAt;
  final double cumulativeEnergyKwh;
  final double? intervalEnergyKwh;
  final double? voltageV;
  final double? currentA;
  final double? powerW;
  final double? powerFactor;
  final double? frequencyHz;
  final int? sequenceNumber;
  final String validationStatus;
  final String? validationReason;

  factory MeterReadingRecord.fromMap(Map<String, dynamic> map) {
    return MeterReadingRecord(
      readingId: map['reading_id'] as String,
      deviceId: map['device_id'] as String,
      measurementTimestamp:
          DateTime.tryParse(map['measurement_timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      receivedAt:
          DateTime.tryParse(map['received_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      cumulativeEnergyKwh:
          (map['cumulative_energy_kwh'] as num?)?.toDouble() ?? 0,
      intervalEnergyKwh: (map['interval_energy_kwh'] as num?)?.toDouble(),
      voltageV: (map['voltage_v'] as num?)?.toDouble(),
      currentA: (map['current_a'] as num?)?.toDouble(),
      powerW: (map['power_w'] as num?)?.toDouble(),
      powerFactor: (map['power_factor'] as num?)?.toDouble(),
      frequencyHz: (map['frequency_hz'] as num?)?.toDouble(),
      sequenceNumber: (map['sequence_number'] as num?)?.toInt(),
      validationStatus: map['validation_status'] as String? ?? 'pending',
      validationReason: map['validation_reason'] as String?,
    );
  }
}

abstract final class MeterRegistrationService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<MeterUnitOption>> fetchAssignableUnits() async {
    final responses = await Future.wait([
      _client
          .from('rental_unit')
          .select('unit_id, unit_number, block_and_floor, unit_status')
          .inFilter('unit_status', ['available', 'occupied'])
          .order('unit_number'),
      _client.from('electricity_device').select('unit_id').inFilter(
        'device_status',
        ['pending', 'active', 'offline'],
      ),
    ]);

    final occupiedUnitIds = (responses[1] as List)
        .map((row) => (row as Map)['unit_id']?.toString())
        .whereType<String>()
        .toSet();

    return (responses[0] as List)
        .map(
          (row) =>
              MeterUnitOption.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .where((unit) => !occupiedUnitIds.contains(unit.unitId))
        .toList();
  }

  static Future<List<RegisteredMeterRecord>> fetchRegisteredMeters() async {
    final rows = await _client
        .from('electricity_device')
        .select(
          'device_id, device_identifier, meter_serial_number, meter_model, '
          'modbus_slave_id, sampling_interval_sec, calibration_factor, '
          'measurement_tolerance, initial_cumulative_kwh, installation_date, '
          'data_source, device_status, last_seen_at, registered_at, '
          'rental_unit(unit_number, block_and_floor)',
        )
        .order('registered_at', ascending: false);

    final meterRows = (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final deviceIds = meterRows
        .map((row) => row['device_id']?.toString())
        .whereType<String>()
        .toList();

    final latestByDevice = <String, MeterReadingRecord>{};
    if (deviceIds.isNotEmpty) {
      final readingRows = await _client
          .from('electricity_reading')
          .select(
            'reading_id, device_id, measurement_timestamp, received_at, '
            'cumulative_energy_kwh, interval_energy_kwh, voltage_v, current_a, '
            'power_w, power_factor, frequency_hz, sequence_number, '
            'validation_status, validation_reason',
          )
          .inFilter('device_id', deviceIds)
          .order('measurement_timestamp', ascending: false);

      for (final row in readingRows as List) {
        final reading = MeterReadingRecord.fromMap(
          Map<String, dynamic>.from(row as Map),
        );
        latestByDevice.putIfAbsent(reading.deviceId, () => reading);
      }
    }

    return meterRows
        .map(
          (row) => RegisteredMeterRecord.fromMap(
            row,
            latestReading: latestByDevice[row['device_id']?.toString()],
          ),
        )
        .toList();
  }

  static Future<List<MeterReadingRecord>> fetchMeterReadings(
    String deviceId, {
    int limit = 30,
  }) async {
    final rows = await _client
        .from('electricity_reading')
        .select(
          'reading_id, device_id, measurement_timestamp, received_at, '
          'cumulative_energy_kwh, interval_energy_kwh, voltage_v, current_a, '
          'power_w, power_factor, frequency_hz, sequence_number, '
          'validation_status, validation_reason',
        )
        .eq('device_id', deviceId)
        .order('measurement_timestamp', ascending: false)
        .limit(limit);

    return (rows as List)
        .map(
          (row) =>
              MeterReadingRecord.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  static Future<String> registerSimulatedMeter({
    required String unitId,
    required String deviceIdentifier,
    required String meterSerialNumber,
    required int modbusSlaveId,
    required int samplingIntervalSec,
    required double calibrationFactor,
    required double measurementTolerance,
    required double initialCumulativeKwh,
    required DateTime installationDate,
  }) async {
    final administratorId = _client.auth.currentUser?.id;
    if (administratorId == null) {
      throw StateError('The administrator session has expired.');
    }

    final row = await _client
        .from('electricity_device')
        .insert({
          'unit_id': unitId,
          'registered_by_admin_id': administratorId,
          'device_identifier': deviceIdentifier.trim(),
          'meter_serial_number': meterSerialNumber.trim(),
          'meter_model': 'CHINT DDSU666 5(80)A 2P',
          'communication_type': 'RS485 Modbus-RTU',
          'modbus_slave_id': modbusSlaveId,
          'reading_type': 'cumulative_kwh',
          'sampling_interval_sec': samplingIntervalSec,
          'calibration_factor': calibrationFactor,
          'measurement_tolerance': measurementTolerance,
          'initial_cumulative_kwh': initialCumulativeKwh,
          'installation_date': _dateValue(installationDate),
          'data_source': 'simulated',
          'device_status': 'pending',
        })
        .select('device_id')
        .single();

    return row['device_id'] as String;
  }

  static String _dateValue(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
