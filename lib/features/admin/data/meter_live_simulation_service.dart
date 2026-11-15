import 'package:supabase_flutter/supabase_flutter.dart';

import 'ddsu666_graph_demo_dataset.dart';
import 'meter_registration_service.dart';

class MeterLiveSimulationEvent {
  const MeterLiveSimulationEvent({
    required this.completed,
    required this.total,
    required this.status,
    required this.reason,
    required this.powerW,
    required this.cumulativeEnergyKwh,
  });

  final int completed;
  final int total;
  final String status;
  final String reason;
  final double powerW;
  final double cumulativeEnergyKwh;
}

class MeterLiveSimulationSummary {
  const MeterLiveSimulationSummary({
    required this.submitted,
    required this.accepted,
    required this.flagged,
    required this.rejected,
    required this.errors,
    required this.cancelled,
  });

  final int submitted;
  final int accepted;
  final int flagged;
  final int rejected;
  final int errors;
  final bool cancelled;
}

class MeterLiveSimulationService {
  static const int readingCount = 8;
  static const Duration interval = Duration(seconds: 30);

  static SupabaseClient get _client => Supabase.instance.client;

  bool _cancelRequested = false;

  void cancel() => _cancelRequested = true;

  Future<MeterLiveSimulationSummary> run({
    required RegisteredMeterRecord meter,
    void Function(MeterLiveSimulationEvent event)? onReading,
  }) async {
    if (meter.dataSource != 'simulated') {
      throw StateError(
        'Live simulation is available only for simulated meters.',
      );
    }

    _cancelRequested = false;
    final existingReadings = await MeterRegistrationService.fetchMeterReadings(
      meter.deviceId,
      limit: 200,
    );
    var sequence = 0;
    MeterReadingRecord? latestAccepted;
    for (final reading in existingReadings) {
      final candidate = reading.sequenceNumber ?? 0;
      if (candidate > sequence) sequence = candidate;
      if (latestAccepted == null && reading.validationStatus == 'accepted') {
        latestAccepted = reading;
      }
    }

    var cumulativeEnergy =
        latestAccepted?.cumulativeEnergyKwh ?? meter.initialCumulativeKwh;
    final runId =
        'live-${DateTime.now().toUtc().millisecondsSinceEpoch}-${meter.deviceIdentifier}';
    var accepted = 0;
    var flagged = 0;
    var rejected = 0;
    var errors = 0;
    var submitted = 0;

    for (var index = 0; index < readingCount; index++) {
      if (_cancelRequested) break;
      if (index > 0) {
        await Future<void>.delayed(interval);
        if (_cancelRequested) break;
      }

      final sample = ddsu666GraphDemoDataset[index];
      final powerW = sample.powerW;
      final voltageV = sample.voltageV;
      final powerFactor = sample.powerFactor;
      final currentA = sample.currentA;
      cumulativeEnergy += (powerW / 1000) * (interval.inSeconds / 3600);
      sequence += 1;

      var status = 'error';
      var reason = 'The backend did not return a validation result.';
      try {
        final response = await _client.functions.invoke(
          'ingest-meter-reading',
          body: {
            'device_identifier': meter.deviceIdentifier,
            'modbus_slave_id': meter.modbusSlaveId,
            'measurement_timestamp': DateTime.now().toUtc().toIso8601String(),
            'sequence_number': sequence,
            'cumulative_energy_kwh': double.parse(
              cumulativeEnergy.toStringAsFixed(6),
            ),
            'voltage_v': double.parse(voltageV.toStringAsFixed(3)),
            'current_a': double.parse(currentA.toStringAsFixed(3)),
            'power_w': powerW,
            'power_factor': powerFactor,
            'frequency_hz': sample.frequencyHz,
            'test_run_id': runId,
          },
        );
        final rawData = response.data;
        final data = rawData is Map
            ? Map<String, dynamic>.from(rawData)
            : const <String, dynamic>{};
        status = data['validation_status']?.toString() ?? 'error';
        reason =
            data['validation_reason']?.toString() ??
            data['error']?.toString() ??
            reason;
      } on FunctionException catch (error) {
        reason =
            error.details?.toString() ??
            error.reasonPhrase ??
            'The Edge Function request failed.';
      } catch (error) {
        reason = error.toString();
      }

      submitted += 1;
      switch (status) {
        case 'accepted':
          accepted += 1;
        case 'flagged':
          flagged += 1;
        case 'rejected':
          rejected += 1;
        default:
          errors += 1;
      }

      onReading?.call(
        MeterLiveSimulationEvent(
          completed: submitted,
          total: readingCount,
          status: status,
          reason: reason,
          powerW: powerW,
          cumulativeEnergyKwh: cumulativeEnergy,
        ),
      );
    }

    return MeterLiveSimulationSummary(
      submitted: submitted,
      accepted: accepted,
      flagged: flagged,
      rejected: rejected,
      errors: errors,
      cancelled: _cancelRequested,
    );
  }
}
