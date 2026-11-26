import '../presentation/workspace_text.dart';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import '../services/backend/service_location.dart';
import '../widgets/rental_location_editor.dart';

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
    this.findMatches,
    this.findPackageMatches,
    this.createPackagePending,
    this.loadServiceAreas,
    this.savePropertyLocation,
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
  final Future<ProviderSearchResult> Function(
      {required String propertyId,
      required String serviceTypeId,
      required DateTime start,
      required DateTime end})? findMatches;

  /// Supplying this callback enables duration-based package selection.
  /// Legacy callers keep the original manual interval flow.
  final Future<ProviderSearchResult> Function({
    required String propertyId,
    required String serviceTypeId,
    required DateTime start,
    required DateTime end,
    required int cleanerCount,
  })? findPackageMatches;
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
    required String packageId,
  })? createPackagePending;
  final Future<List<ServiceAreaOption>> Function()? loadServiceAreas;
  final Future<void> Function(String id, int revision, String area, String pin)?
      savePropertyLocation;

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
  int _cleanerCount = 1;
  int _durationMinutes = 240;
  bool _packageEdited = false;
  bool get _packageMode => widget.findPackageMatches != null;
  String get _packageSize =>
      '$_cleanerCount ${_cleanerCount == 1 ? 'cleaner' : 'cleaners'} · ${_durationMinutes ~/ 60} hrs';
  List<EligibleProviderItem>? _eligible;
  List<AlternativeProviderTime> _alternatives = const [];
  bool _locationRequired = false;
  String? _areaName;
  EligibleProviderItem? _selectedProvider;
  DateTime? _searchedStart;
  DateTime? _searchedEnd;
  final TextEditingController _instructions = TextEditingController();
  final TextEditingController _additionalTasks = TextEditingController();
  String? _requestToken;
  bool _searching = false;
  bool _searchFailed = false;
  bool _confirmingAlternative = false;
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
    if (_packageMode && _serviceTypeId == null && result[1].isNotEmpty) {
      final standard = result[1]
          .where((s) => s['name'].toString().toLowerCase().contains('standard'))
          .firstOrNull;
      _serviceTypeId =
          (standard ?? result[1].first)['service_type_id'] as String;
    }
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
      if (_packageMode) {
        _packageEdited = true;
        _syncPackageEnd();
      }
      _requestVersion++;
      _eligible = null;
      _alternatives = const [];
      _locationRequired = false;
      _selectedProvider = null;
      _requestToken = null;
      _searchedStart = null;
      _searchedEnd = null;
      _message = null;
      _searchFailed = false;
    });
  }

  (int, int) get _unitWindow {
    final property =
        _properties.where((p) => p['property_id'] == _propertyId).firstOrNull;
    return (
      parseTimeSlot(property?['cleaning_window_start']?.toString()) ?? 0,
      parseTimeSlot(property?['cleaning_window_end']?.toString()) ?? 1439,
    );
  }

  void _syncPackageEnd() {
    final start = _start;
    final (first, last) = _unitWindow;
    if (start == null ||
        timeOfDayMinutes(start) < first ||
        timeOfDayMinutes(start) + _durationMinutes > last) {
      _start = null;
      _end = null;
      return;
    }
    final minute = timeOfDayMinutes(start) + _durationMinutes;
    _end = TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
  }

  bool _matchesPackage(EligibleProviderItem provider) =>
      provider.quoteBasis == 'package' &&
      provider.packageId?.isNotEmpty == true &&
      provider.cleanerCount == _cleanerCount &&
      provider.durationMinutes == _durationMinutes;

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
        ? windowEnd - (_packageMode ? _durationMinutes : 1)
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
      title: _packageMode
          ? 'Choose start time'
          : start
              ? 'Requested start time'
              : 'Requested end time',
      description: _packageMode
          ? '$_packageSize · Cleaning window ${timeSlotLabel(windowStart)}–${timeSlotLabel(windowEnd)} MYT. Provider availability is checked when you search.'
          : 'Within your unit’s cleaning window. Provider availability is checked when you search. MYT (UTC+8).',
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
      setState(() => _message = _packageMode
          ? 'Choose a unit, service, date and start time.'
          : 'Choose a unit, service, date and both times.');
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
    if (_packageMode) {
      final (first, last) = _unitWindow;
      if (timeOfDayMinutes(start) < first ||
          timeOfDayMinutes(end) > last ||
          endAt.difference(startAt).inMinutes != _durationMinutes) {
        setState(() => _message =
            'Choose a start time that fits your unit’s cleaning window.');
        return;
      }
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
      final result = _packageMode
          ? await widget.findPackageMatches!(
              propertyId: propertyId,
              serviceTypeId: serviceTypeId,
              start: startAt,
              end: endAt,
              cleanerCount: _cleanerCount)
          : widget.findMatches == null
              ? null
              : await widget.findMatches!(
                  propertyId: propertyId,
                  serviceTypeId: serviceTypeId,
                  start: startAt,
                  end: endAt);
      final found = result?.current ??
          await widget.findEligible(
            propertyId: propertyId,
            serviceTypeId: serviceTypeId,
            start: startAt,
            end: endAt,
          );
      if (!mounted || searchVersion != _requestVersion) return;
      setState(() {
        _eligible =
            _packageMode ? found.where(_matchesPackage).toList() : found;
        _alternatives =
            (result?.alternatives ?? const <AlternativeProviderTime>[])
                .where((offer) =>
                    !_packageMode ||
                    (_matchesPackage(offer.provider) &&
                        offer.end.difference(offer.start).inMinutes ==
                            _durationMinutes))
                .toList();
        _locationRequired = result?.locationRequired ?? false;
        _areaName = result?.areaName;
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
    if (_packageMode &&
        (widget.createPackagePending == null || !_matchesPackage(provider))) {
      setState(() => _message =
          'Package booking is unavailable. Refresh and check providers again.');
      return;
    }
    final token = _requestToken ?? BookingRequestToken.newV4();
    setState(() {
      _requestToken = token;
      _submitting = true;
      _verifyingSubmission = false;
      _message = null;
    });
    try {
      final instructions =
          bookingRequestInstructions(_instructions.text, _additionalTasks.text);
      if (_packageMode) {
        await widget.createPackagePending!(
          clientRequestId: token,
          providerId: provider.providerId,
          propertyId: propertyId,
          serviceTypeId: serviceTypeId,
          start: start,
          end: end,
          expectedAmount: provider.quotedAmount,
          expectedBasis: 'package',
          instructions: instructions,
          packageId: provider.packageId!,
        );
      } else {
        await widget.createPending(
          clientRequestId: token,
          providerId: provider.providerId,
          propertyId: propertyId,
          serviceTypeId: serviceTypeId,
          start: start,
          end: end,
          expectedAmount: provider.quotedAmount,
          expectedBasis: provider.quoteBasis,
          instructions: instructions,
        );
      }
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

  Future<void> _editRentalLocation() async {
    final id = _propertyId;
    if (id == null ||
        widget.loadServiceAreas == null ||
        widget.savePropertyLocation == null) return;
    try {
      final fresh = await widget.loadProperties();
      if (!mounted) return;
      final row = fresh.firstWhere((p) => p['property_id'] == id);
      await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (_) => RentalLocationEditor(
              location:
                  Map<String, dynamic>.from(row['location'] as Map? ?? {}),
              loadAreas: widget.loadServiceAreas!,
              onSave: (area, pin) => widget.savePropertyLocation!(
                  id, row['property_revision'] as int, area, pin)));
      if (mounted)
        _changed(() {
          _step = 0;
          _options = _loadOptions();
        });
    } catch (_) {
      if (mounted)
        setState(() => _message =
            'Could not open rental location. Check your connection and retry.');
    }
  }

  String _intervalLabel(DateTime start, DateTime end) {
    final a = start.toUtc().add(const Duration(hours: 8)),
        b = end.toUtc().add(const Duration(hours: 8));
    return '${DateFormat('EEE, d MMM yyyy').format(a)} · ${DateFormat('h:mm a').format(a)}–${DateFormat('h:mm a').format(b)} MYT';
  }

  Future<void> _useAlternative(AlternativeProviderTime offer) async {
    if (_packageMode &&
        (!_matchesPackage(offer.provider) ||
            offer.end.difference(offer.start).inMinutes != _durationMinutes))
      return;
    if (_searching ||
        _submitting ||
        _confirmingAlternative ||
        _searchedStart == null ||
        _searchedEnd == null) return;
    _confirmingAlternative = true;
    bool? agreed;
    try {
      agreed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: const Text('Change appointment time?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your requested time'),
              const SizedBox(height: 6),
              Text(_intervalLabel(_searchedStart!, _searchedEnd!)),
              const Divider(height: 28),
              const Text('New time'),
              const SizedBox(height: 6),
              Text(
                _intervalLabel(offer.start, offer.end),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Text(
                offer.provider.displayName?.trim().isNotEmpty == true
                    ? offer.provider.displayName!
                    : 'Cleaning provider',
              ),
              const SizedBox(height: 6),
              Text(
                'Total quote · RM ${offer.provider.quotedAmount.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 10),
              const Text('Availability and price will be checked again.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep my time'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Use time & review'),
            ),
          ],
        ),
      );
    } finally {
      _confirmingAlternative = false;
    }
    if (!mounted || agreed != true) return;
    final start = offer.start.toUtc().add(const Duration(hours: 8)),
        end = offer.end.toUtc().add(const Duration(hours: 8));
    _changed(() {
      _day = DateTime(start.year, start.month, start.day);
      _start = TimeOfDay(hour: start.hour, minute: start.minute);
      _end = TimeOfDay(hour: end.hour, minute: end.minute);
    });
    final version = _requestVersion;
    await _search();
    if (!mounted || version != _requestVersion || _searchFailed) return;
    final confirmed = _eligible
        ?.where((p) =>
            p.providerId == offer.provider.providerId &&
            (!_packageMode || p.packageId == offer.provider.packageId))
        .firstOrNull;
    setState(() {
      if (confirmed == null) {
        _message =
            'That alternative is no longer available. Review the latest providers or choose another time.';
      } else {
        _selectedProvider = confirmed;
        _step = 3;
        _message = null;
        _top();
      }
    });
  }

  String _timeLabel(TimeOfDay? time) => time == null
      ? 'Select time'
      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Widget _compactPackageForm(_RequestOptions options) {
    final property =
        options.properties.firstWhere((p) => p['property_id'] == _propertyId);
    final service = options.serviceTypes
        .where((s) => s['service_type_id'] == _serviceTypeId)
        .firstOrNull;
    final deep =
        service?['name'].toString().toLowerCase().contains('deep') == true;
    final hours = deep ? const [4, 6, 8] : const [2, 3, 4];
    final (first, last) = _unitWindow;
    final fitsWindow = last - first >= _durationMinutes;
    final colors = Theme.of(context).colorScheme;
    Widget field(String label, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            child
          ],
        );
    Widget pair(Widget left, Widget right, {bool crew = false}) =>
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (constraints.maxWidth < 280 * scale) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [left, const SizedBox(height: 12), right]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (crew)
                SizedBox(width: 112 * scale, child: left)
              else
                Expanded(child: left),
              const SizedBox(width: 10),
              Expanded(child: right),
            ]);
          },
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.apartment_outlined, size: 22),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '${workspaceText(property['unit_name'] as String)}, ${workspaceText(property['building_name'] as String)}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
              'Cleaning window · ${timeSlotLabel(first)}–${timeSlotLabel(last)} MYT',
              style: Theme.of(context).textTheme.bodySmall),
        ])),
      ]),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        key: const Key('request-service'),
        isExpanded: true,
        initialValue: _serviceTypeId,
        decoration: const InputDecoration(labelText: 'Service', isDense: true),
        items: options.serviceTypes
            .map((s) => DropdownMenuItem(
                  value: s['service_type_id'] as String,
                  child: Text(s['name'] as String,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (value) => _changed(() {
          _serviceTypeId = value;
          _durationMinutes = 240;
        }),
      ),
      const SizedBox(height: 16),
      pair(
        field(
            'Cleaners',
            DropdownButtonFormField<int>(
              key: const Key('request-cleaners'),
              initialValue: _cleanerCount,
              isExpanded: true,
              decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
              items: [
                for (var count = 1; count <= 4; count++)
                  DropdownMenuItem(
                      value: count,
                      child: Text(
                          '$count ${count == 1 ? 'cleaner' : 'cleaners'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis))
              ],
              onChanged: (value) {
                if (value != null) _changed(() => _cleanerCount = value);
              },
            )),
        field(
            'Duration',
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final hour in hours)
                ChoiceChip(
                  key: ValueKey('request-duration-$hour'),
                  label: Text('$hour hrs'),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                  showCheckmark: false,
                  selected: _durationMinutes == hour * 60,
                  onSelected: (_) =>
                      _changed(() => _durationMinutes = hour * 60),
                ),
            ])),
        crew: true,
      ),
      const SizedBox(height: 16),
      pair(
        field(
            'Date',
            OutlinedButton.icon(
              key: const Key('request-date'),
              onPressed: _pickDay,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(_day == null
                  ? 'Select date'
                  : DateFormat('d MMM yyyy').format(_day!)),
            )),
        field(
            'Start time · MYT',
            OutlinedButton.icon(
              key: const Key('request-start'),
              onPressed:
                  _day == null || !fitsWindow ? null : () => _pickTime(true),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
              icon: const Icon(Icons.schedule_outlined, size: 18),
              label: Text(_timeLabel(_start)),
            )),
      ),
      const SizedBox(height: 12),
      Semantics(
          liveRegion: true,
          child: Container(
            key: const Key('package-end-summary'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10)),
            child: Wrap(
                spacing: 14,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                      _end == null
                          ? 'End time calculated automatically'
                          : 'Ends at ${_timeLabel(_end)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(_packageSize),
                ]),
          )),
      if (!fitsWindow)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
              'This duration does not fit your unit’s cleaning window. Choose a shorter duration or another unit.'),
        ),
      if (_day == null)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Choose a date to select a start time.'),
        ),
      const SizedBox(height: 16),
      Text('Price shown after matching',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const Key('request-check-packages'),
        onPressed: _searching || !fitsWindow ? null : _search,
        icon: const Icon(Icons.search),
        label: Text(_searching ? 'Checking availability…' : 'Check providers'),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      dirty: () =>
          !_saved &&
          ((_packageMode ? _packageEdited : _serviceTypeId != null) ||
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
                        (_packageMode
                            ? const [
                                'Choose unit',
                                'Service & time',
                                'Choose provider',
                                'Review & send'
                              ]
                            : const [
                                'Unit & service',
                                'Date & time',
                                'Choose provider',
                                'Review & send'
                              ])[_step],
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
                      if (!_packageMode)
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              _changed(() => _serviceTypeId = value),
                        ),
                      if ((widget.findMatches != null || _packageMode) &&
                          _propertyId != null) ...[
                        const SizedBox(height: 12),
                        Text(
                            'Rental location: ${((_properties.firstWhere((p) => p['property_id'] == _propertyId)['location'] as Map?)?['area_name'] as String?) ?? 'Choose a rental service area'}'),
                        TextButton.icon(
                            onPressed: _editRentalLocation,
                            icon: const Icon(Icons.location_on_outlined),
                            label: const Text('Set rental location')),
                      ],
                      if (!_packageMode && _serviceTypeId != null) ...[
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
                                  (_packageMode || _serviceTypeId != null)) {
                                _step = 1;
                                _top();
                                _message = null;
                              }
                            });
                          },
                          child: Text(_packageMode
                              ? 'Continue to service & time'
                              : 'Continue to date & time')),
                    ],
                    if (_step == 1 && _packageMode)
                      _compactPackageForm(options),
                    if (_step == 1 && !_packageMode) ...[
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
                    if (_step == 2 && _eligible != null)
                      ..._providerResults(options),
                    if (_step == 3 && _selectedProvider != null)
                      _reviewCard(options),
                  ],
                ),
              );
            },
          ),
        ),
      ));

  void _changeRequestTime() {
    if (_searching || _submitting) return;
    setState(() {
      _step = 1;
      _message = null;
      _top();
    });
  }

  List<Widget> _providerResults(_RequestOptions options) {
    final hasMatches = _eligible!.isNotEmpty;
    return [
      const SizedBox(height: 18),
      _requestSummary(options),
      if (_locationRequired)
        ConnectedStatePanel(
          state: ConnectedViewState.empty,
          title: 'Set your rental location',
          message:
              'Choose an area to find providers who cover your rental unit.',
          actionLabel: 'Set rental location',
          onAction: _editRentalLocation,
        )
      else ...[
        if (hasMatches) ...[
          Text(
            'Available at your time · ${_eligible!.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text('Compare providers and choose one to review.'),
          ..._eligible!.map(_providerCard),
        ],
        if (_alternatives.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            hasMatches ? 'Other available times' : 'Try these available times',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          Text(_packageMode
              ? 'Same service · $_packageSize · Your area · Within 7 days'
              : 'Same service · Your area · Within 7 days'),
          ..._alternativeGroups(),
        ] else if (!hasMatches)
          ConnectedStatePanel(
            state: ConnectedViewState.empty,
            title: _packageMode
                ? 'No matching package'
                : widget.findMatches == null
                    ? 'No provider available for this time'
                    : 'No available times in the next 7 days',
            message: _packageMode
                ? 'Try another duration, crew size or date to check other packages.'
                : 'Choose another date to search again.',
          ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _searching || _submitting ? null : _changeRequestTime,
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Choose another date & time'),
        ),
      ],
    ];
  }

  Widget _requestSummary(_RequestOptions options) {
    final property = options.properties.firstWhere(
      (p) => p['property_id'] == _propertyId,
    );
    final service = options.serviceTypes.firstWhere(
      (p) => p['service_type_id'] == _serviceTypeId,
    );
    final noAvailability = !_locationRequired && _eligible!.isEmpty;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.apartment_outlined, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${workspaceText(property['unit_name'] as String)}, ${workspaceText(property['building_name'] as String)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${service['name']} · ${_areaName ?? ((property['location'] as Map?)?['area_name'] as String? ?? 'Rental area not set')}',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Your requested time'),
                    if (noAvailability)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'No availability',
                          style: TextStyle(color: colors.onSurface),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _intervalLabel(_searchedStart!, _searchedEnd!),
                  key: const Key('requested-time-summary'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (_packageMode) Text(_packageSize),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  DateTime _malaysiaDay(DateTime instant) {
    final local = instant.toUtc().add(const Duration(hours: 8));
    return DateTime.utc(local.year, local.month, local.day);
  }

  List<Widget> _alternativeGroups() {
    final sorted = [..._alternatives]
      ..sort((a, b) => a.start.compareTo(b.start));
    final groups = <DateTime, List<AlternativeProviderTime>>{};
    for (final offer in sorted) {
      groups.putIfAbsent(_malaysiaDay(offer.start), () => []).add(offer);
    }
    final requestedDay = _malaysiaDay(_searchedStart!);
    return [
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('EEE, d MMM yyyy').format(entry.key),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (entry.key.difference(requestedDay).inDays == 0)
                      const Text('Same day')
                    else if (entry.key.difference(requestedDay).inDays == 1)
                      const Text('Next day'),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final offer in entry.value) _alternativeCard(offer),
      ],
    ];
  }

  Widget _alternativeCard(AlternativeProviderTime offer) {
    final provider = offer.provider;
    final start = offer.start.toUtc().add(const Duration(hours: 8));
    final end = offer.end.toUtc().add(const Duration(hours: 8));
    final duration = offer.end.difference(offer.start).inMinutes;
    final durationLabel = duration % 60 == 0
        ? '${duration ~/ 60} hours'
        : '${duration ~/ 60}h ${duration % 60}m';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${DateFormat('h:mm a').format(start)}–${DateFormat('h:mm a').format(end)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  provider.displayName?.trim().isNotEmpty == true
                      ? provider.displayName!
                      : 'Cleaning provider',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'RM ${provider.quotedAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Serves ${_areaName ?? provider.serviceArea} · $durationLabel',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting || _searching
                    ? null
                    : () => _useAlternative(offer),
                label: const Text('Choose this time'),
                icon: const Icon(Icons.arrow_forward, size: 18),
                iconAlignment: IconAlignment.end,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerCard(EligibleProviderItem provider) {
    final rates = [
      if (provider.hourlyRate != null) 'RM ${provider.hourlyRate}/hour',
      if (provider.dailyRate != null) 'RM ${provider.dailyRate}/day',
    ].join(' · ');
    final selected = _selectedProvider?.providerId == provider.providerId;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                provider.displayName?.trim().isNotEmpty == true
                    ? provider.displayName!
                    : 'Eligible cleaning provider',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 5),
            Text(
                _areaName == null ? provider.serviceArea : 'Serves $_areaName'),
            if (provider.distanceKm != null)
              Text(
                  'Approx. ${provider.distanceKm!.toStringAsFixed(1)} km to your rental unit'),
            if (provider.bio?.isNotEmpty == true) Text(provider.bio!),
            const SizedBox(height: 7),
            if (provider.quoteBasis != 'package') Text(rates),
            if (provider.quoteBasis == 'package') ...[
              Text(_packageSize),
              if (provider.packageScope?.trim().isNotEmpty == true)
                Text(provider.packageScope!),
            ],
            const SizedBox(height: 7),
            Text(
              provider.quoteBasis == 'package'
                  ? 'Package total · RM ${provider.quotedAmount.toStringAsFixed(2)}'
                  : 'Quoted price · RM ${provider.quotedAmount.toStringAsFixed(2)} '
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
              onPressed: _submitting || _searching
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
            if (_packageMode) Text(_packageSize),
            if (provider.packageScope?.trim().isNotEmpty == true)
              Text('Package scope: ${provider.packageScope!}'),
            const SizedBox(height: 8),
            Text(
                'Total quoted amount: RM ${provider.quotedAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(provider.quoteBasis == 'package'
                ? 'Total session price for the selected crew and duration.'
                : provider.quoteBasis == 'daily'
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
