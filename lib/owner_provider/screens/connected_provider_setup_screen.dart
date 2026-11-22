import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/backend/safe_diagnostics.dart';

import '../features/availability/domain/provider_setup.dart';
import '../services/backend/connected_failure_message.dart';
import '../widgets/connected_state_panel.dart';
import '../widgets/connected_action_feedback.dart';
import '../widgets/snapshot_refresh_notice.dart';
import '../services/backend/session_snapshot_cache.dart';
import '../widgets/time_slot_picker.dart';

typedef AddConnectedSlot = Future<void> Function(
  int weekday,
  String startTime,
  String endTime,
);

/// All reads and writes are delegated to the authenticated backend. No
/// sample availability or service capability is created in this screen.
class ConnectedProviderSetupScreen extends StatefulWidget {
  const ConnectedProviderSetupScreen({
    super.key,
    required this.load,
    this.initialData,
    required this.saveServices,
    required this.addSlot,
    required this.removeSlot,
    required this.addUnavailableDate,
    required this.removeUnavailableDate,
  });

  final Future<ProviderSetupData> Function() load;
  final ProviderSetupData? initialData;
  final Future<void> Function(Set<String>) saveServices;
  final AddConnectedSlot addSlot;
  final Future<void> Function(String) removeSlot;
  final Future<void> Function(String) addUnavailableDate;
  final Future<void> Function(String) removeUnavailableDate;

  @override
  State<ConnectedProviderSetupScreen> createState() =>
      _ConnectedProviderSetupScreenState();
}

class _ConnectedProviderSetupScreenState
    extends State<ConnectedProviderSetupScreen> {
  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  late Future<ProviderSetupData> _future;
  ProviderSetupData? _last;
  bool _verifying = true;
  bool _fresh = false;
  Set<String> _selectedServices = {};
  bool _busy = false;
  bool _needsVerification = false;
  String? _error;
  ConnectedActionNotice? _notice;

  @override
  void initState() {
    super.initState();
    _last = widget.initialData;
    _selectedServices = Set.of(_last?.selectedServiceIds ?? const <String>{});
    _future = _load();
  }

  Future<ProviderSetupData> _load({bool preserveServices = false}) async {
    try {
      final data = await widget.load();
      if (!mounted) return data;
      _last = data;
      _fresh = true;
      if (!preserveServices)
        _selectedServices = Set.of(data.selectedServiceIds);
      return data;
    } catch (error) {
      if (rejectsSnapshot(error)) _last = null;
      rethrow;
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _refresh({bool preserveServices = false, bool keepNotice = false}) =>
      setState(() {
        if (!keepNotice) _notice = null;
        _error = null;
        _needsVerification = false;
        _verifying = true;
        _fresh = false;
        _future = _load(preserveServices: preserveServices);
      });

  Future<void> _run(
    Future<void> Function() action, {
    String working = 'Saving availability',
    String saved = 'Your availability changes were saved to your account.',
  }) async {
    if (_busy || _needsVerification || _verifying || !_fresh) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = ConnectedActionNotice(ConnectedActionState.working, working,
          'Please wait while we check and save your changes.');
    });
    try {
      await action();
      if (mounted) {
        _notice = ConnectedActionNotice(
            ConnectedActionState.success, 'Changes saved', saved);
        _refresh(keepNotice: true);
      }
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.providerSetupSave, error);
      if (mounted) {
        final details = error.toString().toLowerCase();
        final deterministic = details.contains('confirmed booking') ||
            details.contains('confirmed job') ||
            details.contains('overlap') ||
            details.contains('2 hours');
        final message = details.contains('confirmed booking') ||
                details.contains('confirmed job')
            ? 'A confirmed job still needs this service or availability. Keep it until the booking is resolved.'
            : details.contains('overlap')
                ? 'Working slots on the same day cannot overlap.'
                : details.contains('2 hours')
                    ? 'Each working slot must be at least 2 hours.'
                    : ConnectedFailureMessage.forWrite(error,
                        item: 'availability');
        setState(() {
          _needsVerification = !deterministic;
          _error = message;
          _notice = deterministic
              ? ConnectedActionNotice(
                  ConnectedActionState.error, 'Change not saved', message)
              : null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSlot(int weekday, List<ProviderWeeklySlotItem> slots) async {
    final range = await showDialog<(int, int)>(
      context: context,
      builder: (_) => _WorkingSlotDialog(
        weekday: weekday,
        dayName: _days[weekday - 1],
        existing: slots,
      ),
    );
    if (!mounted || range == null) return;
    await _run(() => widget.addSlot(
          weekday,
          ProviderSlotRules.databaseTime(range.$1),
          ProviderSlotRules.databaseTime(range.$2),
        ));
  }

  Future<void> _addUnavailableDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      helpText: 'Choose a day you cannot accept cleaning jobs',
    );
    if (!mounted || date == null) return;
    final key = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final current = await _future;
    if (!mounted) return;
    if (current.unavailableDates.contains(key)) {
      setState(() {
        _error = 'This date is already unavailable.';
        _notice = ConnectedActionNotice(
            ConnectedActionState.error, 'Date already blocked', _error!);
      });
      return;
    }
    await _run(() => widget.addUnavailableDate(key));
  }

  Future<void> _confirmRemoval(
      String title, Future<void> Function() remove) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text(
            'This change affects future availability. Confirmed jobs will remain protected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _run(remove);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Services & availability'),
        actions: [
          IconButton(
            tooltip: 'Refresh availability',
            onPressed: _busy || _verifying ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ConnectedActionFeedbackFrame(
        notice: _notice,
        onDismiss: _busy ? null : () => setState(() => _notice = null),
        child: FutureBuilder<ProviderSetupData>(
          future: _future,
          builder: (context, snapshot) {
            final rejected =
                snapshot.hasError && rejectsSnapshot(snapshot.error!);
            final data = rejected ? null : snapshot.data ?? _last;
            if (snapshot.hasError && data == null) {
              SafeDiagnostics.app
                  .record(SafeOperation.providerSetupLoad, snapshot.error!);
              return ConnectedStatePanel(
                state: ConnectedViewState.error,
                title: 'Could not load your availability',
                message:
                    'Check your connection and try again. Your saved working hours have not been changed.',
                actionLabel: 'Retry',
                onAction: _refresh,
              );
            }
            if (data == null) {
              return const ConnectedStatePanel(
                state: ConnectedViewState.loading,
                title: 'Loading your availability',
                message:
                    'Checking your services, working hours and blocked dates.',
              );
            }
            if (_needsVerification) {
              return ConnectedStatePanel(
                state: ConnectedViewState.error,
                title: 'Check saved availability',
                message:
                    '${_error ?? 'We could not confirm the change.'} Your service selections are kept until you check the latest saved data.',
                actionLabel: 'Check latest data',
                onAction: () => _refresh(preserveServices: true),
              );
            }
            return Column(children: [
              SnapshotRefreshNotice(
                  refreshing: _verifying,
                  failed: snapshot.hasError,
                  onRetry: _refresh),
              if (snapshot.hasError)
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                        'Saved availability is read-only until the latest data is verified.')),
              Expanded(
                  child: AbsorbPointer(
                      absorbing: _verifying || snapshot.hasError,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          Card(
                            color: scheme.primaryContainer,
                            child: const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Select the services you provide, then declare the hours '
                                'when you can accept a complete cleaning appointment. '
                                'Changes are saved to your account.',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('Cleaning services',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          if (data.services.isEmpty)
                            ConnectedStatePanel(
                              state: ConnectedViewState.empty,
                              title: 'No cleaning services available',
                              message:
                                  'The service list is empty. Refresh and try again before setting your working hours.',
                              actionLabel: 'Refresh services',
                              onAction: _refresh,
                            ),
                          for (final service in data.services)
                            CheckboxListTile(
                              key: Key('service-${service.name}'),
                              value: _selectedServices.contains(service.id),
                              title: Text(service.name),
                              onChanged: _busy || !_fresh
                                  ? null
                                  : (checked) => setState(() {
                                        _notice = null;
                                        _error = null;
                                        if (checked == true) {
                                          _selectedServices.add(service.id);
                                        } else {
                                          _selectedServices.remove(service.id);
                                        }
                                      }),
                            ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _busy ||
                                    !_fresh ||
                                    data.services.isEmpty ||
                                    _selectedServices.isEmpty ||
                                    setEquals(_selectedServices,
                                        data.selectedServiceIds)
                                ? null
                                : () => _run(
                                      () => widget.saveServices(
                                          Set.of(_selectedServices)),
                                      working: 'Saving cleaning services',
                                      saved:
                                          'Your selected cleaning services were saved to your account.',
                                    ),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save service types'),
                          ),
                          const SizedBox(height: 26),
                          Text('Weekly working slots',
                              style: Theme.of(context).textTheme.titleLarge),
                          const Text(
                              'Each slot must be at least 2 hours. Slots may touch, but not overlap.'),
                          const SizedBox(height: 10),
                          for (var weekday = 1; weekday <= 7; weekday++)
                            _dayCard(weekday, data.slots, scheme),
                          const SizedBox(height: 24),
                          Text('Unavailable dates',
                              style: Theme.of(context).textTheme.titleLarge),
                          const Text(
                              'A blocked date overrides all weekly slots. Confirmed jobs cannot be invalidated.'),
                          const SizedBox(height: 8),
                          if (data.unavailableDates.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('No blocked dates.'),
                            ),
                          for (final date
                              in data.unavailableDates.toList()..sort())
                            ListTile(
                              title: Text(date),
                              trailing: IconButton(
                                tooltip: 'Remove unavailable date $date',
                                onPressed: _busy || !_fresh
                                    ? null
                                    : () => _confirmRemoval(
                                        'Remove unavailable date?',
                                        () =>
                                            widget.removeUnavailableDate(date)),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed:
                                _busy || !_fresh ? null : _addUnavailableDate,
                            icon: const Icon(Icons.event_busy_outlined),
                            label: const Text('Add unavailable date'),
                          ),
                          if (_error != null && _notice == null)
                            Text(_error!,
                                style: TextStyle(color: scheme.error)),
                        ],
                      )))
            ]);
          },
        ),
      ),
    );
  }

  Widget _dayCard(
    int weekday,
    List<ProviderWeeklySlotItem> allSlots,
    ColorScheme scheme,
  ) {
    final slots = allSlots.where((slot) => slot.weekday == weekday).toList()
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_days[weekday - 1],
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (slots.isEmpty)
              Text('No working hours',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            for (final slot in slots)
              Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${ProviderSlotRules.databaseTime(slot.startMinute)}'
                        '–${ProviderSlotRules.databaseTime(slot.endMinute)}'),
                    trailing: IconButton(
                      tooltip: 'Remove working slot',
                      onPressed: _busy || !_fresh
                          ? null
                          : () => _confirmRemoval('Remove working slot?',
                              () => widget.removeSlot(slot.id)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                  if (slot.endMinute - slot.startMinute <
                      ProviderSlotRules.minimumMinutes)
                    Text(
                      'This older slot is under 2 hours. Remove it and add a valid slot before accepting requests.',
                      style: TextStyle(color: scheme.error),
                    ),
                ],
              ),
            TextButton.icon(
              onPressed:
                  _busy || !_fresh ? null : () => _addSlot(weekday, allSlots),
              icon: const Icon(Icons.add),
              label: const Text('Add working slot'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkingSlotDialog extends StatefulWidget {
  const _WorkingSlotDialog({
    required this.weekday,
    required this.dayName,
    required this.existing,
  });
  final int weekday;
  final String dayName;
  final List<ProviderWeeklySlotItem> existing;

  @override
  State<_WorkingSlotDialog> createState() => _WorkingSlotDialogState();
}

class _WorkingSlotDialogState extends State<_WorkingSlotDialog> {
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 10, minute: 0);
  String? _error;

  Future<void> _pick(bool start) async {
    final value = await showTimeSlotPicker(
      context: context,
      initialTime: start ? _start : _end,
      title: start ? 'Working slot starts' : 'Working slot ends',
      description:
          'Your working hours in MYT. Saving checks for overlapping slots.',
      firstMinute: start
          ? 0
          : timeOfDayMinutes(_start) + ProviderSlotRules.minimumMinutes,
      lastMinute: start ? 1439 - ProviderSlotRules.minimumMinutes : 1439,
    );
    if (!mounted || value == null) return;
    setState(() {
      if (start) {
        _start = value;
        if (timeOfDayMinutes(_end) - timeOfDayMinutes(value) <
            ProviderSlotRules.minimumMinutes) {
          final end =
              timeOfDayMinutes(value) + ProviderSlotRules.minimumMinutes;
          _end = TimeOfDay(hour: end ~/ 60, minute: end % 60);
        }
      } else {
        _end = value;
      }
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Add working slot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.dayName} · minimum 2 hours'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _pick(true),
              child: Text('Start ${timeSlotLabel(timeOfDayMinutes(_start))}'),
            ),
            OutlinedButton(
              onPressed: () => _pick(false),
              child: Text('End ${timeSlotLabel(timeOfDayMinutes(_end))}'),
            ),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep unchanged'),
          ),
          FilledButton(
            onPressed: () {
              final start = _start.hour * 60 + _start.minute;
              final end = _end.hour * 60 + _end.minute;
              final error = ProviderSlotRules.validate(
                weekday: widget.weekday,
                startMinute: start,
                endMinute: end,
                existing: widget.existing,
              );
              if (error != null) {
                setState(() => _error = error);
                return;
              }
              Navigator.of(context).pop((start, end));
            },
            child: const Text('Save slot'),
          ),
        ],
      );
}
