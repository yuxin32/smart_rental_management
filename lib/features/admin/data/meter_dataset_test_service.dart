import 'package:supabase_flutter/supabase_flutter.dart';

import 'meter_registration_service.dart';

enum MeterDatasetScenario { normal, mixed }

extension MeterDatasetScenarioDetails on MeterDatasetScenario {
  String get label => switch (this) {
    MeterDatasetScenario.normal => 'Normal readings',
    MeterDatasetScenario.mixed => 'Mixed validation test',
  };

  String get description => switch (this) {
    MeterDatasetScenario.normal =>
      'Sends five valid, increasing cumulative-kWh readings. All records should be accepted.',
    MeterDatasetScenario.mixed =>
      'Sends valid, duplicate, sequence-gap, invalid, and abnormal records to exercise each validation outcome.',
  };
}

class MeterDatasetResult {
  const MeterDatasetResult({
    required this.caseName,
    required this.expectedStatus,
    required this.actualStatus,
    required this.reason,
    required this.stored,
    required this.readingId,
  });

  final String caseName;
  final String expectedStatus;
  final String actualStatus;
  final String reason;
  final bool stored;
  final String? readingId;

  bool get passed => expectedStatus == actualStatus;
}

class MeterDatasetSummary {
  const MeterDatasetSummary({
    required this.runId,
    required this.scenario,
    required this.results,
  });

  final String runId;
  final MeterDatasetScenario scenario;
  final List<MeterDatasetResult> results;

  int get submitted => results.length;
  int get accepted => _count('accepted');
  int get flagged => _count('flagged');
  int get rejected => _count('rejected');
  int get duplicates => _count('duplicate');
  int get failed => _count('error');
  int get passedCases => results.where((result) => result.passed).length;
  bool get allExpectationsMet => passedCases == submitted;

  int _count(String status) =>
      results.where((result) => result.actualStatus == status).length;
}

class _DatasetRecord {
  const _DatasetRecord({
    required this.caseName,
    required this.expectedStatus,
    required this.payload,
  });

  final String caseName;
  final String expectedStatus;
  final Map<String, dynamic> payload;
}

abstract final class MeterDatasetTestService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<MeterDatasetSummary> run({
    required RegisteredMeterRecord meter,
    required MeterDatasetScenario scenario,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (meter.dataSource != 'simulated') {
      throw StateError(
        'Dataset testing is available only for simulated meters.',
      );
    }

    final existingReadings = await MeterRegistrationService.fetchMeterReadings(
      meter.deviceId,
      limit: 200,
    );
    var maximumSequence = 0;
    MeterReadingRecord? latestAccepted;
    for (final reading in existingReadings) {
      final sequence = reading.sequenceNumber ?? 0;
      if (sequence > maximumSequence) maximumSequence = sequence;
      if (latestAccepted == null && reading.validationStatus == 'accepted') {
        latestAccepted = reading;
      }
    }

    final baseline =
        latestAccepted?.cumulativeEnergyKwh ?? meter.initialCumulativeKwh;
    final runId =
        'dataset-${DateTime.now().toUtc().millisecondsSinceEpoch}-${meter.deviceIdentifier}';
    final records = switch (scenario) {
      MeterDatasetScenario.normal => _normalRecords(
        meter: meter,
        runId: runId,
        sequenceBase: maximumSequence,
        cumulativeBase: baseline,
      ),
      MeterDatasetScenario.mixed => _mixedRecords(
        meter: meter,
        runId: runId,
        sequenceBase: maximumSequence,
        cumulativeBase: baseline,
      ),
    };

    final results = <MeterDatasetResult>[];
    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      try {
        final response = await _client.functions.invoke(
          'ingest-meter-reading',
          body: record.payload,
        );
        final rawData = response.data;
        final data = rawData is Map
            ? Map<String, dynamic>.from(rawData)
            : const <String, dynamic>{};
        results.add(
          MeterDatasetResult(
            caseName: record.caseName,
            expectedStatus: record.expectedStatus,
            actualStatus: data['validation_status']?.toString() ?? 'error',
            reason:
                data['validation_reason']?.toString() ??
                data['error']?.toString() ??
                'No response reason was returned.',
            stored: data['stored'] == true,
            readingId: data['reading_id']?.toString(),
          ),
        );
      } on FunctionException catch (error) {
        results.add(
          MeterDatasetResult(
            caseName: record.caseName,
            expectedStatus: record.expectedStatus,
            actualStatus: 'error',
            reason:
                error.details?.toString() ??
                error.reasonPhrase ??
                'The Edge Function request failed.',
            stored: false,
            readingId: null,
          ),
        );
      } catch (error) {
        results.add(
          MeterDatasetResult(
            caseName: record.caseName,
            expectedStatus: record.expectedStatus,
            actualStatus: 'error',
            reason: error.toString(),
            stored: false,
            readingId: null,
          ),
        );
      }
      onProgress?.call(index + 1, records.length);
    }

    return MeterDatasetSummary(
      runId: runId,
      scenario: scenario,
      results: results,
    );
  }

  static List<_DatasetRecord> _normalRecords({
    required RegisteredMeterRecord meter,
    required String runId,
    required int sequenceBase,
    required double cumulativeBase,
  }) {
    const increments = [0.041, 0.042, 0.045, 0.042, 0.044];
    var cumulative = cumulativeBase;
    final start = DateTime.now().toUtc().subtract(const Duration(seconds: 12));

    return List.generate(increments.length, (index) {
      cumulative += increments[index];
      return _DatasetRecord(
        caseName: 'Normal reading ${index + 1}',
        expectedStatus: 'accepted',
        payload: _payload(
          meter: meter,
          runId: runId,
          timestamp: start.add(Duration(seconds: index * 2)),
          sequenceNumber: sequenceBase + index + 1,
          cumulativeEnergyKwh: cumulative,
        ),
      );
    });
  }

  static List<_DatasetRecord> _mixedRecords({
    required RegisteredMeterRecord meter,
    required String runId,
    required int sequenceBase,
    required double cumulativeBase,
  }) {
    final start = DateTime.now().toUtc().subtract(const Duration(seconds: 20));
    final first = _payload(
      meter: meter,
      runId: runId,
      timestamp: start,
      sequenceNumber: sequenceBase + 1,
      cumulativeEnergyKwh: cumulativeBase + 0.041,
    );
    final second = _payload(
      meter: meter,
      runId: runId,
      timestamp: start.add(const Duration(seconds: 2)),
      sequenceNumber: sequenceBase + 2,
      cumulativeEnergyKwh: cumulativeBase + 0.083,
    );

    return [
      _DatasetRecord(
        caseName: 'Valid baseline reading',
        expectedStatus: 'accepted',
        payload: first,
      ),
      _DatasetRecord(
        caseName: 'Valid increasing reading',
        expectedStatus: 'accepted',
        payload: second,
      ),
      _DatasetRecord(
        caseName: 'Duplicate timestamp and sequence',
        expectedStatus: 'duplicate',
        payload: {...second, 'test_case_id': 'duplicate'},
      ),
      _DatasetRecord(
        caseName: 'Sequence gap',
        expectedStatus: 'flagged',
        payload: _payload(
          meter: meter,
          runId: runId,
          timestamp: start.add(const Duration(seconds: 6)),
          sequenceNumber: sequenceBase + 4,
          cumulativeEnergyKwh: cumulativeBase + 0.125,
        ),
      ),
      _DatasetRecord(
        caseName: 'Invalid power factor',
        expectedStatus: 'rejected',
        payload: _payload(
          meter: meter,
          runId: runId,
          timestamp: start.add(const Duration(seconds: 8)),
          sequenceNumber: sequenceBase + 5,
          cumulativeEnergyKwh: cumulativeBase + 0.166,
          powerFactor: 1.20,
        ),
      ),
      _DatasetRecord(
        caseName: 'Decreasing cumulative energy',
        expectedStatus: 'rejected',
        payload: _payload(
          meter: meter,
          runId: runId,
          timestamp: start.add(const Duration(seconds: 10)),
          sequenceNumber: sequenceBase + 6,
          cumulativeEnergyKwh: (cumulativeBase - 0.500).clamp(
            0,
            double.infinity,
          ),
        ),
      ),
      _DatasetRecord(
        caseName: 'Abnormal interval increase',
        expectedStatus: 'flagged',
        payload: _payload(
          meter: meter,
          runId: runId,
          timestamp: start.add(const Duration(seconds: 12)),
          sequenceNumber: sequenceBase + 7,
          cumulativeEnergyKwh: cumulativeBase + 5.000,
        ),
      ),
      _DatasetRecord(
        caseName: 'Modbus address mismatch',
        expectedStatus: 'rejected',
        payload: _payload(
          meter: meter,
          runId: runId,
          timestamp: start.add(const Duration(seconds: 14)),
          sequenceNumber: sequenceBase + 8,
          cumulativeEnergyKwh: cumulativeBase + 0.212,
          modbusSlaveId: meter.modbusSlaveId == 247
              ? 246
              : meter.modbusSlaveId + 1,
        ),
      ),
    ];
  }

  static Map<String, dynamic> _payload({
    required RegisteredMeterRecord meter,
    required String runId,
    required DateTime timestamp,
    required int sequenceNumber,
    required double cumulativeEnergyKwh,
    int? modbusSlaveId,
    double powerFactor = 0.95,
  }) {
    const voltage = 238.4;
    const current = 2.15;
    final power = voltage * current * powerFactor.clamp(0, 1);
    return {
      'device_identifier': meter.deviceIdentifier,
      'modbus_slave_id': modbusSlaveId ?? meter.modbusSlaveId,
      'measurement_timestamp': timestamp.toIso8601String(),
      'sequence_number': sequenceNumber,
      'cumulative_energy_kwh': double.parse(
        cumulativeEnergyKwh.toStringAsFixed(6),
      ),
      'voltage_v': voltage,
      'current_a': current,
      'power_w': double.parse(power.toStringAsFixed(3)),
      'power_factor': powerFactor,
      'frequency_hz': 50.0,
      'test_run_id': runId,
    };
  }
}
