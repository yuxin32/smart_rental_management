import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/availability/domain/provider_setup.dart';
import '../services/backend/safe_diagnostics.dart';
import 'provider_working_hours_dialogs.dart';

typedef SaveProviderWeek = Future<ProviderWeeklyState> Function(
    Map<int, List<ProviderWorkingRange>>, ProviderWeeklyState);

class ProviderWeeklyHoursEditor extends StatefulWidget {
  const ProviderWeeklyHoursEditor(
      {super.key,
      required this.data,
      required this.enabled,
      required this.loadFresh,
      required this.save,
      required this.onSaved,
      required this.onBusyChanged});
  final ProviderSetupData data;
  final bool enabled;
  final Future<ProviderWeeklyState> Function() loadFresh;
  final SaveProviderWeek save;
  final VoidCallback onSaved;
  final ValueChanged<bool> onBusyChanged;
  @override
  State<ProviderWeeklyHoursEditor> createState() =>
      _ProviderWeeklyHoursEditorState();
}

class _ProviderWeeklyHoursEditorState extends State<ProviderWeeklyHoursEditor> {
  int _day = 1;
  ProviderWeeklyState? _override;
  bool _busy = false, _needsCheck = false, _error = false;
  String? _notice;
  Map<int, List<ProviderWorkingRange>>? _pending;
  ProviderWeeklyState? get _state => _override ?? widget.data.weeklyState;
  List<ProviderWeeklySlotItem> get _slots => _state?.slots ?? widget.data.slots;
  bool get _enabled => widget.enabled && !_busy && !_needsCheck;

  @override
  void didUpdateWidget(covariant ProviderWeeklyHoursEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy &&
        oldWidget.data.weeklyState != widget.data.weeklyState &&
        widget.data.weeklyState != null) _override = widget.data.weeklyState;
  }

  void _working(bool value) {
    if (mounted) setState(() => _busy = value);
    widget.onBusyChanged(value);
  }

  void _message(String message, {bool error = false}) {
    if (mounted)
      setState(() {
        _notice = message;
        _error = error;
      });
  }

  Future<ProviderWeeklyState?> _check({bool verification = false}) async {
    if (!widget.enabled || _busy) return null;
    _working(true);
    try {
      final state = await widget.loadFresh();
      if (!mounted) return null;
      setState(() {
        _override = state;
        _needsCheck = false;
        _notice = null;
      });
      if (verification && _pending != null) {
        final matches = _pending!.entries.every((entry) {
          final current = state.rangesFor(entry.key);
          final desired = List<ProviderWorkingRange>.of(entry.value)
            ..sort((a, b) => a.start.compareTo(b.start));
          return current.length == desired.length &&
              List.generate(
                  current.length,
                  (i) =>
                      current[i].start == desired[i].start &&
                      current[i].end == desired[i].end).every((value) => value);
        });
        _message(matches
            ? 'Your saved hours match this change.'
            : 'Saved hours checked. Review them before making another change.');
        _pending = null;
      }
      return state;
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.providerSetupLoad, error);
      if (mounted) setState(() => _needsCheck = true);
      _message('Could not check your latest hours. Check again before editing.',
          error: true);
      return null;
    } finally {
      _working(false);
    }
  }

  Future<void> _commit(Map<int, List<ProviderWorkingRange>> changes,
      ProviderWeeklyState expected) async {
    if (!mounted || !_enabled) return;
    _pending = Map.unmodifiable({
      for (final entry in changes.entries)
        entry.key: List<ProviderWorkingRange>.unmodifiable(entry.value)
    });
    _working(true);
    try {
      final saved = await widget.save(changes, expected);
      if (!mounted) return;
      setState(() {
        _override = saved;
        _pending = null;
        _needsCheck = false;
      });
      _message(changes.length > 1
          ? 'Working hours copied to ${changes.length} days.'
          : 'Working hours saved.');
      widget.onSaved();
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.providerSetupSave, error);
      if (mounted) setState(() => _needsCheck = true);
      final conflict = error is PostgrestException &&
          const {'40001', 'PT409', '23514'}.contains(error.code);
      _message(
          conflict
              ? 'Your hours or confirmed jobs changed. Check the latest hours before editing again.'
              : 'We could not confirm this change. Check your saved hours before trying again.',
          error: true);
    } finally {
      _working(false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  scrollable: true,
                  title: Text(title),
                  content: Text(message),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(action)),
                  ])) ==
      true;

  Future<void> _edit(int day, {String? slotId}) async {
    final state = await _check();
    if (!mounted || state == null) return;
    ProviderWorkingRange? initial;
    if (slotId != null) {
      final found =
          state.slots.where((slot) => slot.weekday == day && slot.id == slotId);
      if (found.isEmpty) {
        _message('These hours changed. Select the time slot again.');
        return;
      }
      initial = ProviderWorkingRange(
          found.single.startMinute, found.single.endMinute);
    } else {
      final existing = state.rangesFor(day);
      for (final minute in [
        ...List.generate(28, (i) => 480 + i * 30),
        ...List.generate(16, (i) => i * 30)
      ]) {
        final candidate = ProviderWorkingRange(minute, minute + 120);
        if (state.validateDay(day, [...existing, candidate]) == null) {
          initial = candidate;
          break;
        }
      }
      if (initial == null) {
        _message(
            'No room for another 2-hour slot. Review the existing hours first.',
            error: true);
        return;
      }
    }
    final range = await showDialog<ProviderWorkingRange>(
        context: context,
        builder: (_) => WorkingRangeDialog(
            state: state, day: day, initial: initial!, slotId: slotId));
    if (!mounted || range == null) return;
    final ranges = [
      for (final slot in state.slots)
        if (slot.weekday == day && slot.id != slotId)
          ProviderWorkingRange(slot.startMinute, slot.endMinute),
      range,
    ];
    await _commit({day: ranges}, state);
  }

  Future<void> _remove(int day, String slotId) async {
    final state = await _check();
    if (!mounted || state == null) return;
    final ranges = [
      for (final slot in state.slots)
        if (slot.weekday == day && slot.id != slotId)
          ProviderWorkingRange(slot.startMinute, slot.endMinute)
    ];
    final error = state.validateDay(day, ranges);
    if (error != null) {
      _message(error, error: true);
      return;
    }
    if (!await _confirm(
        'Remove this time slot?',
        'The other working hours for ${providerWeekdays[day - 1]} stay unchanged.',
        'Remove')) return;
    await _commit({day: ranges}, state);
  }

  Future<void> _toggle(int day, bool work) async {
    if (work) {
      await _edit(day);
      return;
    }
    final state = await _check();
    if (!mounted || state == null) return;
    final error = state.validateDay(day, []);
    if (error != null) {
      _message(error, error: true);
      return;
    }
    if (!await _confirm(
        'Set ${providerWeekdays[day - 1]} as not working?',
        'This removes all recurring time slots for this weekday. For a single date off, use Days off below.',
        'Set not working')) return;
    await _commit({day: []}, state);
  }

  Future<void> _copy(int day) async {
    final state = await _check();
    if (!mounted || state == null) return;
    final ranges = state.rangesFor(day);
    if (ranges.isEmpty) {
      _message('Add working hours before copying them.');
      return;
    }
    final error = state.validateDay(day, ranges);
    if (error != null) {
      _message(error, error: true);
      return;
    }
    final targets = await showDialog<Set<int>>(
        context: context,
        builder: (_) => CopyWorkingHoursDialog(
            sourceDay: day, state: state, ranges: ranges));
    if (!mounted || targets == null || targets.isEmpty) return;
    await _commit({for (final target in targets) target: ranges}, state);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slots = _slots.where((slot) => slot.weekday == _day).toList()
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    final required =
        _state?.required.where((item) => item.weekday == _day).toList() ?? [];
    final jobs = _state?.countFor(_day) ?? 0;
    final dayName = Text(providerWeekdays[_day - 1],
        style: Theme.of(context).textTheme.titleMedium);
    final copyAction = TextButton.icon(
        onPressed: _enabled && slots.isNotEmpty ? () => _copy(_day) : null,
        icon: const Icon(Icons.copy_outlined, size: 16),
        label: const Text('Copy'));
    final workToggle = Row(mainAxisSize: MainAxisSize.min, children: [
      Text(slots.isEmpty ? 'Off' : 'Working',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      Tooltip(
          message: jobs > 0
              ? 'Keep working hours for confirmed jobs'
              : 'Working on ${providerWeekdays[_day - 1]}',
          child: Switch(
              value: slots.isNotEmpty,
              onChanged: !_enabled || jobs > 0
                  ? null
                  : (value) => _toggle(_day, value)))
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Repeats weekly · MYT'),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, constraints) {
        final columns = MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 4 : 7;
        final width = (constraints.maxWidth - (columns - 1) * 5) / columns;
        return Wrap(spacing: 5, runSpacing: 7, children: [
          for (var day = 1; day <= 7; day++)
            SizedBox(
                width: width,
                child: Semantics(
                    label:
                        '${providerWeekdays[day - 1]}, ${_slots.where((slot) => slot.weekday == day).length} time slots',
                    selected: day == _day,
                    child: OutlinedButton(
                      key: ValueKey('working-weekday-$day'),
                      onPressed:
                          _busy ? null : () => setState(() => _day = day),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 0),
                          backgroundColor:
                              day == _day ? scheme.primary : scheme.surface,
                          foregroundColor:
                              day == _day ? scheme.onPrimary : scheme.onSurface,
                          side: BorderSide(
                              color: day == _day
                                  ? scheme.primary
                                  : scheme.outlineVariant)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(providerWeekdays[day - 1].substring(0, 3),
                            style: const TextStyle(fontSize: 12)),
                      ]),
                    )))
        ]);
      }),
      const SizedBox(height: 16),
      if (_busy)
        const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator()),
      if (_notice != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
                liveRegion: true,
                child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: _error
                            ? scheme.errorContainer
                            : scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_notice!,
                              style: TextStyle(
                                  color: _error
                                      ? scheme.onErrorContainer
                                      : scheme.onPrimaryContainer)),
                          if (_needsCheck)
                            TextButton(
                                onPressed: _busy || !widget.enabled
                                    ? null
                                    : () => _check(verification: true),
                                child: const Text('Check saved hours')),
                        ])))),
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < 300 * scale) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                dayName,
                Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [copyAction, workToggle]),
              ]);
        }
        return Row(
            children: [Expanded(child: dayName), copyAction, workToggle]);
      }),
      Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (slots.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Not working on this weekday.')),
            for (final slot in slots)
              Builder(builder: (context) {
                final remaining = [
                  for (final other in slots)
                    if (other.id != slot.id)
                      ProviderWorkingRange(other.startMinute, other.endMinute)
                ];
                final protected = _state?.validateDay(_day, remaining) != null;
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  if (slot != slots.first) const Divider(height: 1),
                  ListTile(
                    title: Text(workingRangeLabel(ProviderWorkingRange(
                        slot.startMinute, slot.endMinute))),
                    subtitle: Text(slot.endMinute - slot.startMinute < 120
                        ? 'Under 2 hours · update this slot'
                        : '${((slot.endMinute - slot.startMinute) / 60).toStringAsFixed((slot.endMinute - slot.startMinute) % 60 == 0 ? 0 : 1)} hours'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          key: ValueKey('edit-working-slot-${slot.id}'),
                          tooltip: 'Edit time slot',
                          onPressed: _enabled
                              ? () => _edit(_day, slotId: slot.id)
                              : null,
                          icon: const Icon(Icons.edit_outlined, size: 19)),
                      IconButton(
                          tooltip: protected
                              ? 'Required by confirmed jobs'
                              : 'Remove time slot',
                          onPressed: !_enabled || protected
                              ? null
                              : () => _remove(_day, slot.id),
                          icon: Icon(
                              protected
                                  ? Icons.lock_outline
                                  : Icons.delete_outline,
                              size: 19)),
                    ]),
                  ),
                ]);
              }),
            const Divider(height: 1),
            OutlinedButton.icon(
                onPressed: _enabled ? () => _edit(_day) : null,
                icon: const Icon(Icons.add),
                label: const Text('Add time slot')),
          ])),
      if (jobs > 0)
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lock_outline, size: 16),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                      '${jobs == 1 ? '1 upcoming job' : '$jobs upcoming jobs'} · keep ' +
                          required
                              .take(3)
                              .map((item) =>
                                  '${workingTime(item.start)}–${workingTime(item.end)}')
                              .join(', ') +
                          (required.length > 3
                              ? ' and ${required.length - 3} other required times available.'
                              : ' available.'),
                      style: Theme.of(context).textTheme.bodySmall)),
            ])),
    ]);
  }
}
