import 'package:supabase_flutter/supabase_flutter.dart';

class TenantElectricityMeter {
  const TenantElectricityMeter({
    required this.deviceId,
    required this.deviceIdentifier,
    required this.serialNumber,
    required this.model,
    required this.samplingIntervalSec,
    required this.status,
    required this.lastSeenAt,
    required this.unitNumber,
    required this.unitLocation,
  });

  final String deviceId;
  final String deviceIdentifier;
  final String serialNumber;
  final String model;
  final int samplingIntervalSec;
  final String status;
  final DateTime? lastSeenAt;
  final String unitNumber;
  final String? unitLocation;

  String get unitLabel {
    if (unitLocation == null || unitLocation!.trim().isEmpty) {
      return unitNumber;
    }
    return '${unitLocation!.trim()} · $unitNumber';
  }

  factory TenantElectricityMeter.fromMap(Map<String, dynamic> map) {
    final unit = map['rental_unit'] is Map
        ? Map<String, dynamic>.from(map['rental_unit'] as Map)
        : <String, dynamic>{};

    return TenantElectricityMeter(
      deviceId: map['device_id'] as String,
      deviceIdentifier: map['device_identifier'] as String? ?? '',
      serialNumber: map['meter_serial_number'] as String? ?? '',
      model: map['meter_model'] as String? ?? 'Electricity meter',
      samplingIntervalSec:
          (map['sampling_interval_sec'] as num?)?.toInt() ?? 300,
      status: map['device_status'] as String? ?? 'pending',
      lastSeenAt: DateTime.tryParse(map['last_seen_at']?.toString() ?? ''),
      unitNumber: unit['unit_number'] as String? ?? 'Assigned unit',
      unitLocation: unit['block_and_floor'] as String?,
    );
  }
}

class TenantElectricityReading {
  const TenantElectricityReading({
    required this.readingId,
    required this.measurementTimestamp,
    required this.receivedAt,
    required this.cumulativeEnergyKwh,
    required this.intervalEnergyKwh,
    required this.voltageV,
    required this.currentA,
    required this.powerW,
    required this.powerFactor,
    required this.frequencyHz,
  });

  final String readingId;
  final DateTime measurementTimestamp;
  final DateTime receivedAt;
  final double cumulativeEnergyKwh;
  final double? intervalEnergyKwh;
  final double? voltageV;
  final double? currentA;
  final double? powerW;
  final double? powerFactor;
  final double? frequencyHz;

  factory TenantElectricityReading.fromMap(Map<String, dynamic> map) {
    return TenantElectricityReading(
      readingId: map['reading_id'] as String,
      measurementTimestamp:
          DateTime.tryParse(map['measurement_timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      receivedAt:
          DateTime.tryParse(map['received_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      cumulativeEnergyKwh:
          (map['cumulative_energy_kwh'] as num?)?.toDouble() ?? 0,
      intervalEnergyKwh: (map['interval_energy_kwh'] as num?)?.toDouble(),
      voltageV: (map['voltage_v'] as num?)?.toDouble(),
      currentA: (map['current_a'] as num?)?.toDouble(),
      powerW: (map['power_w'] as num?)?.toDouble(),
      powerFactor: (map['power_factor'] as num?)?.toDouble(),
      frequencyHz: (map['frequency_hz'] as num?)?.toDouble(),
    );
  }
}

abstract final class TenantElectricityService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<TenantElectricityMeter?> fetchActiveMeter() async {
    final rows = await _client
        .from('electricity_device')
        .select(
          'device_id, device_identifier, meter_serial_number, meter_model, '
          'sampling_interval_sec, device_status, last_seen_at, registered_at, '
          'rental_unit(unit_number, block_and_floor)',
        )
        .eq('device_status', 'active')
        .order('registered_at', ascending: false)
        .limit(1);

    final records = rows as List;
    if (records.isEmpty) return null;
    return TenantElectricityMeter.fromMap(
      Map<String, dynamic>.from(records.first as Map),
    );
  }

  static Stream<List<TenantElectricityReading>> watchAcceptedReadings(
    String deviceId, {
    int limit = 60,
  }) {
    return _client
        .from('electricity_reading')
        .stream(primaryKey: ['reading_id'])
        .eq('device_id', deviceId)
        .order('measurement_timestamp', ascending: false)
        .limit(limit)
        .map((rows) {
          final readings = rows
              .where((row) => row['validation_status'] == 'accepted')
              .map(
                (row) => TenantElectricityReading.fromMap(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList();
          readings.sort(
            (left, right) =>
                left.measurementTimestamp.compareTo(right.measurementTimestamp),
          );
          return readings;
        });
  }
}
