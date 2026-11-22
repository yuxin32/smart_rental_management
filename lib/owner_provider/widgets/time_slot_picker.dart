import 'dart:math' as math;

import 'package:flutter/material.dart';

int timeOfDayMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

String timeSlotLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

int? parseTimeSlot(String? value) {
  final match = RegExp(r'^(\d{2}):([0-5]\d)(?::[0-5]\d(?:\.\d+)?)?$')
      .firstMatch(value ?? '');
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  return hour < 24 ? hour * 60 + int.parse(match.group(2)!) : null;
}

/// Candidate times, not a reservation or an assertion of provider availability.
/// Exact existing values and range boundaries are retained without rounding.
List<int> timeSlotCandidates({
  required int firstMinute,
  required int lastMinute,
  int? initialMinute,
  int step = 30,
}) {
  assert(step > 0);
  final first = math.max(0, firstMinute);
  final last = math.min(1440, lastMinute);
  if (last < first) return const [];
  final result = <int>{first, last};
  for (var minute = ((first + step - 1) ~/ step) * step;
      minute <= last;
      minute += step) {
    result.add(minute);
  }
  if (initialMinute != null &&
      initialMinute >= first &&
      initialMinute <= last) {
    result.add(initialMinute);
  }
  return result.toList()..sort();
}

Future<TimeOfDay?> showTimeSlotPicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String title = 'Choose time',
  String description = 'All times are in Malaysia time (MYT, UTC+8).',
  int firstMinute = 0,
  int lastMinute = 1439,
}) async {
  final minute = await showMinuteTimeSlotPicker(
    context: context,
    initialMinute: timeOfDayMinutes(initialTime),
    title: title,
    description: description,
    firstMinute: firstMinute,
    lastMinute: math.min(lastMinute, 1439),
  );
  return minute == null
      ? null
      : TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
}

/// The local availability model also supports an explicit 24:00 end boundary.
/// Connected PostgreSQL time fields continue to stop at 23:59.
Future<int?> showMinuteTimeSlotPicker({
  required BuildContext context,
  required int initialMinute,
  required String title,
  String description = 'All times are in Malaysia time (MYT, UTC+8).',
  int firstMinute = 0,
  int lastMinute = 1439,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => TimeSlotPicker(
      title: title,
      description: description,
      initialMinute: initialMinute,
      firstMinute: firstMinute,
      lastMinute: lastMinute,
    ),
  );
}

class TimeSlotPicker extends StatefulWidget {
  const TimeSlotPicker({
    super.key,
    required this.title,
    required this.initialMinute,
    this.description = 'All times are in Malaysia time (MYT, UTC+8).',
    this.firstMinute = 0,
    this.lastMinute = 1439,
  });

  final String title;
  final String description;
  final int initialMinute;
  final int firstMinute;
  final int lastMinute;

  @override
  State<TimeSlotPicker> createState() => _TimeSlotPickerState();
}

class _TimeSlotPickerState extends State<TimeSlotPicker> {
  static const _parts = ['Morning', 'Afternoon', 'Evening', 'Early hours'];
  static const _starts = [360, 720, 1080, 0];
  late int _part;
  int? _exactHour;
  final _scroll = ScrollController();

  int _partOf(int minute) => minute >= 1080
      ? 2
      : minute >= 720
          ? 1
          : minute >= 360
              ? 0
              : 3;

  @override
  void initState() {
    super.initState();
    final choices = _candidates;
    final initial = choices.contains(widget.initialMinute)
        ? widget.initialMinute
        : choices.isEmpty
            ? 540
            : choices.first;
    _part = _partOf(initial);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<int> get _candidates => timeSlotCandidates(
        firstMinute: widget.firstMinute,
        lastMinute: widget.lastMinute,
        initialMinute: widget.initialMinute,
      );

  List<int> get _hours => [
        for (var hour = _starts[_part] ~/ 60;
            hour < _starts[_part] ~/ 60 + 6;
            hour++)
          if (hour * 60 <= widget.lastMinute &&
              hour * 60 + 59 >= widget.firstMinute)
            hour,
      ];

  void _resetScroll() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final candidates = _candidates;
    final exact = _exactHour;
    final times = exact == null
        ? candidates.where((minute) => _partOf(minute) == _part).toList()
        : [
            for (var minute = exact * 60; minute < exact * 60 + 60; minute++)
              if (minute >= widget.firstMinute && minute <= widget.lastMinute)
                minute,
          ];
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: math.min(680, MediaQuery.sizeOf(context).height * .9)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child:
                          Text(widget.title, style: theme.textTheme.titleLarge),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close time selection',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ]),
                const SizedBox(height: 4),
                Flexible(
                    child: SingleChildScrollView(
                        controller: _scroll,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(widget.description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant)),
                              const SizedBox(height: 12),
                              if (candidates.isNotEmpty)
                                Wrap(spacing: 8, runSpacing: 4, children: [
                                  for (var part = 0;
                                      part < _parts.length;
                                      part++)
                                    if (candidates.any(
                                        (minute) => _partOf(minute) == part))
                                      ChoiceChip(
                                        key: ValueKey('time-part-$part'),
                                        labelStyle: theme.textTheme.labelLarge
                                            ?.copyWith(color: colors.onSurface),
                                        label: Text(_parts[part]),
                                        selected: _part == part,
                                        onSelected: (_) {
                                          setState(() {
                                            _part = part;
                                            _exactHour = null;
                                          });
                                          _resetScroll();
                                        },
                                      ),
                                ]),
                              if (exact != null) ...[
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, runSpacing: 4, children: [
                                  for (final hour in _hours)
                                    ChoiceChip(
                                      key: ValueKey('time-hour-$hour'),
                                      labelStyle: theme.textTheme.labelLarge
                                          ?.copyWith(color: colors.onSurface),
                                      label: Text(
                                          '${timeSlotLabel(hour * 60)}–${timeSlotLabel(hour * 60 + 59)}'),
                                      selected: exact == hour,
                                      onSelected: (_) {
                                        setState(() => _exactHour = hour);
                                        _resetScroll();
                                      },
                                    ),
                                ]),
                              ],
                              const SizedBox(height: 12),
                              times.isEmpty
                                  ? const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 32),
                                      child: Text(
                                          'No times fit this range. Choose another date or time range.'),
                                    )
                                  : LayoutBuilder(
                                      builder: (context, constraints) {
                                      final scaledFont =
                                          MediaQuery.textScalerOf(context)
                                              .scale(16);
                                      final width =
                                          math.max(96.0, scaledFont * 3.4 + 32);
                                      final columns = math.max(
                                          1,
                                          (constraints.maxWidth / width)
                                              .floor());
                                      final tileWidth = (constraints.maxWidth -
                                              (columns - 1) * 8) /
                                          columns;
                                      return Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (final minute in times)
                                              SizedBox(
                                                width: tileWidth,
                                                child: Semantics(
                                                  selected: minute ==
                                                      widget.initialMinute,
                                                  child: OutlinedButton(
                                                    key: ValueKey(
                                                        'time-slot-$minute'),
                                                    style: OutlinedButton
                                                        .styleFrom(
                                                      minimumSize:
                                                          const Size(0, 48),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 12,
                                                          horizontal: 8),
                                                      backgroundColor: minute ==
                                                              widget
                                                                  .initialMinute
                                                          ? colors.primary
                                                          : null,
                                                      foregroundColor: minute ==
                                                              widget
                                                                  .initialMinute
                                                          ? colors.onPrimary
                                                          : colors.onSurface,
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.of(context)
                                                            .pop(minute),
                                                    child: Text(
                                                        timeSlotLabel(minute)),
                                                  ),
                                                ),
                                              ),
                                          ]);
                                    }),
                            ]))),
                if (candidates.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('time-slot-precision'),
                      icon: Icon(
                          exact == null ? Icons.more_time : Icons.grid_view),
                      label:
                          Text(exact == null ? 'More times' : 'Common times'),
                      onPressed: () {
                        setState(() {
                          final hours = _hours;
                          _exactHour = exact != null || hours.isEmpty
                              ? null
                              : hours.contains(widget.initialMinute ~/ 60)
                                  ? widget.initialMinute ~/ 60
                                  : hours.first;
                        });
                        _resetScroll();
                      },
                    ),
                  ),
              ]),
        ),
      ),
    );
  }
}
