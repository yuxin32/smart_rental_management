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
  final _expandedDays = <int>{};
  ProviderWeeklyState? _override;
  bool _busy = false, _needsCheck = false, _error = false;
  bool _sheetOpen = false;
  VoidCallback? _refreshSheet;
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
        widget.data.weeklyState != null) {
      _override = widget.data.weeklyState;
    }
    if (_sheetOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshSheet?.call();
      });
    }
  }

  void _working(bool value) {
    if (mounted) setState(() => _busy = value);
    _refreshSheet?.call();
    widget.onBusyChanged(value);
  }

  void _message(String message, {bool error = false}) {
    if (mounted) {
      setState(() {
        _notice = message;
        _error = error;
      });
    }
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
        'Remove')) {
      return;
    }
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
        'Set not working')) {
      return;
    }
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

  Future<void> _openDay(int day) async {
    final state = await _check();
    if (!mounted || state == null) return;
    var sheetBusy = false;
    setState(() => _sheetOpen = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, updateSheet) {
            _refreshSheet = () {
              if (context.mounted) updateSheet(() {});
            };
            Future<void> run(Future<void> Function() action) async {
              if (sheetBusy) return;
              updateSheet(() => sheetBusy = true);
              try {
                await action();
              } finally {
                if (context.mounted) updateSheet(() => sheetBusy = false);
              }
            }

            return WorkingDaySheet(
              day: day,
              state: _state!,
              enabled: _enabled && !sheetBusy,
              busy: _busy,
              notice: _buildNotice(
                  onCheck: () => run(() async {
                        await _check(verification: true);
                      }),
                  busy: sheetBusy),
              onEdit: (slotId) => run(() => _edit(day, slotId: slotId)),
              onRemove: (slotId) => run(() => _remove(day, slotId)),
              onToggle: (work) => run(() => _toggle(day, work)),
              onCopy: () => run(() => _copy(day)),
            );
          },
        ),
      );
    } finally {
      _refreshSheet = null;
      if (mounted) setState(() => _sheetOpen = false);
    }
  }

  Widget _buildNotice({VoidCallback? onCheck, bool busy = false}) {
    if (_notice == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _error ? scheme.errorContainer : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
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
                    onPressed: _busy || busy || !widget.enabled
                        ? null
                        : onCheck ?? () => _check(verification: true),
                    child: const Text('Check saved hours')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayRow(int day) {
    final slots = _slots.where((slot) => slot.weekday == day).toList()
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    final expanded = _expandedDays.contains(day);
    final jobs = _state?.countFor(day) ?? 0;
    final theme = Theme.of(context);
    final label = Text(providerWeekdays[day - 1].substring(0, 3),
        semanticsLabel: providerWeekdays[day - 1],
        style:
            theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600));
    final edit = IconButton(
      key: ValueKey('edit-working-day-$day'),
      tooltip: 'Edit ${providerWeekdays[day - 1]} hours',
      onPressed: _enabled ? () => _openDay(day) : null,
      icon: const Icon(Icons.edit_outlined, size: 19),
    );
    final times = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (slots.isEmpty)
          Text('Not working',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        for (final slot in expanded ? slots : slots.take(2))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(workingRangeLabel(
                ProviderWorkingRange(slot.startMinute, slot.endMinute))),
          ),
        if (slots.length > 2)
          TextButton(
            key: ValueKey('expand-working-day-$day'),
            onPressed: () => setState(() {
              if (expanded) {
                _expandedDays.remove(day);
              } else {
                _expandedDays.add(day);
              }
            }),
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                alignment: Alignment.centerLeft),
            child: Text(expanded ? 'Show less' : '+${slots.length - 2} more',
                semanticsLabel: expanded
                    ? 'Show fewer ${providerWeekdays[day - 1]} working hours'
                    : 'Show ${slots.length - 2} more ${providerWeekdays[day - 1]} working hours'),
          ),
        if (jobs > 0)
          Text('$jobs confirmed ${jobs == 1 ? 'job' : 'jobs'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
    return Column(
      key: ValueKey('working-weekday-$day'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: LayoutBuilder(builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (constraints.maxWidth < 280 * scale) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Expanded(child: label), edit]),
                  times,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 56 * scale,
                    child: Padding(
                        padding: const EdgeInsets.only(top: 4), child: label)),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.only(top: 2), child: times)),
                edit,
              ],
            );
          }),
        ),
        const Divider(height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Repeats weekly · MYT'),
          const SizedBox(height: 8),
          if (_busy && !_sheetOpen)
            const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator()),
          if (!_sheetOpen) _buildNotice(),
          for (var day = 1; day <= 7; day++) _dayRow(day),
        ],
      );
}
