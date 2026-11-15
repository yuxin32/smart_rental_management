import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/meter_dataset_test_service.dart';
import '../../data/meter_registration_service.dart';
import '../widgets/admin_ui.dart';

class AdminMeterDatasetTestPage extends StatefulWidget {
  const AdminMeterDatasetTestPage({required this.meter, super.key});

  final RegisteredMeterRecord meter;

  @override
  State<AdminMeterDatasetTestPage> createState() =>
      _AdminMeterDatasetTestPageState();
}

class _AdminMeterDatasetTestPageState extends State<AdminMeterDatasetTestPage> {
  MeterDatasetScenario _scenario = MeterDatasetScenario.normal;
  MeterDatasetSummary? _summary;
  bool _running = false;
  int _completed = 0;
  int _total = 0;

  Future<void> _runDataset() async {
    if (_running) return;
    setState(() {
      _running = true;
      _summary = null;
      _completed = 0;
      _total = _scenario == MeterDatasetScenario.normal ? 5 : 8;
    });

    try {
      final summary = await MeterDatasetTestService.run(
        meter: widget.meter,
        scenario: _scenario,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _completed = completed;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Dataset test could not start: $error')),
        );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const AdminBackAppBar(title: 'Dataset Validation Test'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          AdminCard(
            color: const Color(0xFFEEF3FF),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AdminIconBox(
                  icon: Icons.science_outlined,
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
                        '${widget.meter.unitLabel} · Modbus ${widget.meter.modbusSlaveId}',
                        style: const TextStyle(
                          color: AppColors.body,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Every generated record is sent through the backend ingestion function. The Flutter application does not insert readings directly.',
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
          const SizedBox(height: 20),
          const Text(
            'Select test scenario',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final scenario in MeterDatasetScenario.values) ...[
            _ScenarioCard(
              scenario: scenario,
              selected: _scenario == scenario,
              enabled: !_running,
              onTap: () => setState(() => _scenario = scenario),
            ),
            if (scenario != MeterDatasetScenario.values.last)
              const SizedBox(height: 10),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _running ? null : _runDataset,
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(
                _running
                    ? 'Processing $_completed of $_total records'
                    : 'Run dataset test',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primary.withAlpha(150),
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
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _total == 0 ? null : _completed / _total,
              borderRadius: BorderRadius.circular(20),
            ),
          ],
          if (_summary != null) ...[
            const SizedBox(height: 24),
            _TestSummaryCard(summary: _summary!),
            const SizedBox(height: 20),
            const Text(
              'Validation evidence',
              style: TextStyle(
                color: AppColors.heading,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < _summary!.results.length; index++) ...[
              _ResultCard(result: _summary!.results[index]),
              if (index < _summary!.results.length - 1)
                const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.scenario,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final MeterDatasetScenario scenario;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      color: selected ? const Color(0xFFEFF2FF) : Colors.white,
      onTap: enabled ? onTap : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected ? AppColors.primary : const Color(0xFF9CA4B3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scenario.label,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  scenario.description,
                  style: const TextStyle(
                    color: AppColors.body,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TestSummaryCard extends StatelessWidget {
  const _TestSummaryCard({required this.summary});

  final MeterDatasetSummary summary;

  @override
  Widget build(BuildContext context) {
    final success = summary.allExpectationsMet;
    final color = success ? AppColors.success : const Color(0xFFE8953E);
    return AdminCard(
      color: success ? const Color(0xFFEAF8EF) : const Color(0xFFFFF7EA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                success ? Icons.verified_rounded : Icons.warning_amber_rounded,
                color: color,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  success
                      ? 'All expected results matched'
                      : 'Some results require review',
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryPill(label: 'Submitted', value: summary.submitted),
              _SummaryPill(label: 'Accepted', value: summary.accepted),
              _SummaryPill(label: 'Flagged', value: summary.flagged),
              _SummaryPill(label: 'Rejected', value: summary.rejected),
              _SummaryPill(label: 'Duplicate', value: summary.duplicates),
              if (summary.failed > 0)
                _SummaryPill(label: 'Errors', value: summary.failed),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: AppColors.heading,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final MeterDatasetResult result;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(result.actualStatus);
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.passed
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: result.passed
                    ? AppColors.success
                    : const Color(0xFFD9534F),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.caseName,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AdminStatusPill(
                label: _titleCase(result.actualStatus),
                foregroundColor: color,
                backgroundColor: color.withAlpha(24),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Expected: ${_titleCase(result.expectedStatus)} · ${result.stored ? 'Stored' : 'Not stored'}',
            style: const TextStyle(color: AppColors.body, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            result.reason,
            style: const TextStyle(
              color: AppColors.body,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(String status) {
  return switch (status) {
    'accepted' => AppColors.success,
    'flagged' => const Color(0xFFE8953E),
    'rejected' => const Color(0xFFD9534F),
    'duplicate' => AppColors.primary,
    _ => AppColors.body,
  };
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
