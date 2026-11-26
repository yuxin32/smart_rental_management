import '../presentation/workspace_text.dart';
import 'package:flutter/material.dart';
import '../services/backend/safe_diagnostics.dart';
import 'package:flutter/services.dart';

import '../services/backend/connected_failure_message.dart';
import '../models/demo_data.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../widgets/bedroom_count_field.dart';
import '../widgets/building_name_field.dart';
import '../widgets/time_slot_picker.dart';
import '../widgets/service_location_fields.dart';
import '../services/backend/service_location.dart';

/// Values collected for a real Owner property. Saving is delegated to the
/// connected workspace so this form never writes local preview data.
class ConnectedPropertyInput {
  const ConnectedPropertyInput({
    required this.unitName,
    required this.buildingName,
    required this.address,
    required this.bedrooms,
    required this.sizeSqft,
    required this.cleaningWindowStart,
    required this.cleaningWindowEnd,
    this.areaId,
    this.pinLink = '',
  });

  final String unitName;
  final String buildingName;
  final String address;
  final int bedrooms;
  final int sizeSqft;
  final String cleaningWindowStart;
  final String cleaningWindowEnd;
  final String? areaId;
  final String pinLink;
}

class ConnectedPropertyFormScreen extends StatefulWidget {
  const ConnectedPropertyFormScreen({
    super.key,
    required this.onSave,
    this.initial,
    this.canSave,
    this.loadBuildingOptions,
    this.loadServiceAreas,
  });

  final Future<void> Function(ConnectedPropertyInput input) onSave;
  final DemoProperty? initial;
  final Future<List<Map<String, dynamic>>> Function()? loadBuildingOptions;
  final bool Function()? canSave;
  final Future<List<ServiceAreaOption>> Function()? loadServiceAreas;

  @override
  State<ConnectedPropertyFormScreen> createState() =>
      _ConnectedPropertyFormScreenState();
}

class _ConnectedPropertyFormScreenState
    extends State<ConnectedPropertyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _unit = TextEditingController();
  final _building = TextEditingController();
  final _address = TextEditingController();
  final _bedrooms = TextEditingController();
  final _size = TextEditingController();
  final _pin = TextEditingController();
  Set<String> _areas = {};
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _saving = false;
  bool _needsVerification = false;
  String? _error;
  List<Map<String, dynamic>> _buildingOptions = const [];
  Future<List<Map<String, dynamic>>>? _buildingLoad;
  Future<List<Map<String, dynamic>>> _loadBuildingOptions() async {
    final rows = await (_buildingLoad ??= widget.loadBuildingOptions!());
    if (mounted) _buildingOptions = rows;
    return rows;
  }

  String _originalOrEdited(String value, String? original) =>
      original != null && value.trim() == workspaceText(original)
      ? original
      : value.trim();
  String get _buildingToSave {
    final original = widget.initial?.tower;
    if (original != null && _building.text.trim() == workspaceText(original))
      return original;
    for (final row in _buildingOptions) {
      final raw = row['building_name'] as String;
      if (normalizedBuildingName(workspaceText(raw)) ==
          normalizedBuildingName(_building.text))
        return raw;
    }
    return _building.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  void initState() {
    super.initState();
    _address.addListener(() {
      if (_pin.text.isNotEmpty) _pin.clear();
    });
    final value = widget.initial;
    if (value == null) return;
    _unit.text = workspaceText(value.unit);
    _building.text = workspaceText(value.tower);
    _address.text = workspaceText(value.address);
    _areas = {if (value.locationAreaId != null) value.locationAreaId!};
    _pin.text = value.locationPinLink;
    _bedrooms.text = '${value.bedrooms}';
    _size.text = '${value.sizeSqft}';
    _start = value.cleaningWindowStart;
    _end = value.cleaningWindowEnd;
  }

  @override
  void dispose() {
    _unit.dispose();
    _building.dispose();
    _address.dispose();
    _bedrooms.dispose();
    _size.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<TimeOfDay?> _pickTime({required bool start}) async {
    final selected = await showTimeSlotPicker(
      context: context,
      initialTime:
          (start ? _start : _end) ?? TimeOfDay(hour: start ? 8 : 18, minute: 0),
      title: start ? 'Cleaning window starts' : 'Cleaning window ends',
      description: 'Choose the permitted cleaning window. Malaysia time (MYT).',
      firstMinute: !start && _start != null ? _minutes(_start!) + 1 : 0,
      lastMinute: start ? 1438 : 1439,
    );
    if (!mounted || selected == null) return null;
    setState(() {
      if (start) {
        _start = selected;
        if (_end != null && _minutes(_end!) <= _minutes(selected)) _end = null;
      } else {
        _end = selected;
      }
      _error = null;
    });
    return selected;
  }

  int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;

  String _databaseTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (widget.canSave?.call() == false) {
      setState(
        () =>
            _error = 'Your session changed. Close this form and sign in again.',
      );
      return;
    }
    if (_saving || _needsVerification || !_formKey.currentState!.validate())
      return;
    if (widget.loadServiceAreas != null && _areas.isEmpty) {
      setState(() => _error = 'Choose a rental service area.');
      return;
    }
    if (_start == null || _end == null) return;
    if (_minutes(_end!) <= _minutes(_start!)) {
      setState(() => _error = 'The end time must be after the start time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var writeStarted = false;
    try {
      if (widget.loadBuildingOptions != null &&
          (widget.initial == null ||
              _building.text.trim() != workspaceText(widget.initial!.tower))) {
        await _loadBuildingOptions();
      }
      if (!mounted) return;
      if (widget.canSave?.call() == false) {
        setState(
          () => _error =
              'Your session changed. Close this form and sign in again.',
        );
        return;
      }
      writeStarted = true;
      await widget.onSave(
        ConnectedPropertyInput(
          areaId: _areas.firstOrNull,
          pinLink: _pin.text,
          unitName: _originalOrEdited(_unit.text, widget.initial?.unit),
          buildingName: _buildingToSave,
          address: _originalOrEdited(_address.text, widget.initial?.address),
          bedrooms: int.parse(_bedrooms.text),
          sizeSqft: int.parse(_size.text),
          cleaningWindowStart: _databaseTime(_start!),
          cleaningWindowEnd: _databaseTime(_end!),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              widget.initial == null
                  ? 'Rental unit added.'
                  : 'Rental unit changes saved.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!writeStarted) _buildingLoad = null;
      SafeDiagnostics.app.record(SafeOperation.propertySave, error);
      if (mounted) {
        setState(() {
          final rejected =
              error is PostgrestException &&
              const {'22023', '23514', '23505', '42501'}.contains(error.code);
          _needsVerification = writeStarted && !rejected;
          _error = !writeStarted
              ? 'Could not check saved building names. Check your connection and try again.'
              : error is PostgrestException && error.code == '40001'
              ? 'This property was changed elsewhere. Close this form and reload before editing.'
              : rejected
              ? 'Could not save. Check the details, duplicate unit name and cleaning window. Confirmed bookings must remain within the window.'
              : ConnectedFailureMessage.isConnectionFailure(error)
              ? 'Connection lost while saving. Your entries are kept. Check My properties before adding this unit again.'
              : 'We could not confirm whether this unit was saved. Your entries are kept. Check My properties before adding it again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _textField(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    String? hint,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        controller: controller,
        enabled: !_saving,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        inputFormatters: numeric
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        textCapitalization: numeric
            ? TextCapitalization.none
            : TextCapitalization.words,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3,
          floatingLabelBehavior: hint == null
              ? FloatingLabelBehavior.auto
              : FloatingLabelBehavior.always,
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty)
            return '$label is required';
          if (numeric && (int.tryParse(value) ?? 0) <= 0) {
            return 'Enter a positive number';
          }
          return null;
        },
      ),
    );
  }

  Widget _timeField(bool start) => FormField<TimeOfDay>(
    autovalidateMode: AutovalidateMode.onUserInteraction,
    key: ValueKey(start ? 'window-start' : 'window-end'),
    initialValue: start ? _start : _end,
    validator: (_) {
      final value = start ? _start : _end;
      if (value == null)
        return start ? 'Select a start time' : 'Select an end time';
      if (!start && _start != null && _minutes(value) <= _minutes(_start!))
        return 'End must be after start';
      return null;
    },
    builder: (field) {
      final value = start ? _start : _end;
      return Semantics(
        button: true,
        child: InkWell(
          onTap: _saving
              ? null
              : () async {
                  final selected = await _pickTime(start: start);
                  if (selected != null && mounted) field.didChange(selected);
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: start
                  ? 'Cleaning window starts *'
                  : 'Cleaning window ends *',
              errorText: field.errorText,
              suffixIcon: const Icon(Icons.schedule),
              enabled: !_saving,
            ),
            child: Text(value == null ? 'Select time' : _databaseTime(value)),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      dirty: () =>
          _areas.firstOrNull != widget.initial?.locationAreaId ||
          _pin.text.trim() != (widget.initial?.locationPinLink ?? '') ||
          _unit.text != workspaceText(widget.initial?.unit ?? '') ||
          _building.text != workspaceText(widget.initial?.tower ?? '') ||
          _address.text != workspaceText(widget.initial?.address ?? '') ||
          _bedrooms.text !=
              (widget.initial == null ? '' : '${widget.initial!.bedrooms}') ||
          _size.text !=
              (widget.initial == null ? '' : '${widget.initial!.sizeSqft}') ||
          _start != widget.initial?.cleaningWindowStart ||
          _end != widget.initial?.cleaningWindowEnd,
      busy: () => _saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.initial == null ? 'Add rental unit' : 'Edit rental unit',
          ),
        ),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Property details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text('This rental unit will be saved to your account.'),
                const SizedBox(height: 20),
                _textField(
                  'Unit / apartment number',
                  _unit,
                  hint: 'e.g. A-101 or 12-05',
                  helper: 'The unit or apartment number.',
                ),
                BuildingNameField(
                  controller: _building,
                  address: _address,
                  enabled: !_saving,
                  loadOptions: widget.loadBuildingOptions == null
                      ? null
                      : _loadBuildingOptions,
                ),
                _textField(
                  'Property address',
                  _address,
                  hint: 'e.g. 12 Jalan Example, Kuala Lumpur',
                  helper:
                      'The address the provider needs to find this property.',
                ),
                BedroomCountField(controller: _bedrooms, enabled: !_saving),
                if (widget.loadServiceAreas != null) ...[
                  const SizedBox(height: 16),
                  ServiceLocationFields(
                    loadAreas: widget.loadServiceAreas!,
                    selected: _areas,
                    onChanged: (v) => setState(() => _areas = v),
                    pinController: _pin,
                    enabled: !_saving,
                  ),
                ],
                const SizedBox(height: 14),
                _textField(
                  'Size (sqft)',
                  _size,
                  numeric: true,
                  hint: 'e.g. 980',
                  helper: 'Floor area in square feet (sqft).',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Permissible cleaning window',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Cleaning bookings must fit within this time range.',
                ),
                const Text(
                  'Both times are required · 24-hour format (HH:mm) · Malaysia time',
                ),
                const SizedBox(height: 12),
                _timeField(true),
                const SizedBox(height: 16),
                _timeField(false),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: _needsVerification
                  ? FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Check My properties'),
                    )
                  : FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _saving
                            ? 'Saving…'
                            : widget.initial == null
                            ? 'Add property'
                            : 'Save changes',
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
