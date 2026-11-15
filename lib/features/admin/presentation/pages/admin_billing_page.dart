import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/meter_registration_service.dart';
import '../widgets/admin_ui.dart';
import 'admin_meter_dataset_test_page.dart';
import 'admin_meter_live_simulation_page.dart';
import 'admin_register_meter_page.dart';

class AdminBillingPage extends StatefulWidget {
  const AdminBillingPage({super.key});

  @override
  State<AdminBillingPage> createState() => _AdminBillingPageState();
}

class _AdminBillingPageState extends State<AdminBillingPage> {
  late Future<List<RegisteredMeterRecord>> _metersFuture;

  @override
  void initState() {
    super.initState();
    _refreshMeters();
  }

  void _refreshMeters() {
    _metersFuture = MeterRegistrationService.fetchRegisteredMeters();
  }

  Future<void> _openRegistration() async {
    final deviceId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AdminRegisterMeterPage()),
    );
    if (deviceId == null || !mounted) return;

    setState(_refreshMeters);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('The simulated meter was registered successfully.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          AdminScreenTitle(
            title: 'Meters & Billing',
            subtitle: 'Review readings and prepare rental bills',
            action: IconButton(
              tooltip: 'Register meter',
              onPressed: _openRegistration,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFE6EBFF),
                foregroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AdminCard(
              color: const Color(0xFFEEF3FF),
              child: Row(
                children: [
                  const AdminIconBox(
                    icon: Icons.electric_meter_rounded,
                    color: AppColors.primary,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Electricity reading status',
                          style: TextStyle(
                            color: AppColors.heading,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '85 accepted · 1 flagged · 0 missing',
                          style: TextStyle(color: AppColors.body, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  AdminStatusPill(
                    label: 'Good',
                    foregroundColor: AppColors.success,
                    backgroundColor: Colors.white,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              'Registered meters',
              style: TextStyle(
                color: AppColors.heading,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FutureBuilder<List<RegisteredMeterRecord>>(
              future: _metersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const AdminCard(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return AdminCard(
                    child: Column(
                      children: [
                        const Text(
                          'Registered meters could not be loaded.',
                          style: TextStyle(color: AppColors.body),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => setState(_refreshMeters),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final meters = snapshot.data ?? const [];
                if (meters.isEmpty) {
                  return AdminCard(
                    child: Column(
                      children: [
                        const AdminIconBox(
                          icon: Icons.electric_meter_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'No electricity meter registered',
                          style: TextStyle(
                            color: AppColors.heading,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Register a simulated DDSU666 meter to begin dataset testing.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.body, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _openRegistration,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Register meter'),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    for (var index = 0; index < meters.length; index++) ...[
                      _RegisteredMeterCard(
                        meter: meters[index],
                        onUpdated: () => setState(_refreshMeters),
                      ),
                      if (index < meters.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              'Current billing period',
              style: TextStyle(
                color: AppColors.heading,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AdminCard(
              child: Column(
                children: [
                  const _BillingLine(
                    label: 'Billing period',
                    value: '1 Mar – 31 Mar 2026',
                    icon: Icons.date_range_outlined,
                  ),
                  const _BillingLine(
                    label: 'Effective tariff',
                    value: 'Residential TNB · RM 0.57/kWh',
                    icon: Icons.payments_outlined,
                  ),
                  const _BillingLine(
                    label: 'Bills ready',
                    value: '85 of 86 units',
                    icon: Icons.receipt_long_outlined,
                    valueColor: AppColors.success,
                    last: true,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AdminGenerateBillsPage(),
                        ),
                      ),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Generate rental & utility bills'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              'Validation exception',
              style: TextStyle(
                color: AppColors.heading,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AdminCard(
              color: const Color(0xFFFFF7EA),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdminIconBox(
                    icon: Icons.warning_amber_rounded,
                    color: Color(0xFFE8953E),
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unusual cumulative-energy change',
                          style: TextStyle(
                            color: AppColors.heading,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Block A · A-12-08 · reading excluded from bill generation until reviewed.',
                          style: TextStyle(
                            color: AppColors.body,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisteredMeterCard extends StatelessWidget {
  const _RegisteredMeterCard({required this.meter, required this.onUpdated});

  final RegisteredMeterRecord meter;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context) {
    final statusColor = meter.status == 'active'
        ? AppColors.success
        : meter.status == 'pending'
        ? const Color(0xFFE8953E)
        : AppColors.body;

    return AdminCard(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdminMeterDetailsPage(meter: meter),
          ),
        );
        onUpdated();
      },
      child: Column(
        children: [
          Row(
            children: [
              const AdminIconBox(
                icon: Icons.sensors_outlined,
                color: Color(0xFF7C68D8),
                backgroundColor: Color(0xFFF0ECFF),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meter.model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.heading,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Meter ID: ${meter.deviceIdentifier}',
                      style: const TextStyle(
                        color: AppColors.body,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA4B3)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ReadingStat(
                  label: 'Mapped unit',
                  value: meter.unitNumber,
                ),
              ),
              Expanded(
                child: _ReadingStat(
                  label: 'Latest reading',
                  value: meter.latestReading == null
                      ? 'Awaiting dataset'
                      : '${meter.latestReading!.cumulativeEnergyKwh.toStringAsFixed(3)} kWh',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  meter.dataSource == 'simulated'
                      ? 'Simulated dataset source'
                      : 'Physical ESP32 source',
                  style: const TextStyle(color: AppColors.body, fontSize: 11),
                ),
              ),
              AdminStatusPill(
                label: _titleCase(meter.status),
                foregroundColor: statusColor,
                backgroundColor: statusColor.withAlpha(24),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AdminMeterDetailsPage extends StatefulWidget {
  const AdminMeterDetailsPage({required this.meter, super.key});

  final RegisteredMeterRecord meter;

  @override
  State<AdminMeterDetailsPage> createState() => _AdminMeterDetailsPageState();
}

class _AdminMeterDetailsPageState extends State<AdminMeterDetailsPage> {
  late Future<List<MeterReadingRecord>> _readingsFuture;

  RegisteredMeterRecord get meter => widget.meter;

  @override
  void initState() {
    super.initState();
    _readingsFuture = MeterRegistrationService.fetchMeterReadings(
      meter.deviceId,
    );
  }

  Future<void> _refreshReadings() async {
    final future = MeterRegistrationService.fetchMeterReadings(meter.deviceId);
    setState(() => _readingsFuture = future);
    await future;
  }

  Future<void> _openDatasetTest() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminMeterDatasetTestPage(meter: meter),
      ),
    );
    if (!mounted) return;
    await _refreshReadings();
  }

  Future<void> _openLiveSimulation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminMeterLiveSimulationPage(meter: meter),
      ),
    );
    if (!mounted) return;
    await _refreshReadings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const AdminBackAppBar(title: 'Meter Details'),
      body: RefreshIndicator(
        onRefresh: _refreshReadings,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            AdminCard(
              child: Column(
                children: [
                  _MeterDetailLine(
                    label: 'Model',
                    value: meter.model,
                    icon: Icons.electric_meter_outlined,
                  ),
                  const _MeterDetailLine(
                    label: 'Communication',
                    value: 'RS485 Modbus-RTU',
                    icon: Icons.settings_ethernet_outlined,
                  ),
                  _MeterDetailLine(
                    label: 'Serial number',
                    value: meter.serialNumber,
                    icon: Icons.numbers_rounded,
                  ),
                  _MeterDetailLine(
                    label: 'Assigned unit',
                    value: meter.unitLabel,
                    icon: Icons.meeting_room_outlined,
                  ),
                  _MeterDetailLine(
                    label: 'Modbus address',
                    value: meter.modbusSlaveId.toString(),
                    icon: Icons.pin_outlined,
                  ),
                  _MeterDetailLine(
                    label: 'Sampling interval',
                    value: '${meter.samplingIntervalSec} seconds',
                    icon: Icons.schedule_outlined,
                  ),
                  _MeterDetailLine(
                    label: 'Initial reading',
                    value:
                        '${meter.initialCumulativeKwh.toStringAsFixed(3)} kWh',
                    icon: Icons.bolt_outlined,
                    last: true,
                  ),
                ],
              ),
            ),
            if (meter.dataSource == 'simulated') ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openDatasetTest,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Run dataset validation test'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openLiveSimulation,
                  icon: const Icon(Icons.waves_rounded),
                  label: const Text('Run live graph dataset'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Recent readings',
              style: TextStyle(
                color: AppColors.heading,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<MeterReadingRecord>>(
              future: _readingsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const AdminCard(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return AdminCard(
                    child: Column(
                      children: [
                        const Text(
                          'Meter readings could not be loaded.',
                          style: TextStyle(color: AppColors.body),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _refreshReadings,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final readings = snapshot.data ?? const [];
                if (readings.isEmpty) {
                  return const AdminCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AdminIconBox(
                          icon: Icons.dataset_outlined,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No readings received yet',
                                style: TextStyle(
                                  color: AppColors.heading,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'This meter will remain pending until its first dataset reading passes backend validation.',
                                style: TextStyle(
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

                return Column(
                  children: [
                    for (var index = 0; index < readings.length; index++) ...[
                      _MeterReadingCard(reading: readings[index]),
                      if (index < readings.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MeterReadingCard extends StatelessWidget {
  const _MeterReadingCard({required this.reading});

  final MeterReadingRecord reading;

  @override
  Widget build(BuildContext context) {
    final statusColor = _readingStatusColor(reading.validationStatus);
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatDateTime(reading.measurementTimestamp),
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AdminStatusPill(
                label: _titleCase(reading.validationStatus),
                foregroundColor: statusColor,
                backgroundColor: statusColor.withAlpha(24),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _ReadingStat(
                  label: 'Cumulative energy',
                  value:
                      '${reading.cumulativeEnergyKwh.toStringAsFixed(3)} kWh',
                ),
              ),
              Expanded(
                child: _ReadingStat(
                  label: 'Interval usage',
                  value: reading.intervalEnergyKwh == null
                      ? '—'
                      : '${reading.intervalEnergyKwh!.toStringAsFixed(3)} kWh',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_measurement(reading.voltageV, 'V')} · '
            '${_measurement(reading.currentA, 'A')} · '
            '${_measurement(reading.powerW, 'W')} · '
            'PF ${reading.powerFactor?.toStringAsFixed(2) ?? '—'} · '
            '${_measurement(reading.frequencyHz, 'Hz')}',
            style: const TextStyle(color: AppColors.body, fontSize: 11),
          ),
          if (reading.validationReason?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              reading.validationReason!,
              style: TextStyle(color: statusColor, fontSize: 11, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class AdminGenerateBillsPage extends StatelessWidget {
  const AdminGenerateBillsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const AdminBackAppBar(title: 'Generate Bills'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          const Text(
            'March 2026 billing run',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Review the validated inputs before creating bills.',
            style: TextStyle(color: AppColors.body, fontSize: 13),
          ),
          const SizedBox(height: 18),
          AdminCard(
            child: Column(
              children: const [
                _BillingLine(
                  label: 'Units ready for billing',
                  value: '85 units',
                  icon: Icons.home_work_outlined,
                ),
                _BillingLine(
                  label: 'Validated electricity readings',
                  value: '170 readings',
                  icon: Icons.electric_meter_outlined,
                ),
                _BillingLine(
                  label: 'Flagged readings excluded',
                  value: '1 reading',
                  icon: Icons.warning_amber_outlined,
                  valueColor: Color(0xFFE8953E),
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Bill preview',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          AdminCard(
            child: Column(
              children: const [
                _BillPreviewRow(
                  unit: 'A-12-08',
                  tenant: 'Alex Tan',
                  amount: 'RM 1,325.42',
                ),
                _BillPreviewRow(
                  unit: 'B-05-03',
                  tenant: 'Nur Izzati',
                  amount: 'RM 1,287.10',
                ),
                _BillPreviewRow(
                  unit: 'B-08-07',
                  tenant: 'Siti Hajar',
                  amount: 'RM 1,246.80',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AdminCard(
            color: const Color(0xFFF0F5FF),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The bill uses the active tenancy, validated cumulative kWh readings, effective tariff, rental amount, water charge, and shared-occupancy rule.',
                    style: TextStyle(
                      color: Color(0xFF5D75B4),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bills generated for preview.')),
                );
              },
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Generate bills'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingStat extends StatelessWidget {
  const _ReadingStat({required this.label, required this.value});

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
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.heading,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _BillingLine extends StatelessWidget {
  const _BillingLine({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor = AppColors.heading,
    this.last = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFECEFF3))),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.body, fontSize: 13),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeterDetailLine extends _BillingLine {
  const _MeterDetailLine({
    required super.label,
    required super.value,
    required super.icon,
    super.last,
  });
}

class _BillPreviewRow extends StatelessWidget {
  const _BillPreviewRow({
    required this.unit,
    required this.tenant,
    required this.amount,
    this.last = false,
  });

  final String unit;
  final String tenant;
  final String amount;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFECEFF3))),
      ),
      child: Row(
        children: [
          const AdminIconBox(
            icon: Icons.home_work_outlined,
            color: AppColors.primary,
            backgroundColor: Color(0xFFE6EBFF),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tenant,
                  style: const TextStyle(color: AppColors.body, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: const TextStyle(
              color: AppColors.heading,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

Color _readingStatusColor(String status) {
  return switch (status) {
    'accepted' => AppColors.success,
    'flagged' => const Color(0xFFE8953E),
    'rejected' => const Color(0xFFD9534F),
    _ => AppColors.body,
  };
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} · $hour:$minute';
}

String _measurement(double? value, String unit) {
  if (value == null) return '— $unit';
  final decimals = unit == 'W' ? 0 : 2;
  return '${value.toStringAsFixed(decimals)} $unit';
}
