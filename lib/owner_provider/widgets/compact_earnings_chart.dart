import 'dart:math' as math;
import 'package:flutter/material.dart';

class EarningsChartPoint {
  const EarningsChartPoint(this.label, this.range, this.amount, this.jobs);
  final String label, range;
  final double amount;
  final int jobs;
}

/// Zero-filled reporting buckets, drawn on a shared scale. Selection changes
/// only a bar's colour, never paints a background stripe or invents a value.
class CompactEarningsChart extends StatefulWidget {
  const CompactEarningsChart({super.key, required this.points, this.onDetails});
  final List<EarningsChartPoint> points;
  final ValueChanged<int>? onDetails;
  @override
  State<CompactEarningsChart> createState() => _CompactEarningsChartState();
}

class _CompactEarningsChartState extends State<CompactEarningsChart> {
  int? selected;
  @override
  void didUpdateWidget(CompactEarningsChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points.length != widget.points.length ||
        oldWidget.points.asMap().entries.any((e) =>
            e.value.range != widget.points[e.key].range ||
            e.value.amount != widget.points[e.key].amount ||
            e.value.jobs != widget.points[e.key].jobs)) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.0);
    final axisWidth = 42.0 * scale;
    final plotHeight = 176.0 + (scale - 1) * 30;
    final barHeight = plotHeight - 12 - 18 * scale;
    if (points.isEmpty) return const Text('No reporting periods yet.');
    final colors = Theme.of(context).colorScheme;
    final maximum = points.fold<double>(0, (v, p) => math.max(v, p.amount));
    final rawStep = maximum == 0 ? 1.0 : maximum / 3;
    final power =
        math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
    final step = (rawStep / power).ceil() * power;
    final ceiling = step * 3;
    final point = selected == null ? null : points[selected!];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('RM', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: axisWidth,
              height: plotHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 3; i >= 0; i--)
                    Text(_amount(step * i),
                        style: Theme.of(context).textTheme.labelSmall)
                ],
              )),
          Expanded(
              child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(constraints.maxWidth - axisWidth,
                  points.length * 62.0 * scale),
              child: Column(children: [
                SizedBox(
                    height: plotHeight,
                    child: Stack(children: [
                      Positioned.fill(
                          child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                            4,
                            (_) => Divider(
                                height: 1,
                                thickness: 1,
                                color: colors.outlineVariant)),
                      )),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < points.length; i++)
                              Expanded(
                                  child: Semantics(
                                button: true,
                                selected: selected == i,
                                label:
                                    '${points[i].range}, RM ${points[i].amount.toStringAsFixed(2)}, ${points[i].jobs} completed jobs',
                                child: Tooltip(
                                    key: ValueKey(
                                        'earnings-bucket-${points[i].label}'),
                                    message:
                                        '${points[i].range}\n${points[i].jobs} completed jobs · RM ${points[i].amount.toStringAsFixed(2)}',
                                    child: GestureDetector(
                                      key: ValueKey('earnings-bar-$i'),
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => setState(() => selected = i),
                                      child: SizedBox(
                                          height: plotHeight,
                                          child: Align(
                                            alignment: Alignment.bottomCenter,
                                            child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                      _amount(points[i].amount),
                                                      maxLines: 1,
                                                      style: const TextStyle(
                                                          fontSize: 11)),
                                                  const SizedBox(height: 4),
                                                  FractionallySizedBox(
                                                      widthFactor: .68,
                                                      child: Container(
                                                        key: ValueKey(
                                                            'earnings-bar-fill-$i'),
                                                        height:
                                                            points[i].amount /
                                                                ceiling *
                                                                barHeight,
                                                        decoration: BoxDecoration(
                                                            color: selected == i
                                                                ? colors.primary
                                                                : colors.primary
                                                                    .withOpacity(
                                                                        .48),
                                                            borderRadius:
                                                                const BorderRadius
                                                                    .vertical(
                                                                    top: Radius
                                                                        .circular(
                                                                            3))),
                                                      )),
                                                ]),
                                          )),
                                    )),
                              )),
                          ]),
                    ])),
                const SizedBox(height: 8),
                Row(children: [
                  for (final p in points)
                    Expanded(
                        child: Text(p.label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall))
                ]),
              ]),
            ),
          )),
        ]);
      }),
      const SizedBox(height: 16),
      if (point == null)
        Text('Tap a bar for its amount and completed jobs.',
            style: Theme.of(context).textTheme.bodySmall)
      else ...[
        Text(point.range, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(
            'RM ${point.amount.toStringAsFixed(2)} · ${point.jobs} completed ${point.jobs == 1 ? 'job' : 'jobs'}'),
        if (widget.onDetails != null && point.jobs > 0)
          TextButton(
              onPressed: () => widget.onDetails!(selected!),
              child: const Text('View jobs')),
      ],
    ]);
  }

  String _amount(double n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(1)}m'
      : n >= 10000
          ? '${(n / 1000).toStringAsFixed(1)}k'
          : n == n.roundToDouble()
              ? n.toStringAsFixed(0)
              : n.toStringAsFixed(1);
}
