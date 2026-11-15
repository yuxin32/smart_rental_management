import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/tenant_electricity_service.dart';
import '../widgets/tenant_ui.dart';

class TenantMeterDetailsPage extends StatelessWidget {
  const TenantMeterDetailsPage({required this.meter, super.key});

  final TenantElectricityMeter meter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const TenantBackAppBar(title: 'Electricity Consumption'),
      body: StreamBuilder<List<TenantElectricityReading>>(
        stream: TenantElectricityService.watchAcceptedReadings(meter.deviceId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && !snapshot.hasData) {
            return const _DetailsErrorState();
          }

          final readings = snapshot.data ?? const [];
          final latest = readings.isEmpty ? null : readings.last;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: [
              _MeterHeaderCard(meter: meter, latest: latest),
              const SizedBox(height: 18),
              _LiveReadingCard(readings: readings),
            ],
          );
        },
      ),
    );
  }
}

class _MeterHeaderCard extends StatelessWidget {
  const _MeterHeaderCard({required this.meter, required this.latest});

  final TenantElectricityMeter meter;
  final TenantElectricityReading? latest;

  @override
  Widget build(BuildContext context) {
    final live = _isLive(meter, latest);
    return TenantCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meter.unitLabel,
                        style: const TextStyle(
                          color: AppColors.heading,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${meter.model} · ${meter.deviceIdentifier}',
                        style: const TextStyle(
                          color: Color(0xFF98A0AF),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                TenantStatusPill(
                  label: latest == null
                      ? 'Awaiting data'
                      : live
                      ? 'Live'
                      : 'Delayed',
                  foregroundColor: latest == null
                      ? AppColors.body
                      : live
                      ? AppColors.success
                      : const Color(0xFFE8953E),
                  backgroundColor: latest == null
                      ? const Color(0xFFF0F1F4)
                      : live
                      ? const Color(0xFFE0F7E7)
                      : const Color(0xFFFFF0DA),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFECEFF3)),
          IntrinsicHeight(
            child: Row(
              children: [
                const Expanded(
                  child: _MeterInfoCell(
                    label: 'Data status',
                    value: 'Validated',
                    valueColor: AppColors.success,
                  ),
                ),
                const VerticalDivider(width: 1, color: Color(0xFFECEFF3)),
                Expanded(
                  child: _MeterInfoCell(
                    label: 'Last update',
                    value: latest == null
                        ? '—'
                        : _formatTime(latest!.measurementTimestamp),
                    valueColor: AppColors.heading,
                  ),
                ),
                const VerticalDivider(width: 1, color: Color(0xFFECEFF3)),
                Expanded(
                  child: _MeterInfoCell(
                    label: 'Current power',
                    value: latest?.powerW == null
                        ? '—'
                        : '${latest!.powerW!.toStringAsFixed(0)} W',
                    valueColor: AppColors.primary,
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

class _LiveReadingCard extends StatelessWidget {
  const _LiveReadingCard({required this.readings});

  final List<TenantElectricityReading> readings;

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return TenantCard(
        child: const Column(
          children: [
            Icon(
              Icons.hourglass_empty_rounded,
              color: AppColors.primary,
              size: 32,
            ),
            SizedBox(height: 12),
            Text(
              'Waiting for the first validated reading',
              style: TextStyle(
                color: AppColors.heading,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 7),
            Text(
              'Rejected or flagged records are not displayed to tenants or used as valid consumption.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.body,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    final latest = readings.last;
    final visibleReadings = readings.length > 30
        ? readings.sublist(readings.length - 30)
        : readings;
    final powerValues = visibleReadings
        .where((reading) => reading.powerW != null)
        .map((reading) => reading.powerW!)
        .toList();
    final usage = readings.length < 2
        ? latest.intervalEnergyKwh ?? 0
        : (latest.cumulativeEnergyKwh - readings.first.cumulativeEnergyKwh)
              .clamp(0, double.infinity)
              .toDouble();

    return TenantCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Live Power Graph',
                  style: TextStyle(
                    color: AppColors.heading,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TenantStatusPill(
                label: 'Accepted readings only',
                foregroundColor: AppColors.success,
                backgroundColor: Color(0xFFE0F7E7),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Latest ${visibleReadings.length} validated records · power in watts (W)',
            style: const TextStyle(color: AppColors.body, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ReadingValue(
                  label: 'Current power',
                  value: latest.powerW == null
                      ? '—'
                      : '${latest.powerW!.toStringAsFixed(0)} W',
                ),
              ),
              Expanded(
                child: _ReadingValue(
                  label: 'Cumulative energy',
                  value: '${latest.cumulativeEnergyKwh.toStringAsFixed(3)} kWh',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ReadingValue(
                  label: 'Usage in this window',
                  value: '${usage.toStringAsFixed(4)} kWh',
                ),
              ),
              Expanded(
                child: _ReadingValue(
                  label: 'Latest interval',
                  value: latest.intervalEnergyKwh == null
                      ? '—'
                      : '${latest.intervalEnergyKwh!.toStringAsFixed(4)} kWh',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (powerValues.isEmpty)
            const SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'No active-power values are available for this period.',
                  style: TextStyle(color: AppColors.body),
                ),
              ),
            )
          else
            SizedBox(
              height: 240,
              width: double.infinity,
              child: CustomPaint(
                painter: _UsageChartPainter(values: powerValues),
              ),
            ),
          if (visibleReadings.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(visibleReadings.first.measurementTimestamp),
                  style: const TextStyle(color: AppColors.body, fontSize: 11),
                ),
                Text(
                  _formatTime(visibleReadings.last.measurementTimestamp),
                  style: const TextStyle(color: AppColors.body, fontSize: 11),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5FF),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              'Latest electrical values: ${_measurement(latest.voltageV, 'V')} · '
              '${_measurement(latest.currentA, 'A')} · '
              'PF ${latest.powerFactor?.toStringAsFixed(2) ?? '—'} · '
              '${_measurement(latest.frequencyHz, 'Hz')}',
              style: const TextStyle(
                color: AppColors.body,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeterInfoCell extends StatelessWidget {
  const _MeterInfoCell({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF98A0AF), fontSize: 11),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingValue extends StatelessWidget {
  const _ReadingValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
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
      ),
    );
  }
}

class _UsageChartPainter extends CustomPainter {
  const _UsageChartPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final chartRect = Rect.fromLTWH(8, 10, size.width - 16, size.height - 25);
    final gridPaint = Paint()
      ..color = const Color(0xFFE3E8F0)
      ..strokeWidth = 1;

    for (var index = 0; index < 5; index++) {
      final y = chartRect.top + (chartRect.height / 4) * index;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    var minimum = values.first;
    var maximum = values.first;
    for (final value in values.skip(1)) {
      if (value < minimum) minimum = value;
      if (value > maximum) maximum = value;
    }
    final range = maximum == minimum ? 1.0 : maximum - minimum;
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? chartRect.center.dx
          : chartRect.left + chartRect.width * index / (values.length - 1);
      final normalized = (values[index] - minimum) / range;
      final y = chartRect.bottom - chartRect.height * normalized;
      points.add(Offset(x, y));
    }

    if (points.length > 1) {
      final fillPath = Path()..moveTo(points.first.dx, chartRect.bottom);
      for (final point in points) {
        fillPath.lineTo(point.dx, point.dy);
      }
      fillPath
        ..lineTo(points.last.dx, chartRect.bottom)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            colors: [
              AppColors.primary.withAlpha(58),
              AppColors.primary.withAlpha(4),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(chartRect),
      );

      final linePath = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        linePath.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        linePath,
        Paint()
          ..color = AppColors.primary
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    canvas.drawCircle(points.last, 4, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(covariant _UsageChartPainter oldDelegate) => true;
}

class _DetailsErrorState extends StatelessWidget {
  const _DetailsErrorState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Validated electricity readings could not be loaded. Please try again later.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.body),
        ),
      ),
    );
  }
}

bool _isLive(TenantElectricityMeter meter, TenantElectricityReading? latest) {
  if (latest == null) return false;
  final thresholdSeconds = meter.samplingIntervalSec * 3 > 20
      ? meter.samplingIntervalSec * 3
      : 20;
  return DateTime.now().toUtc().difference(
        latest.measurementTimestamp.toUtc(),
      ) <=
      Duration(seconds: thresholdSeconds);
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _measurement(double? value, String unit) {
  if (value == null) return '— $unit';
  return '${value.toStringAsFixed(2)} $unit';
}
