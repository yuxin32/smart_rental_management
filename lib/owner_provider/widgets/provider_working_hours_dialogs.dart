import 'package:flutter/material.dart';
import '../features/availability/domain/provider_setup.dart';
import 'time_slot_picker.dart';

const providerWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];
String workingTime(int minute) =>
    minute == 1440 ? '24:00' : ProviderSlotRules.databaseTime(minute);
String workingRangeLabel(ProviderWorkingRange range) =>
    '${workingTime(range.start)} – ${workingTime(range.end)}';

class WorkingRangeDialog extends StatefulWidget {
  const WorkingRangeDialog(
      {super.key,
      required this.state,
      required this.day,
      required this.initial,
      this.slotId});
  final ProviderWeeklyState state;
  final int day;
  final ProviderWorkingRange initial;
  final String? slotId;
  @override
  State<WorkingRangeDialog> createState() => _WorkingRangeDialogState();
}

class _WorkingRangeDialogState extends State<WorkingRangeDialog> {
  late ProviderWorkingRange _range = widget.initial;
  List<ProviderWorkingRange> _with(ProviderWorkingRange range) => [
        for (final slot in widget.state.slots)
          if (slot.weekday == widget.day && slot.id != widget.slotId)
            ProviderWorkingRange(slot.startMinute, slot.endMinute),
        range,
      ];
  ProviderWorkingRange _candidate(bool start, int minute) => start
      ? ProviderWorkingRange(
          minute, _range.end - minute < 120 ? minute + 120 : _range.end)
      : ProviderWorkingRange(_range.start, minute);
  Future<void> _pick(bool start) async {
    final minute = await showMinuteTimeSlotPicker(
      context: context,
      initialMinute: start ? _range.start : _range.end,
      title: start ? 'Working slot starts' : 'Working slot ends',
      description:
          'Minimum 2 hours. Times that overlap or affect confirmed jobs are disabled. MYT.',
      firstMinute: start ? 0 : _range.start + 120,
      lastMinute: start ? 1319 : 1439,
      isSelectable: (value) =>
          widget.state
              .validateDay(widget.day, _with(_candidate(start, value))) ==
          null,
    );
    if (!mounted || minute == null) return;
    setState(() => _range = _candidate(start, minute));
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.state.validateDay(widget.day, _with(_range));
    final required =
        widget.state.required.where((item) => item.weekday == widget.day);
    Widget field(bool start) => OutlinedButton(
        key: ValueKey(start ? 'working-start' : 'working-end'),
        onPressed: () => _pick(start),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14)),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(start ? 'Starts' : 'Ends',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(workingTime(start ? _range.start : _range.end),
                    style: Theme.of(context).textTheme.titleLarge)
              ],
            )));
    return AlertDialog(
      scrollable: true,
      title: Text(
          '${widget.slotId == null ? 'Add' : 'Edit'} ${providerWeekdays[widget.day - 1]} hours'),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Repeats weekly · Malaysia time (MYT)'),
            const SizedBox(height: 16),
            MediaQuery.sizeOf(context).width < 380 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.4
                ? Column(children: [
                    field(true),
                    const SizedBox(height: 10),
                    field(false)
                  ])
                : Row(children: [
                    Expanded(child: field(true)),
                    const SizedBox(width: 10),
                    Expanded(child: field(false))
                  ]),
            const SizedBox(height: 12),
            const Text('Each time slot must be at least 2 hours.'),
            if (required.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                  'Confirmed jobs need: ${required.map((item) => '${workingTime(item.start)}–${workingTime(item.end)}').join(', ')}.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed:
                error == null ? () => Navigator.pop(context, _range) : null,
            child: const Text('Save hours')),
      ],
    );
  }
}

class CopyWorkingHoursDialog extends StatefulWidget {
  const CopyWorkingHoursDialog(
      {super.key,
      required this.sourceDay,
      required this.state,
      required this.ranges});
  final int sourceDay;
  final ProviderWeeklyState state;
  final List<ProviderWorkingRange> ranges;
  @override
  State<CopyWorkingHoursDialog> createState() => _CopyWorkingHoursDialogState();
}

class _CopyWorkingHoursDialogState extends State<CopyWorkingHoursDialog> {
  final _selected = <int>{};
  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text('Copy ${providerWeekdays[widget.sourceDay - 1]} hours'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.ranges.map(workingRangeLabel).join('\n')),
              const SizedBox(height: 10),
              const Text(
                  'Existing hours on the selected days will be replaced. Other days stay unchanged.'),
              const SizedBox(height: 8),
              for (var day = 1; day <= 7; day++)
                Builder(builder: (context) {
                  final source = day == widget.sourceDay;
                  final error = widget.state.validateDay(day, widget.ranges);
                  final current = widget.state.rangesFor(day);
                  return CheckboxListTile(
                    key: ValueKey('copy-weekday-$day'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(providerWeekdays[day - 1]),
                    subtitle: Text(source
                        ? 'Current day'
                        : error ??
                            (current.isEmpty
                                ? 'Not working'
                                : current.map(workingRangeLabel).join(' / '))),
                    value: _selected.contains(day),
                    onChanged: source || error != null
                        ? null
                        : (checked) => setState(() {
                              if (checked == true)
                                _selected.add(day);
                              else
                                _selected.remove(day);
                            }),
                  );
                }),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, Set<int>.of(_selected)),
              child: Text(_selected.isEmpty
                  ? 'Copy hours'
                  : 'Copy to ${_selected.length} days')),
        ],
      );
}
