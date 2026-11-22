import 'package:flutter/material.dart';
import '../widgets/building_name_field.dart';

import '../models/demo_data.dart';
import '../services/property_store.dart';
import '../widgets/bedroom_count_field.dart';
import '../widgets/time_slot_picker.dart';

class PropertyFormScreen extends StatefulWidget {
  const PropertyFormScreen({
    super.key,
    required this.store,
    required this.bookings,
    this.initial,
  });

  final PropertyStore store;
  final Iterable<DemoBooking> bookings;
  final DemoProperty? initial;

  @override
  State<PropertyFormScreen> createState() => _PropertyFormScreenState();
}

class _PropertyFormScreenState extends State<PropertyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _unit;
  late final TextEditingController _tower;
  late final TextEditingController _address;
  late final TextEditingController _bedrooms;
  late final TextEditingController _sizeSqft;
  late TimeOfDay _windowStart;
  late TimeOfDay _windowEnd;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _unit = TextEditingController(text: initial?.unit ?? '');
    _tower = TextEditingController(text: initial?.tower ?? '');
    _address = TextEditingController(text: initial?.address ?? '');
    _bedrooms = TextEditingController(
        text: initial == null ? '' : '${initial.bedrooms}');
    _sizeSqft = TextEditingController(
        text: initial == null ? '' : '${initial.sizeSqft}');
    _windowStart =
        initial?.cleaningWindowStart ?? const TimeOfDay(hour: 8, minute: 0);
    _windowEnd =
        initial?.cleaningWindowEnd ?? const TimeOfDay(hour: 18, minute: 0);
  }

  @override
  void dispose() {
    _unit.dispose();
    _tower.dispose();
    _address.dispose();
    _bedrooms.dispose();
    _sizeSqft.dispose();
    super.dispose();
  }

  Future<void> _pickWindow({required bool start}) async {
    final picked = await showTimeSlotPicker(
      context: context,
      initialTime: start ? _windowStart : _windowEnd,
      title: start ? 'Cleaning window starts' : 'Cleaning window ends',
      firstMinute: start ? 0 : timeOfDayMinutes(_windowStart) + 1,
      lastMinute: start ? 1438 : 1439,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _windowStart = picked;
        if (timeOfDayMinutes(_windowEnd) <= timeOfDayMinutes(picked)) {
          final end = (timeOfDayMinutes(picked) + 30).clamp(0, 1439);
          _windowEnd = TimeOfDay(hour: end ~/ 60, minute: end % 60);
        }
      } else {
        _windowEnd = picked;
      }
      _error = null;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final bedrooms = int.parse(_bedrooms.text);
    final size = int.parse(_sizeSqft.text);
    final PropertySaveResult result;
    if (widget.initial == null) {
      result = widget.store.add(
        unit: _unit.text,
        tower: _tower.text,
        address: _address.text,
        bedrooms: bedrooms,
        sizeSqft: size,
        cleaningWindowStart: _windowStart,
        cleaningWindowEnd: _windowEnd,
      );
    } else {
      result = widget.store.update(
        widget.initial!.copyWith(
          unit: _unit.text.trim(),
          tower: _tower.text.trim(),
          address: _address.text.trim(),
          bedrooms: bedrooms,
          sizeSqft: size,
          cleaningWindowStart: _windowStart,
          cleaningWindowEnd: _windowEnd,
        ),
        bookings: widget.bookings,
      );
    }
    if (!result.saved) {
      setState(() => _error = result.message);
      return;
    }
    Navigator.of(context).pop(result.property);
  }

  Widget _field(String label, TextEditingController controller,
      {TextInputType? inputType,
      String? Function(String?)? validator,
      String? hint,
      String? helper}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: inputType,
        textCapitalization: inputType == TextInputType.number
            ? TextCapitalization.none
            : TextCapitalization.words,
        decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helper,
            helperMaxLines: 3,
            floatingLabelBehavior: hint == null
                ? FloatingLabelBehavior.auto
                : FloatingLabelBehavior.always),
        validator: validator ??
            (value) => value == null || value.trim().isEmpty
                ? '$label is required'
                : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      appBar:
          AppBar(title: Text(editing ? 'Edit rental unit' : 'Add rental unit')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Property details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            _field('Unit name', _unit,
                hint: 'e.g. A-12-03', helper: 'The unit or apartment number.'),
            BuildingNameField(
                controller: _tower,
                address: _address,
                options: widget.store.properties
                    .map((p) => <String, dynamic>{
                          'building_name': p.tower,
                          'address': p.address,
                        })
                    .toList()),
            _field('Property address', _address,
                hint: 'e.g. 12 Jalan Example, Kuala Lumpur',
                helper:
                    'The address the provider needs to find this property.'),
            BedroomCountField(controller: _bedrooms),
            const SizedBox(height: 14),
            _field('Size (sqft)', _sizeSqft,
                hint: 'e.g. 980',
                helper: 'Floor area in square feet (sqft).',
                inputType: TextInputType.number,
                validator: (value) => (int.tryParse(value ?? '') ?? 0) > 0
                    ? null
                    : 'Enter a positive size'),
            const SizedBox(height: 4),
            const Text(
              'Permissible cleaning window',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Booking eligibility and alternative windows must stay inside this interval.',
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickWindow(start: true),
                  icon: const Icon(Icons.schedule),
                  label: Text(
                      'From ${timeSlotLabel(timeOfDayMinutes(_windowStart))}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickWindow(start: false),
                  icon: const Icon(Icons.schedule),
                  label:
                      Text('To ${timeSlotLabel(timeOfDayMinutes(_windowEnd))}'),
                ),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (editing) ...[
              const SizedBox(height: 12),
              const Text(
                'A unit with existing bookings keeps its unit and building name so those bookings remain linked.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
          ]),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(editing ? 'Save changes' : 'Add property'),
          ),
        ),
      ),
    );
  }
}
