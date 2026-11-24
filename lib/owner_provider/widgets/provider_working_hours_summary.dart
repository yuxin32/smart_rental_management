import 'package:flutter/material.dart';

import '../features/availability/domain/provider_setup.dart';
import '../theme/app_theme.dart';

/// Read-only weekly hours. These are working slots, not bookable gaps.
class ProviderWorkingHoursSummary extends StatelessWidget {
  const ProviderWorkingHoursSummary({super.key, required this.slots});

  final List<Map<String, dynamic>> slots;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    if (slots.isEmpty) {
      return Text('No working slots saved yet.',
          style: TextStyle(color: sem.textSecondary));
    }
    return Column(
      children: List.generate(7, (index) {
        final daySlots = slots
            .where((slot) => slot['weekday'] == index + 1)
            .toList()
          ..sort((a, b) =>
              ProviderSlotRules.parseDatabaseTime(a['start_time'] as String)
                  .compareTo(ProviderSlotRules.parseDatabaseTime(
                      b['start_time'] as String)));
        return _WorkingDaySummary(
          key: ValueKey(index + 1),
          day: _days[index],
          slots: daySlots,
        );
      }),
    );
  }
}

class _WorkingDaySummary extends StatefulWidget {
  const _WorkingDaySummary({super.key, required this.day, required this.slots});

  final String day;
  final List<Map<String, dynamic>> slots;

  @override
  State<_WorkingDaySummary> createState() => _WorkingDaySummaryState();
}

class _WorkingDaySummaryState extends State<_WorkingDaySummary> {
  bool _expanded = false;

  String _time(Object? value) => ProviderSlotRules.databaseTime(
      ProviderSlotRules.parseDatabaseTime(value as String));

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final visibleSlots = _expanded ? widget.slots : widget.slots.take(2);
    final hiddenCount = widget.slots.length - 2;
    final day = Text(widget.day,
        style: TextStyle(color: sem.textPrimary, fontWeight: FontWeight.w600));
    final times = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.slots.isEmpty)
          Text('Not working', style: TextStyle(color: sem.textSecondary)),
        for (final slot in visibleSlots)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
                '${_time(slot['start_time'])} – ${_time(slot['end_time'])}',
                style: TextStyle(
                    color: sem.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        if (hiddenCount > 0)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                alignment: Alignment.centerLeft),
            child: Text(_expanded ? 'Show less' : '+$hiddenCount more',
                semanticsLabel: _expanded
                    ? 'Show fewer ${widget.day} working hours'
                    : 'Show $hiddenCount more ${widget.day} working hours'),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: LayoutBuilder(builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            // Stack within the same day when enlarged text needs more room.
            if (constraints.maxWidth < 250 * scale) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [day, const SizedBox(height: 8), times],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 110 * scale, child: day),
                Expanded(child: times),
              ],
            );
          }),
        ),
        Divider(height: 1, color: sem.border),
      ],
    );
  }
}
