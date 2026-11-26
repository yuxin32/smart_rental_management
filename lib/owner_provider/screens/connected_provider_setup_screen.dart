import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/backend/safe_diagnostics.dart';

import '../features/availability/domain/provider_setup.dart';
import '../features/availability/domain/cleaning_package.dart';
import '../widgets/provider_cleaning_packages.dart';
import '../services/backend/connected_failure_message.dart';
import '../widgets/connected_state_panel.dart';
import '../widgets/connected_action_feedback.dart';
import '../widgets/snapshot_refresh_notice.dart';
import '../services/backend/session_snapshot_cache.dart';
import '../widgets/provider_weekly_hours_editor.dart';
import '../theme/app_theme.dart';

/// All reads and writes are delegated to the authenticated backend. No
/// sample availability or service capability is created in this screen.
class ConnectedProviderSetupScreen extends StatefulWidget {
  const ConnectedProviderSetupScreen({
    super.key,
    required this.load,
    this.initialData,
    required this.saveServices,
    required this.loadWeeklyHours,
    required this.saveWeeklyHours,
    required this.addUnavailableDate,
    required this.removeUnavailableDate,
    required this.loadDayOffConstraints,
    this.bottomNavigationBar,
    this.loadPackages,
    this.savePackage,
  });

  final Future<ProviderSetupData> Function() load;
  final ProviderSetupData? initialData;
  final Future<void> Function(Set<String>) saveServices;
  final Future<ProviderWeeklyState> Function() loadWeeklyHours;
  final SaveProviderWeek saveWeeklyHours;
  final Widget? bottomNavigationBar;
  final Future<List<CleaningPackage>> Function()? loadPackages;
  final SaveCleaningPackage? savePackage;
  final Future<void> Function(String) addUnavailableDate;
  final Future<void> Function(String) removeUnavailableDate;
  final Future<ProviderDayOffConstraints> Function(DateTime, DateTime)
      loadDayOffConstraints;

  @override
  State<ConnectedProviderSetupScreen> createState() =>
      _ConnectedProviderSetupScreenState();
}

class _ConnectedProviderSetupScreenState
    extends State<ConnectedProviderSetupScreen> {
  late Future<ProviderSetupData> _future;
  ProviderSetupData? _last;
  bool _verifying = true;
  bool _fresh = false;
  Set<String> _selectedServices = {};
  bool _busy = false;
  bool _needsVerification = false;
  bool _checkingDates = false;
  bool _retryDates = false;
  bool _weeklyBusy = false;
  bool _packageBusy = false;
  bool _showWorkingHours = false;
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
        _retryDates = false;
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
    if (_busy ||
        _weeklyBusy ||
        _checkingDates ||
        _needsVerification ||
        _verifying ||
        !_fresh) return;
    setState(() {
      _busy = true;
      _retryDates = false;
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

  Future<void> _addUnavailableDate() async {
    if (_busy ||
        _weeklyBusy ||
        _checkingDates ||
        _verifying ||
        !_fresh ||
        _needsVerification) return;
    setState(() {
      _checkingDates = true;
      _retryDates = false;
      _notice = null;
      _error = null;
    });
    try {
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      final first = DateTime(now.year, now.month, now.day);
      final last = DateTime(now.year + 2);
      final constraints = await widget.loadDayOffConstraints(first, last);
      if (!mounted) return;
      if (ProviderDayOffConstraints.dateKey(constraints.firstDate) !=
              ProviderDayOffConstraints.dateKey(first) ||
          ProviderDayOffConstraints.dateKey(constraints.lastDate) !=
              ProviderDayOffConstraints.dateKey(last)) {
        throw StateError('Date range could not be verified.');
      }
      DateTime? initial;
      for (var day = first;
          !day.isAfter(last);
          day = DateTime(day.year, day.month, day.day + 1)) {
        if (constraints.allows(day)) {
          initial = day;
          break;
        }
      }
      if (initial == null) {
        setState(() => _notice = const ConnectedActionNotice(
            ConnectedActionState.error,
            'No dates available',
            'Every date in this calendar already has a confirmed job or a day off.'));
        return;
      }
      setState(() => _checkingDates = false);
      final date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: first,
        lastDate: last,
        currentDate: first,
        selectableDayPredicate: constraints.allows,
        helpText: 'Choose an unavailable date',
        errorInvalidText:
            'Choose a date without a confirmed job or an existing day off.',
      );
      if (!mounted || date == null) return;
      if (!constraints.allows(date))
        throw StateError('Date could not be verified.');
      setState(() => _checkingDates = false);
      await _run(() =>
          widget.addUnavailableDate(ProviderDayOffConstraints.dateKey(date)));
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.providerSetupLoad, error);
      if (mounted)
        setState(() {
          _retryDates = true;
          _notice = const ConnectedActionNotice(
              ConnectedActionState.error,
              'Could not check dates',
              'Your latest bookings and days off could not be verified. Try again before choosing a date.');
        });
    } finally {
      if (mounted) setState(() => _checkingDates = false);
    }
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

  Widget _buildSection(BuildContext context, String title, IconData icon,
      List<Widget> children) {
    final sem = SemanticColors.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: sem.surface,
          border: Border.all(color: sem.border),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            key: ValueKey('availability-section-$title'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).brightness == Brightness.dark
                ? sem.primarySurface
                : sem.primaryBorder,
            child: Row(children: [
              Icon(icon,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: sem.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)))
            ])),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children)),
      ]),
    );
  }

  bool get _packagesConfigured =>
      widget.loadPackages != null && widget.savePackage != null;

  Future<void> _manageDaysOff() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) {
          final dates = (_last?.unavailableDates.toList() ?? <String>[])
            ..sort();
          Future<void> run(Future<void> Function() action) async {
            await action();
            try {
              await _future;
            } catch (_) {
              /* Parent shows verification error. */
            }
            if (sheetContext.mounted) updateSheet(() {});
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Days off',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close days off',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (dates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No days off added.'),
                      ),
                    for (final date in dates)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          DateFormat(
                            'EEE, d MMM yyyy',
                          ).format(DateTime.parse(date)),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove unavailable date $date',
                          onPressed: _busy ||
                                  _weeklyBusy ||
                                  _packageBusy ||
                                  !_fresh
                              ? null
                              : () => run(
                                    () => _confirmRemoval(
                                      'Remove day off?',
                                      () => widget.removeUnavailableDate(date),
                                    ),
                                  ),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy ||
                              _weeklyBusy ||
                              _packageBusy ||
                              _checkingDates ||
                              !_fresh
                          ? null
                          : () => run(_addUnavailableDate),
                      icon: const Icon(Icons.add),
                      label: const Text('Add day off'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Dates with confirmed jobs cannot be blocked.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _compactContents(ProviderSetupData data) {
    final disabled =
        _busy || _weeklyBusy || _packageBusy || _checkingDates || !_fresh;
    Widget tab(String label, bool selected, VoidCallback onTap) => Expanded(
          child: selected
              ? FilledButton(
                  onPressed: disabled ? null : onTap, child: Text(label))
              : OutlinedButton(
                  onPressed: disabled ? null : onTap,
                  child: Text(label),
                ),
        );
    return [
      Row(
        children: [
          tab(
            'Packages',
            !_showWorkingHours,
            () => setState(() => _showWorkingHours = false),
          ),
          const SizedBox(width: 8),
          tab(
            'Working hours',
            _showWorkingHours,
            () => setState(() => _showWorkingHours = true),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (!_showWorkingHours) ...[
        ProviderCleaningPackages(
          key: const ValueKey('provider-cleaning-packages'),
          services: data.services,
          selectedServices: data.selectedServiceIds,
          load: widget.loadPackages!,
          save: widget.savePackage!,
          enabled: _fresh && !_busy && !_weeklyBusy,
          onBusyChanged: (busy) {
            if (mounted) setState(() => _packageBusy = busy);
          },
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          key: const ValueKey('package-service-capabilities'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Services offered'),
          children: [
            for (final service in data.services)
              CheckboxListTile(
                key: Key('service-${service.name}'),
                contentPadding: EdgeInsets.zero,
                title: Text(service.name),
                value: _selectedServices.contains(service.id),
                secondary:
                    data.weeklyState?.requiredServices.contains(service.id) ==
                            true
                        ? const Icon(Icons.lock_outline, size: 18)
                        : null,
                onChanged: disabled ||
                        data.weeklyState?.requiredServices.contains(
                              service.id,
                            ) ==
                            true
                    ? null
                    : (checked) => setState(() {
                          if (checked == true) {
                            _selectedServices.add(service.id);
                          } else {
                            _selectedServices.remove(service.id);
                          }
                        }),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: disabled ||
                        _selectedServices.isEmpty ||
                        setEquals(_selectedServices, data.selectedServiceIds)
                    ? null
                    : () => _run(
                          () => widget.saveServices(Set.of(_selectedServices)),
                          working: 'Saving cleaning services',
                          saved: 'Cleaning services saved.',
                        ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save services'),
              ),
            ),
          ],
        ),
      ] else ...[
        ProviderWeeklyHoursEditor(
          key: const ValueKey('provider-weekly-hours'),
          data: data,
          enabled: _fresh && !_busy && !_packageBusy && !_checkingDates,
          loadFresh: widget.loadWeeklyHours,
          save: widget.saveWeeklyHours,
          onSaved: () => _refresh(preserveServices: true, keepNotice: true),
          onBusyChanged: (busy) {
            if (mounted) setState(() => _weeklyBusy = busy);
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Days off · ${data.unavailableDates.length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: disabled ? null : _manageDaysOff,
              child: const Text('Manage'),
            ),
          ],
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 16),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'Confirmed bookings are protected.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
      if (_error != null && _notice == null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      bottomNavigationBar: widget.bottomNavigationBar,
      appBar: AppBar(
        title: const Text('Services & availability'),
        actions: [
          IconButton(
            tooltip: 'Refresh availability',
            onPressed: _busy || _weeklyBusy || _packageBusy || _verifying || _checkingDates
                ? null
                : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ConnectedActionFeedbackFrame(
        notice: _notice,
        actionLabel: _retryDates ? 'Check dates again' : null,
        onAction: _retryDates && !_checkingDates && !_busy
            ? _addUnavailableDate
            : null,
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
                      absorbing:
                          _verifying || _checkingDates || snapshot.hasError,
                      child: ListView(
                        key: const PageStorageKey('services-availability-form'),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          if (_packagesConfigured) ..._compactContents(data) else ...[
                          _buildSection(context, 'Cleaning services',
                              Icons.cleaning_services_outlined, [
                            if (data.services.isEmpty)
                              ConnectedStatePanel(
                                state: ConnectedViewState.empty,
                                title: 'No cleaning services available',
                                message:
                                    'The service list is empty. Refresh and try again before setting your working hours.',
                                actionLabel: 'Refresh services',
                                onAction: _refresh,
                              ),
                            SizedBox(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  for (final service in data.services)
                                    CheckboxListTile(
                                      key: Key('service-${service.name}'),
                                      value: _selectedServices
                                          .contains(service.id),
                                      title: Text(service.name,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface)),
                                      secondary: data
                                                  .weeklyState?.requiredServices
                                                  .contains(service.id) ==
                                              true
                                          ? const Icon(Icons.lock_outline,
                                              size: 18)
                                          : null,
                                      subtitle: data
                                                  .weeklyState?.requiredServices
                                                  .contains(service.id) ==
                                              true
                                          ? Text('Used by an upcoming booking',
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant))
                                          : null,
                                      onChanged: _busy ||
                                              _weeklyBusy ||
                                              !_fresh ||
                                              data.weeklyState?.requiredServices
                                                      .contains(service.id) ==
                                                  true
                                          ? null
                                          : (checked) => setState(() {
                                                _notice = null;
                                                _error = null;
                                                if (checked == true) {
                                                  _selectedServices
                                                      .add(service.id);
                                                } else {
                                                  _selectedServices
                                                      .remove(service.id);
                                                }
                                              }),
                                    ),
                                  const SizedBox(height: 8),
                                  FilledButton.icon(
                                    onPressed: _busy ||
                                            _weeklyBusy ||
                                            !_fresh ||
                                            data.services.isEmpty ||
                                            _selectedServices.isEmpty ||
                                            setEquals(_selectedServices,
                                                data.selectedServiceIds)
                                        ? null
                                        : () => _run(
                                              () => widget.saveServices(
                                                  Set.of(_selectedServices)),
                                              working:
                                                  'Saving cleaning services',
                                              saved:
                                                  'Your selected cleaning services were saved to your account.',
                                            ),
                                    icon: const Icon(Icons.save_outlined),
                                    label: const Text('Save services'),
                                  ),
                                ])),
                          ]),
                          const SizedBox(height: 26),
                          _buildSection(context, 'Weekly working hours',
                              Icons.schedule_outlined, [
                            ProviderWeeklyHoursEditor(
                              key: const ValueKey('provider-weekly-hours'),
                              data: data,
                              enabled: _fresh && !_busy && !_checkingDates,
                              loadFresh: widget.loadWeeklyHours,
                              save: widget.saveWeeklyHours,
                              onSaved: () => _refresh(
                                  preserveServices: true, keepNotice: true),
                              onBusyChanged: (busy) {
                                if (mounted) setState(() => _weeklyBusy = busy);
                              },
                            ),
                          ]),
                          const SizedBox(height: 24),
                          _buildSection(
                              context, 'Days off', Icons.event_busy_outlined, [
                            const Text(
                                'One-off dates · weekly hours stay the same.'),
                            const SizedBox(height: 8),
                            if (data.unavailableDates.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('No days off added.'),
                              ),
                            for (final date
                                in data.unavailableDates.toList()..sort())
                              ListTile(
                                title: Text(DateFormat('EEE, d MMM yyyy')
                                    .format(DateTime.parse(date))),
                                subtitle: const Text('All day'),
                                trailing: IconButton(
                                  tooltip: 'Remove unavailable date $date',
                                  onPressed: _busy || _weeklyBusy || !_fresh
                                      ? null
                                      : () => _confirmRemoval(
                                          'Remove day off?',
                                          () => widget
                                              .removeUnavailableDate(date)),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: _busy ||
                                      _weeklyBusy ||
                                      _checkingDates ||
                                      _needsVerification ||
                                      !_fresh
                                  ? null
                                  : _addUnavailableDate,
                              icon: _checkingDates
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.event_busy_outlined),
                              label: Text(_checkingDates
                                  ? 'Checking dates…'
                                  : 'Add day off'),
                            ),
                          ]),
                          if (_error != null && _notice == null)
                            Text(_error!,
                                style: TextStyle(color: scheme.error)),
                          ],
                        ],
                      )))
            ]);
          },
        ),
      ),
    );
  }
}
