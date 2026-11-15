import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/tenant_electricity_service.dart';
import '../widgets/tenant_ui.dart';
import 'tenant_meter_details_page.dart';

class TenantDevicesPage extends StatefulWidget {
  const TenantDevicesPage({super.key});

  @override
  State<TenantDevicesPage> createState() => _TenantDevicesPageState();
}

class _TenantDevicesPageState extends State<TenantDevicesPage> {
  late Future<TenantElectricityMeter?> _meterFuture;

  @override
  void initState() {
    super.initState();
    _meterFuture = TenantElectricityService.fetchActiveMeter();
  }

  Future<void> _refresh() async {
    final future = TenantElectricityService.fetchActiveMeter();
    setState(() => _meterFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: TenantScreenTitle(title: 'My Electricity Meter'),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverToBoxAdapter(
              child: FutureBuilder<TenantElectricityMeter?>(
                future: _meterFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _LoadingState();
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(onRetry: _refresh);
                  }

                  final meter = snapshot.data;
                  if (meter == null) {
                    return const _NoMeterState();
                  }

                  return StreamBuilder<List<TenantElectricityReading>>(
                    stream: TenantElectricityService.watchAcceptedReadings(
                      meter.deviceId,
                    ),
                    builder: (context, readingSnapshot) {
                      final readings = readingSnapshot.data ?? const [];
                      final latest = readings.isEmpty ? null : readings.last;
                      final liveState = _meterLiveState(meter, latest);

                      return Column(
                        children: [
                          _DeviceSummaryCard(
                            deviceCount: 1,
                            statusText: switch (liveState) {
                              _MeterLiveState.live =>
                                'Validated readings are updating',
                              _MeterLiveState.delayed =>
                                'The latest reading is delayed',
                              _MeterLiveState.awaiting =>
                                'Waiting for a validated reading',
                            },
                            healthy: liveState == _MeterLiveState.live,
                          ),
                          const SizedBox(height: 18),
                          _ElectricityMeterCard(
                            meter: meter,
                            latest: latest,
                            liveState: liveState,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TenantMeterDetailsPage(meter: meter),
                              ),
                            ),
                          ),
                          if (readingSnapshot.hasError) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Live updates are temporarily unavailable. Pull down to retry.',
                              style: TextStyle(
                                color: Color(0xFFD9534F),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _MeterLiveState { live, delayed, awaiting }

_MeterLiveState _meterLiveState(
  TenantElectricityMeter meter,
  TenantElectricityReading? latest,
) {
  if (latest == null) return _MeterLiveState.awaiting;
  final thresholdSeconds = meter.samplingIntervalSec * 3 > 20
      ? meter.samplingIntervalSec * 3
      : 20;
  final age = DateTime.now().toUtc().difference(
    latest.measurementTimestamp.toUtc(),
  );
  return age <= Duration(seconds: thresholdSeconds)
      ? _MeterLiveState.live
      : _MeterLiveState.delayed;
}

class _DeviceSummaryCard extends StatelessWidget {
  const _DeviceSummaryCard({
    required this.deviceCount,
    required this.statusText,
    required this.healthy,
  });

  final int deviceCount;
  final String statusText;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 19, 20, 21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.headerStart, Color(0xFF6878EC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Meter Summary',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 255, 255, 0.20),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$deviceCount Meter',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color.fromRGBO(255, 255, 255, 0.20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  healthy
                      ? Icons.wifi_tethering_rounded
                      : Icons.schedule_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ElectricityMeterCard extends StatelessWidget {
  const _ElectricityMeterCard({
    required this.meter,
    required this.latest,
    required this.liveState,
    required this.onTap,
  });

  final TenantElectricityMeter meter;
  final TenantElectricityReading? latest;
  final _MeterLiveState liveState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (liveState) {
      _MeterLiveState.live => AppColors.success,
      _MeterLiveState.delayed => const Color(0xFFE8953E),
      _MeterLiveState.awaiting => AppColors.body,
    };
    final statusLabel = switch (liveState) {
      _MeterLiveState.live => 'Live',
      _MeterLiveState.delayed => 'Delayed',
      _MeterLiveState.awaiting => 'Awaiting data',
    };

    return TenantCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 21),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.headerEnd, AppColors.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(
                      Icons.electric_meter_outlined,
                      color: Colors.white,
                      size: 31,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          meter.unitLabel,
                          style: const TextStyle(
                            color: AppColors.heading,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${meter.model} · ${meter.deviceIdentifier}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF98A0AF),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TenantStatusPill(
                          label: statusLabel,
                          foregroundColor: statusColor,
                          backgroundColor: statusColor.withAlpha(24),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFA6AEBC),
                    size: 27,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFBF8),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Column(
                  children: [
                    _MeterSummaryLine(
                      label: 'Current power',
                      value: latest?.powerW == null
                          ? '—'
                          : '${latest!.powerW!.toStringAsFixed(0)} W',
                    ),
                    const SizedBox(height: 10),
                    _MeterSummaryLine(
                      label: 'Cumulative energy',
                      value: latest == null
                          ? '—'
                          : '${latest!.cumulativeEnergyKwh.toStringAsFixed(3)} kWh',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeterSummaryLine extends StatelessWidget {
  const _MeterSummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.body, fontSize: 14),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.headerEnd,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 260,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return TenantCard(
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFD9534F)),
          const SizedBox(height: 10),
          const Text('Electricity meter data could not be loaded.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _NoMeterState extends StatelessWidget {
  const _NoMeterState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _DeviceSummaryCard(
          deviceCount: 0,
          statusText: 'No active meter is available',
          healthy: false,
        ),
        const SizedBox(height: 18),
        TenantCard(
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.electric_meter_outlined, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'An administrator must register, validate, and activate the electricity meter assigned to your rental unit.',
                  style: TextStyle(
                    color: AppColors.body,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
