import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../features/bookings/domain/cleaning_request_flow.dart';
import '../main.dart';
import '../models/demo_data.dart';
import '../theme/app_theme.dart';
import '../widgets/time_slot_picker.dart';
import 'provider_results_screen.dart';

/// The owner prepares a request here. Nothing is recorded until a provider is
/// selected and the owner confirms the review screen.
class NewBookingScreen extends StatefulWidget {
  const NewBookingScreen({super.key, this.onSubmit});

  final void Function(DemoBooking booking)? onSubmit;

  @override
  State<NewBookingScreen> createState() => _NewBookingScreenState();
}

class _NewBookingScreenState extends State<NewBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _instructions = TextEditingController();
  DemoProperty? _property;
  ServiceTypeOption? _service;
  DateTime? _date;
  TimeOfDay? _time;
  int? _durationHours;
  bool _finding = false;

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimeSlotPicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
      title: 'Requested start time',
      description:
          'Choose a requested time. Eligibility is checked when you search. MYT (UTC+8).',
      firstMinute: _property == null
          ? 0
          : timeOfDayMinutes(_property!.cleaningWindowStart),
      lastMinute: _property == null
          ? 1439
          : timeOfDayMinutes(_property!.cleaningWindowEnd) -
              (_durationHours ?? 1) * 60,
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _findProviders() async {
    if (_finding || !_formKey.currentState!.validate()) return;
    if (_date == null || _time == null) {
      _showError('Please choose a preferred date and time.');
      return;
    }

    final start = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );
    if (!start.isAfter(DateTime.now())) {
      _showError('Please choose a future date and time.');
      return;
    }

    final draft = CleaningRequestDraft(
      property: _property!,
      service: _service!,
      requestedStart: start,
      duration: Duration(hours: _durationHours!),
      instructions: _instructions.text.trim(),
    );

    setState(() => _finding = true);
    final selection = await Navigator.of(context).push<SelectedCleaningRequest>(
      MaterialPageRoute(
        builder: (_) => ProviderResultsScreen(draft: draft),
      ),
    );
    if (!mounted) return;
    setState(() => _finding = false);
    if (selection == null) return;
    if (!selection.draft.requestedStart.isAfter(DateTime.now())) {
      _showError('Please choose a future date and time.');
      return;
    }

    // Revalidate at submission as well as on the review screen. Pending does
    // not reserve the slot; acceptance has a separate protected recheck.
    final app = AppProviders.of(context);
    final eligible = app.providerStore.matchProviders(
      request: selection.draft.matchRequest,
      bookings: app.bookingStore.bookings,
    );
    if (!eligible.rankedProviders.any((p) => p.id == selection.provider.id)) {
      _showError('That provider or time is no longer available. Try again.');
      return;
    }

    final saved = app.bookingStore.add(
      property: selection.draft.property.display,
      serviceType: selection.draft.service.label,
      scheduledStart: selection.draft.requestedStart,
      scheduledEnd: selection.draft.requestedEnd,
      providerName: selection.provider.name,
      specialInstructions: selection.draft.instructions,
    );
    widget.onSubmit?.call(saved);
    Navigator.of(context).pop(saved);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final properties = AppProviders.of(context).propertyStore.properties;
    final selectedDate =
        _date == null ? null : DateFormat('d MMM y').format(_date!);

    return Scaffold(
      appBar: AppBar(title: const Text('Request cleaning service')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _section(
              title: 'Rental unit',
              subtitle: 'Choose a unit registered to your Owner account.',
              child: DropdownButtonFormField<DemoProperty>(
                value: _property,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Property'),
                items: [
                  for (final property in properties)
                    DropdownMenuItem(
                      value: property,
                      child: Text(property.display),
                    ),
                ],
                onChanged: (value) => setState(() => _property = value),
                validator: (value) =>
                    value == null ? 'Select a rental unit' : null,
              ),
            ),
            if (_property != null) ...[
              const SizedBox(height: 8),
              Text(
                'Cleaning window: ${_formatTime(_property!.cleaningWindowStart)}–${_formatTime(_property!.cleaningWindowEnd)}',
                style: TextStyle(fontSize: 12, color: sem.textSecondary),
              ),
            ],
            const SizedBox(height: 22),
            _section(
              title: 'Cleaning service',
              subtitle: 'The duration is checked for the whole appointment.',
              child: Column(
                children: [
                  DropdownButtonFormField<ServiceTypeOption>(
                    value: _service,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Service type'),
                    items: [
                      for (final service in ServiceTypeOption.all)
                        DropdownMenuItem(
                          value: service,
                          child: Text(service.label),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _service = value;
                      _durationHours = value?.durationHours;
                    }),
                    validator: (value) =>
                        value == null ? 'Select a service type' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _durationHours,
                    decoration: const InputDecoration(labelText: 'Duration'),
                    items: [
                      for (var hours = 1; hours <= 8; hours++)
                        DropdownMenuItem(
                          value: hours,
                          child: Text('$hours hour${hours == 1 ? '' : 's'}'),
                        ),
                    ],
                    onChanged: _service == null
                        ? null
                        : (value) => setState(() => _durationHours = value),
                    validator: (value) =>
                        value == null ? 'Select a duration' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _section(
              title: 'Preferred appointment',
              subtitle:
                  'If this interval is unavailable, we will show feasible alternatives.',
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(selectedDate ?? 'Choose date'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(
                          _time == null ? 'Choose time' : _formatTime(_time!)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _section(
              title: 'Cleaning instructions',
              subtitle: 'Tell the provider what is required at this unit.',
              child: TextFormField(
                controller: _instructions,
                maxLength: 300,
                minLines: 3,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Instructions',
                  hintText: 'e.g. Focus on the kitchen and both bathrooms',
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter cleaning instructions'
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryBorder),
              ),
              child: const Text(
                'Next, review eligible providers and choose one. No booking is created until you confirm. A submitted request remains Pending until the provider accepts it.',
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: FilledButton.icon(
            onPressed: _finding ? null : _findProviders,
            icon: const Icon(Icons.person_search_outlined),
            label: Text(_finding ? 'Checking…' : 'Find suitable providers'),
          ),
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final sem = SemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: sem.textPrimary,
            )),
        const SizedBox(height: 3),
        Text(subtitle,
            style: TextStyle(fontSize: 12, color: sem.textSecondary)),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
