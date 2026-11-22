import '../presentation/workspace_text.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/backend/safe_diagnostics.dart';

import '../services/backend/supabase_booking_repository.dart';
import '../services/backend/connected_failure_message.dart';
import '../services/backend/supabase_owner_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/connected_state_panel.dart';
import '../widgets/connected_action_feedback.dart';
import '../widgets/cleaning_service_scope.dart';
import '../widgets/time_slot_picker.dart';
import '../widgets/unsaved_changes_guard.dart';

/// Local calendar entries are explicitly interpreted as Malaysia time.
/// Keeping this conversion independent of device timezone prevents an Owner
/// travelling abroad from submitting a different interval than they saw.
DateTime malaysiaBookingInstant(DateTime day, TimeOfDay time) => DateTime.utc(
      day.year,
      day.month,
      day.day,
      time.hour - 8,
      time.minute,
    );

class ConnectedBookingRequestScreen extends StatefulWidget {
  const ConnectedBookingRequestScreen({
    super.key,
    required this.loadProperties,
    required this.loadServiceTypes,
    required this.findEligible,
    required this.createPending,
    required this.findCreatedBooking,
    this.now,
    this.initialPropertyId,
  });

  final Future<List<Map<String, dynamic>>> Function() loadProperties;
  final Future<List<Map<String, dynamic>>> Function() loadServiceTypes;
  final Future<List<EligibleProviderItem>> Function({
    required String propertyId,
    required String serviceTypeId,
    required DateTime start,
    required DateTime end,
  }) findEligible;
  final Future<BookingCreationOutcome> Function({
    required String clientRequestId,
    required String providerId,
    required String propertyId,
    required String serviceTypeId,
    required DateTime start,
    required DateTime end,
    required num expectedAmount,
    required String expectedBasis,
    required String instructions,
  }) createPending;
  final Future<String?> Function(String clientRequestId) findCreatedBooking;
  final DateTime Function()? now;
  final String? initialPropertyId;

  @override
  State<ConnectedBookingRequestScreen> createState() =>
      _ConnectedBookingRequestScreenState();
}

class _ConnectedBookingRequestScreenState
    extends State<ConnectedBookingRequestScreen> {
  late Future<_RequestOptions> _options;
  List<Map<String, dynamic>> _properties = const [];
  String? _propertyId;
  String? _serviceTypeId;
  DateTime? _day;
  TimeOfDay? _start;
  TimeOfDay? _end;
  List<EligibleProviderItem>? _eligible;
  EligibleProviderItem? _selectedProvider;
  DateTime? _searchedStart;
  DateTime? _searchedEnd;
  final TextEditingController _instructions = TextEditingController();
  final TextEditingController _additionalTasks = TextEditingController();
  String? _requestToken;
  bool _searching = false;
  bool _searchFailed = false;
  bool _submitting = false;
  bool _verifyingSubmission = false;
  String? _message;
  int _requestVersion = 0;
  int _step = 0;
  bool _saved = false;
  final _scroll = ScrollController();
  void _top() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
  bool _validateDetails = false;

  @override
  void initState() {
    super.initState();
    _propertyId = widget.initialPropertyId;
    _options = _loadOptions();
  }

  Future<_RequestOptions> _loadOptions() async {
    final result = await Future.wait([
      widget.loadProperties(),
      widget.loadServiceTypes(),
    ]);
    _properties = result[0];
    if (_propertyId != null &&
        !result[0].any((p) => p['property_id'] == _propertyId))
      _propertyId = null;
    return _RequestOptions(result[0], result[1]);
  }

  void _retryOptions() => setState(() {
        _message = null;
        _options = _loadOptions();
      });

  void _changed(VoidCallback update) {
    setState(() {
      update();
      _requestVersion++;
      _eligible = null;
      _selectedProvider = null;
      _requestToken = null;
      _searchedStart = null;
      _searchedEnd = null;
      _message = null;
      _searchFailed = false;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _instructions.dispose();
    _additionalTasks.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final today = (widget.now?.call() ?? DateTime.now())
        .toUtc()
        .add(const Duration(hours: 8));
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? today,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
    );
    if (picked != null && mounted) _changed(() => _day = picked);
  }

  Future<void> _pickTime(bool start) async {
    var windowStart = 0;
    var windowEnd = 1439;
    for (final property in _properties) {
      if (property['property_id'] == _propertyId) {
        windowStart =
            parseTimeSlot(property['cleaning_window_start']?.toString()) ?? 0;
        windowEnd =
            parseTimeSlot(property['cleaning_window_end']?.toString()) ?? 1439;
        break;
      }
    }
    var first = start
        ? windowStart
        : math.max(
            windowStart, _start == null ? 0 : timeOfDayMinutes(_start!) + 1);
    final last = start
        ? windowEnd - 1
        : math.min(
            windowEnd, _start == null ? 1439 : timeOfDayMinutes(_start!) + 480);
    final today = (widget.now?.call() ?? DateTime.now())
        .toUtc()
        .add(const Duration(hours: 8));
    if (start &&
        _day?.year == today.year &&
        _day?.month == today.month &&
        _day?.day == today.day) {
      first = math.max(first, today.hour * 60 + today.minute + 1);
    }
    final endDefault =
        ((timeOfDayMinutes(_start ?? const TimeOfDay(hour: 9, minute: 0))) +
                120)
            .clamp(0, 1439);
    final picked = await showTimeSlotPicker(
      context: context,
      initialTime: start
          ? (_start ?? const TimeOfDay(hour: 9, minute: 0))
          : (_end ??
              TimeOfDay(hour: endDefault ~/ 60, minute: endDefault % 60)),
      title: start ? 'Requested start time' : 'Requested end time',
      description:
          'Within your unit’s cleaning window. Provider availability is checked when you search. MYT (UTC+8).',
      firstMinute: first,
      lastMinute: last,
    );
    if (picked != null && mounted) {
      _changed(() {
        if (start) {
          _start = picked;
          if (_end != null &&
              (timeOfDayMinutes(_end!) <= timeOfDayMinutes(picked) ||
                  timeOfDayMinutes(_end!) - timeOfDayMinutes(picked) > 480)) {
            _end = null;
          }
        } else {
          _end = picked;
        }
      });
    }
  }

  Future<void> _search() async {
    if (_searching) return;
    final propertyId = _propertyId;
    final serviceTypeId = _serviceTypeId;
    final day = _day;
    final start = _start;
    final end = _end;
    if (propertyId == null ||
        serviceTypeId == null ||
        day == null ||
        start == null ||
        end == null) {
      setState(() => _message = 'Choose a unit, service, date and both times.');
      return;
    }
    final startAt = malaysiaBookingInstant(day, start);
    final endAt = malaysiaBookingInstant(day, end);
    if (!endAt.isAfter(startAt) ||
        !startAt.isAfter((widget.now?.call() ?? DateTime.now()).toUtc())) {
      setState(
          () => _message = 'Choose a future interval with end after start.');
      return;
    }
    if (endAt.difference(startAt) > const Duration(hours: 8)) {
      setState(() => _message = 'Service duration cannot exceed 8 hours.');
      return;
    }
    final searchVersion = _requestVersion;
    setState(() {
      _searching = true;
      _searchFailed = false;
      _message = null;
      _eligible = null;
      _selectedProvider = null;
      _requestToken = null;
    });
    try {
      final found = await widget.findEligible(
        propertyId: propertyId,
        serviceTypeId: serviceTypeId,
        start: startAt,
        end: endAt,
      );
      if (!mounted || searchVersion != _requestVersion) return;
      setState(() {
        _eligible = found;
        _step = 2;
        _top();
        _searchedStart = startAt;
        _searchedEnd = endAt;
      });
    } catch (error) {
      if (!mounted || searchVersion != _requestVersion) return;
      SafeDiagnostics.app.record(SafeOperation.providerSearch, error);
      setState(() => _searchFailed = true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final provider = _selectedProvider;
    final propertyId = _propertyId;
    final serviceTypeId = _serviceTypeId;
    final start = _searchedStart;
    final end = _searchedEnd;
    if (provider == null ||
        propertyId == null ||
        serviceTypeId == null ||
        start == null ||
        end == null) return;
    final token = _requestToken ?? BookingRequestToken.newV4();
    setState(() {
      _requestToken = token;
      _submitting = true;
      _verifyingSubmission = false;
      _message = null;
    });
    try {
      await widget.createPending(
        clientRequestId: token,
        providerId: provider.providerId,
        propertyId: propertyId,
        serviceTypeId: serviceTypeId,
        start: start,
        end: end,
        expectedAmount: provider.quotedAmount,
        expectedBasis: provider.quoteBasis,
        instructions: bookingRequestInstructions(
            _instructions.text, _additionalTasks.text),
      );
      if (mounted) {
        _saved = true;
        _submitting = false;
        Navigator.of(context).pop(true);
      }
    } on BookingRequestRejected catch (error) {
      if (!mounted) return;
      final notice = ConnectedFailureMessage.forBookingReason(error.reason);
      setState(() {
        _message = notice;
        _step = 1;
        _top();
        _eligible = null;
        _selectedProvider = null;
        _requestToken = null;
      });
    } catch (error) {
      if (!mounted) return;
      SafeDiagnostics.app.record(SafeOperation.requestCreate, error);
      setState(() => _verifyingSubmission = true);
      try {
        final existing = await widget.findCreatedBooking(token);
        if (!mounted) return;
        if (existing != null) {
          _saved = true;
          _submitting = false;
          Navigator.of(context).pop(true);
          return;
        }
        setState(() => _message =
            'The request was not found in your bookings. You can retry with the same request details; a duplicate will not be created.');
      } catch (lookupError) {
        SafeDiagnostics.app.record(SafeOperation.requestVerify, lookupError);
        if (!mounted) return;
        setState(() => _message =
            'We could not confirm whether the request was saved. Check your bookings when connected, or retry here with the same request details; a duplicate will not be created.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _timeLabel(TimeOfDay? time) => time == null
      ? 'Select time'
      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      dirty: () =>
          !_saved &&
          (_serviceTypeId != null ||
              _day != null ||
              _instructions.text.isNotEmpty ||
              _additionalTasks.text.isNotEmpty),
      busy: () => _submitting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Request cleaning')),
        body: ConnectedActionFeedbackFrame(
          notice: _submitting
              ? ConnectedActionNotice(
                  ConnectedActionState.working,
                  _verifyingSubmission
                      ? 'Checking your request'
                      : 'Sending cleaning request',
                  _verifyingSubmission
                      ? 'Checking your bookings before offering a retry.'
                      : 'Please wait while we validate and save your Pending request.')
              : _message == null
                  ? null
                  : ConnectedActionNotice(ConnectedActionState.error,
                      'Check your request', _message!),
          child: FutureBuilder<_RequestOptions>(
            future: _options,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ConnectedStatePanel(
                  state: ConnectedViewState.error,
                  title: 'Could not prepare your request',
                  message:
                      'Check your connection, then try loading your units and services again.',
                  actionLabel: 'Retry',
                  onAction: _retryOptions,
                );
              }
              if (!snapshot.hasData) {
                return const ConnectedStatePanel(
                  state: ConnectedViewState.loading,
                  title: 'Preparing your request',
                  message: 'Loading your rental units and cleaning services.',
                );
              }
              final options = snapshot.data!;
              if (options.properties.isEmpty) {
                return ConnectedStatePanel(
                  state: ConnectedViewState.empty,
                  title: 'Add a rental unit first',
                  message:
                      'A cleaning request needs a rental unit. Return Home, open Properties from the bottom menu and add your unit, then try again.',
                  actionLabel: 'Back to Home',
                  onAction: () => Navigator.of(context).pop(),
                );
              }
              if (options.serviceTypes.isEmpty) {
                return ConnectedStatePanel(
                  state: ConnectedViewState.empty,
                  title: 'Cleaning services are unavailable',
                  message:
                      'We could not find any service types to request. Try loading them again.',
                  actionLabel: 'Retry',
                  onAction: _retryOptions,
                );
              }
              return AbsorbPointer(
                absorbing: _submitting,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(18),
                  children: [
                    Text('Step ${_step + 1} of 4',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: (_step + 1) / 4),
                    const SizedBox(height: 12),
                    Text(
                        const [
                          'Unit & service',
                          'Date & time',
                          'Choose provider',
                          'Review & send'
                        ][_step],
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    if (_step > 0)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: const Text('Previous step'),
                              onPressed: _submitting || _searching
                                  ? null
                                  : () => setState(() {
                                        _step--;
                                        _top();
                                        _message = null;
                                      }))),
                    if (_step == 0) ...[
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Plan your cleaning request',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: 6),
                            Text(
                                'Check the full service interval in Malaysia time before choosing a provider.',
                                style: TextStyle(
                                    color: Color(0xFFD9E8FF), height: 1.4)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        key: const Key('request-unit'),
                        isExpanded: true,
                        value: _propertyId,
                        decoration: InputDecoration(
                            labelText: 'Rental unit',
                            errorText: _validateDetails && _propertyId == null
                                ? 'Choose your rental unit.'
                                : null),
                        items: options.properties.map((row) {
                          final label =
                              '${workspaceText(row['unit_name'] as String)}, ${workspaceText(row['building_name'] as String)}';
                          return DropdownMenuItem(
                            value: row['property_id'] as String,
                            child: Tooltip(
                              message: label,
                              child: Text(label,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            _changed(() => _propertyId = value),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        key: const Key('request-service'),
                        isExpanded: true,
                        value: _serviceTypeId,
                        decoration: InputDecoration(
                            labelText: 'Cleaning service',
                            errorText:
                                _validateDetails && _serviceTypeId == null
                                    ? 'Choose a cleaning service.'
                                    : null),
                        items: options.serviceTypes.map((row) {
                          final label = row['name'] as String;
                          return DropdownMenuItem(
                            value: row['service_type_id'] as String,
                            child: Tooltip(
                              message: label,
                              child: Text(label,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            _changed(() => _serviceTypeId = value),
                      ),
                      if (_serviceTypeId != null) ...[
                        const SizedBox(height: 12),
                        CleaningServiceScope(
                          description: options.serviceTypes.firstWhere((row) =>
                              row['service_type_id'] ==
                              _serviceTypeId)['description'] as String?,
                        ),
                      ],
                      const SizedBox(height: 14),
                      FilledButton(
                          onPressed: () {
                            setState(() {
                              _validateDetails = true;
                              if (_propertyId != null &&
                                  _serviceTypeId != null) {
                                _step = 1;
                                _top();
                                _message = null;
                              }
                            });
                          },
                          child: const Text('Continue to date & time')),
                    ],
                    if (_step == 1) ...[
                      Semantics(
                        button: true,
                        label: _day == null
                            ? 'Select service date'
                            : 'Service date: ${_day!.day}/${_day!.month}/${_day!.year}',
                        onTap: _pickDay,
                        child: ExcludeSemantics(
                            child: OutlinedButton.icon(
                          onPressed: _pickDay,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(_day == null
                              ? 'Select service date'
                              : '${_day!.day}/${_day!.month}/${_day!.year}'),
                        )),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Start time'),
                              Semantics(
                                button: true,
                                label: 'Start time: ${_timeLabel(_start)}',
                                onTap: () => _pickTime(true),
                                child: ExcludeSemantics(
                                    child: OutlinedButton.icon(
                                  onPressed: () => _pickTime(true),
                                  icon: const Icon(Icons.schedule_outlined),
                                  label: Text(_timeLabel(_start)),
                                )),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('End time'),
                              Semantics(
                                button: true,
                                label: 'End time: ${_timeLabel(_end)}',
                                onTap: () => _pickTime(false),
                                child: ExcludeSemantics(
                                    child: OutlinedButton.icon(
                                  onPressed: () => _pickTime(false),
                                  icon: const Icon(Icons.schedule_outlined),
                                  label: Text(_timeLabel(_end)),
                                )),
                              ),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      const Text(
                          'All times are shown in Malaysia time (MYT, UTC+8).'),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _searching ? null : _search,
                        icon: const Icon(Icons.search),
                        label: Text(_searching
                            ? 'Checking availability…'
                            : 'Find eligible providers'),
                      ),
                    ],
                    if (_step == 1 || _step == 2) ...[
                      if (_searching)
                        const ConnectedStatePanel(
                          state: ConnectedViewState.loading,
                          title: 'Checking providers',
                          message:
                              'We are checking the complete requested interval.',
                        ),
                      if (_searchFailed)
                        ConnectedStatePanel(
                          state: ConnectedViewState.error,
                          title: 'Could not check providers',
                          message:
                              'Check your connection and try the same request again.',
                          actionLabel: 'Retry search',
                          onAction: _search,
                        ),
                    ],
                    if (_step == 2 && _eligible != null) ...[
                      const SizedBox(height: 22),
                      Text('Eligible when checked · ${_eligible!.length}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(height: 5),
                      const Text(
                          'These providers meet the requested service and time checks. Compare their rates and ratings before choosing. The quoted price is checked again when you submit.'),
                      if (_eligible!.isEmpty)
                        ConnectedStatePanel(
                          state: ConnectedViewState.empty,
                          title: 'No provider available for this time',
                          message:
                              'Try a different service time or cleaning type. You can also check this interval again.',
                          actionLabel: 'Check again',
                          onAction: _search,
                        ),
                      ..._eligible!.map(_providerCard),
                    ],
                    if (_step == 3 && _selectedProvider != null)
                      _reviewCard(options),
                  ],
                ),
              );
            },
          ),
        ),
      ));

  Widget _providerCard(EligibleProviderItem provider) {
    final rates = [
      if (provider.hourlyRate != null) 'RM ${provider.hourlyRate}/hour',
      if (provider.dailyRate != null) 'RM ${provider.dailyRate}/day',
    ].join(' · ');
    final selected = _selectedProvider?.providerId == provider.providerId;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: selected ? const Color(0xFFE9F0FC) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Eligible cleaning provider',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 5),
            Text(provider.serviceArea),
            if (provider.bio?.isNotEmpty == true) Text(provider.bio!),
            const SizedBox(height: 7),
            Text(rates),
            const SizedBox(height: 7),
            Text(
              'Quoted price · RM ${provider.quotedAmount.toStringAsFixed(2)} '
              '(${provider.quoteBasis == 'daily' ? '8-hour day rate' : 'hourly rate'})',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800),
            ),
            Text(
                'Rating: ${provider.ratingAverage?.toString() ?? 'New provider'} · '
                '${provider.completedJobCount} completed jobs'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                        _selectedProvider = provider;
                        _step = 3;
                        _top();
                        _requestToken = null;
                        _message = null;
                      }),
              child: Text(selected ? 'Selected' : 'Select and review'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(_RequestOptions options) {
    final provider = _selectedProvider!;
    final selectedService = options.serviceTypes.firstWhere(
      (row) => row['service_type_id'] == _serviceTypeId,
    )['name'] as String;
    final selectedProperty = options.properties.firstWhere(
      (row) => row['property_id'] == _propertyId,
    );
    return Card(
      margin: const EdgeInsets.only(top: 16, bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Review your request',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            Text(
                '$selectedService · ${workspaceText(selectedProperty['unit_name'] as String)}'),
            Text('Date: ${_day!.day}/${_day!.month}/${_day!.year} · '
                '${_timeLabel(_start)}–${_timeLabel(_end)} MYT'),
            Text('Provider area: ${provider.serviceArea}'),
            const SizedBox(height: 8),
            Text(
                'Total quoted amount: RM ${provider.quotedAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(provider.quoteBasis == 'daily'
                ? 'Fixed 8-hour daily rate.'
                : 'Hourly rate multiplied by booked time.'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('booking-instructions'),
              controller: _instructions,
              enabled: !_submitting,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Cleaning instructions (optional)',
                hintText: 'Describe areas to focus on or access details',
              ),
              onChanged: (_) => _requestToken = null,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('booking-additional-tasks'),
              controller: _additionalTasks,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Additional tasks to discuss (optional)',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                alignLabelWithHint: true,
                hintText: 'e.g. Can you also clean inside the oven?',
                helperText:
                    'Not included in this quote. Confirm with your provider before work starts; a new quote may be needed.',
                helperMaxLines: 5,
              ),
              onChanged: (_) => _requestToken = null,
            ),
            const SizedBox(height: 4),
            const Text(
                'Your request will remain Pending until the provider accepts it. You will not be charged when you submit this request; online payment is not available yet.'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(
                    _submitting ? 'Submitting…' : 'Submit Pending request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestOptions {
  const _RequestOptions(this.properties, this.serviceTypes);
  final List<Map<String, dynamic>> properties;
  final List<Map<String, dynamic>> serviceTypes;
}
