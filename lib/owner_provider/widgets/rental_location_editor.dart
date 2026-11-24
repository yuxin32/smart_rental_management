import 'package:flutter/material.dart';
import '../services/backend/service_location.dart';
import 'service_location_fields.dart';

class RentalLocationEditor extends StatefulWidget {
  const RentalLocationEditor(
      {super.key,
      required this.location,
      required this.loadAreas,
      required this.onSave});
  final Map<String, dynamic> location;
  final Future<List<ServiceAreaOption>> Function() loadAreas;
  final Future<void> Function(String area, String pin) onSave;
  @override
  State<RentalLocationEditor> createState() => _RentalLocationEditorState();
}

class _RentalLocationEditorState extends State<RentalLocationEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _pin;
  late Set<String> _areas;
  bool _saving = false, _uncertain = false;
  @override
  void initState() {
    super.initState();
    _pin = TextEditingController(
        text: widget.location['pin_link'] as String? ?? '');
    _areas = {
      if (widget.location['area_id'] is String)
        widget.location['area_id'] as String
    };
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        _uncertain ||
        !_form.currentState!.validate() ||
        _areas.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_areas.single, _pin.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _uncertain = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: SafeArea(
          child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
              child: Form(
                  key: _form,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Rental location',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        const Text(
                            'Choose the area where the rental unit is located. Your current phone location is not used.'),
                        const SizedBox(height: 18),
                        ServiceLocationFields(
                            loadAreas: widget.loadAreas,
                            selected: _areas,
                            onChanged: (v) => setState(() => _areas = v),
                            pinController: _pin,
                            enabled: !_saving && !_uncertain),
                        if (_uncertain)
                          const Padding(
                              padding: EdgeInsets.only(bottom: 14),
                              child: Text(
                                  'We could not confirm the save. Close and reopen this editor to reload the saved location before trying again.')),
                        SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                                onPressed: _saving || _uncertain ? null : _save,
                                child: Text(
                                    _saving ? 'Saving…' : 'Save location'))),
                        TextButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.pop(context, false),
                            child: const Text('Close')),
                      ])))));
}
