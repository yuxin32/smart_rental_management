import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/meter_live_simulation_service.dart';
import '../../data/meter_registration_service.dart';
import '../widgets/admin_ui.dart';

class AdminMeterLiveSimulationPage extends StatefulWidget {
  const AdminMeterLiveSimulationPage({required this.meter, super.key});

  final RegisteredMeterRecord meter;

  @override
  State<AdminMeterLiveSimulationPage> createState() =>
      _AdminMeterLiveSimulationPageState();
}

class _AdminMeterLiveSimulationPageState
    extends State<AdminMeterLiveSimulationPage> {
  MeterLiveSimulationService? _service;
  MeterLiveSimulationEvent? _latestEvent;
  MeterLiveSimulationSummary? _summary;
  bool _running = false;

  Future<void> _start() async {
    if (_running) return;
    final service = MeterLiveSimulationService();
    setState(() {
      _service = service;
      _latestEvent = null;
      _summary = null;
      _running = true;
    });

    try {
      final summary = await service.run(
        meter: widget.meter,
        onReading: (event) {
          if (!mounted) return;
          setState(() => _latestEvent = event);
        },
      );
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Live simulation could not start: $error')),
        );
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _service = null;
        });
      }
    }
  }

  void _stop() {
    _service?.cancel();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _latestEvent;
    final progress = event == null
        ? 0.0
        : event.completed / MeterLiveSimulationService.readingCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const AdminBackAppBar(title: 'Live Graph Dataset'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          AdminCard(
            color: const Color(0xFFEEF3FF),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AdminIconBox(
                  icon: Icons.waves_rounded,
                  color: AppColors.primary,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.meter.deviceIdentifier,
                        style: const TextStyle(
                          color: AppColors.heading,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.meter.unitLabel,
                        style: const TextStyle(
                          color: AppColors.body,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'For this FYP prototype, a short dataset represents readings retrieved from the DDSU666 by an ESP32. Every record still passes through the real backend validation and storage path.',
                        style: TextStyle(
                          color: Color(0xFF5D75B4),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Demonstration settings',
                  style: TextStyle(
                    color: AppColors.heading,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                const _SettingLine(
                  icon: Icons.data_array_rounded,
                  label: 'Readings',
                  value: '8 records',
                ),
                const _SettingLine(
                  icon: Icons.timer_outlined,
                  label: 'Interval',
                  value: 'Every 30 seconds',
                ),
                const _SettingLine(
                  icon: Icons.verified_outlined,
                  label: 'Processing',
                  value: 'Backend validation',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AdminCard(
            color: const Color(0xFFFFF8E8),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.devices_outlined, color: Color(0xFFE8953E)),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'For a live demonstration, keep this administrator page open in one session and open the assigned tenant account on another device or browser.',
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_running || event != null) ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Simulation progress',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${event?.completed ?? 0}/${MeterLiveSimulationService.readingCount}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(20),
            ),
            if (event != null) ...[
              const SizedBox(height: 12),
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _LiveValue(
                            label: 'Latest power',
                            value: '${event.powerW.toStringAsFixed(0)} W',
                          ),
                        ),
                        Expanded(
                          child: _LiveValue(
                            label: 'Cumulative',
                            value:
                                '${event.cumulativeEnergyKwh.toStringAsFixed(4)} kWh',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Backend result: ${_titleCase(event.status)}',
                      style: TextStyle(
                        color: _statusColor(event.status),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
          ],
          if (_summary != null) ...[
            AdminCard(
              color: _summary!.cancelled
                  ? const Color(0xFFFFF7EA)
                  : const Color(0xFFEAF8EF),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _summary!.cancelled
                        ? 'Simulation stopped'
                        : 'Simulation completed',
                    style: const TextStyle(
                      color: AppColors.heading,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_summary!.accepted} accepted · ${_summary!.flagged} flagged · ${_summary!.rejected} rejected · ${_summary!.errors} errors',
                    style: const TextStyle(color: AppColors.body, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _summary == null ? 'Run live graph dataset' : 'Run again',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primary.withAlpha(130),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (_running) ...[
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _stop,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Stop'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingLine extends StatelessWidget {
  const _SettingLine({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFECEFF3))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.body, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.heading,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveValue extends StatelessWidget {
  const _LiveValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.body, fontSize: 11),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.heading,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

Color _statusColor(String status) {
  return switch (status) {
    'accepted' => AppColors.success,
    'flagged' => const Color(0xFFE8953E),
    'rejected' => const Color(0xFFD9534F),
    _ => AppColors.body,
  };
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
