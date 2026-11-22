import '../presentation/workspace_text.dart';
import 'package:flutter/material.dart';

String normalizedBuildingName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// An editable combobox: suggestions are conveniences, never a closed list.
/// Callers provide only the signed-in owner's property projection.
class BuildingNameField extends StatefulWidget {
  const BuildingNameField(
      {super.key,
      required this.controller,
      required this.address,
      this.loadOptions,
      this.options = const [],
      this.enabled = true});
  final TextEditingController controller, address;
  final Future<List<Map<String, dynamic>>> Function()? loadOptions;
  final List<Map<String, dynamic>> options;
  final bool enabled;
  @override
  State<BuildingNameField> createState() => _BuildingNameFieldState();
}

class _BuildingNameFieldState extends State<BuildingNameField> {
  final focus = FocusNode();
  List<Map<String, dynamic>> rows = [];
  bool failed = false, expanded = false;
  void _changed() {
    if (mounted) setState(() {});
  }

  void _focusChanged() {
    if (!focus.hasFocus) expanded = false;
    _changed();
  }

  @override
  void initState() {
    super.initState();
    rows = widget.options;
    widget.controller.addListener(_changed);
    focus.addListener(_focusChanged);
    _load();
  }

  Future<void> _load() async {
    if (widget.loadOptions == null) return;
    try {
      final value = await widget.loadOptions!();
      if (mounted)
        setState(() {
          rows = value;
          failed = false;
        });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final name = workspaceText(row['building_name'] as String? ?? '');
      if (name.trim().isNotEmpty)
        names.putIfAbsent(normalizedBuildingName(name), () => row);
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: widget.controller,
            focusNode: focus,
            enabled: widget.enabled,
            onTap: () => setState(() => expanded = true),
            onEditingComplete: () {
              focus.unfocus();
              setState(() => expanded = false);
            },
            autovalidateMode: AutovalidateMode.onUserInteraction,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
                labelText: 'Building or tower',
                hintText: 'e.g. Menara Suria, Tower A',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                helperText:
                    'Choose a saved building or type a new one. Include the tower or block.',
                helperMaxLines: 3,
                suffixIcon: IconButton(
                    tooltip: 'Show saved buildings',
                    onPressed: widget.enabled
                        ? () {
                            setState(() => expanded = !expanded);
                            if (expanded) focus.requestFocus();
                          }
                        : null,
                    icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more))),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Building or tower is required'
                : null,
          ),
          if (expanded && widget.enabled)
            TextFieldTapRegion(
                child: Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12)),
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final entry in names.entries.where((e) => e.key
                        .contains(
                            normalizedBuildingName(widget.controller.text))))
                      ListTile(
                          leading: const Icon(Icons.apartment_outlined),
                          title: Text(workspaceText(
                              entry.value['building_name'] as String)),
                          onTap: () {
                            widget.controller.text = workspaceText(
                                    entry.value['building_name'] as String)
                                .trim();
                            if (widget.address.text.trim().isEmpty)
                              widget.address.text = workspaceText(
                                  entry.value['address'] as String? ?? '');
                            setState(() => expanded = false);
                            focus.unfocus();
                          }),
                    if (!names.keys.any((k) => k.contains(
                        normalizedBuildingName(widget.controller.text))))
                      Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(widget.controller.text.trim().isEmpty
                              ? 'No saved buildings yet. Type a new building name.'
                              : 'New building name · ${widget.controller.text.trim()}')),
                  ]),
            )),
          if (failed)
            Row(children: [
              const Expanded(
                  child: Text(
                      'Saved buildings could not load. You can still type a name.')),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ]),
        ]));
  }
}
