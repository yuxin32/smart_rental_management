import 'package:flutter/material.dart';
import '../services/backend/service_location.dart';

/// Single source for Owner area selection and Provider coverage selection.
class ServiceLocationFields extends StatefulWidget {
  const ServiceLocationFields(
      {super.key,
      required this.loadAreas,
      required this.selected,
      required this.onChanged,
      required this.pinController,
      this.beforePin,
      this.compact = false,
      this.multiple = false,
      this.enabled = true});
  final Future<List<ServiceAreaOption>> Function() loadAreas;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final TextEditingController pinController;
  final bool multiple, enabled;

  /// An optional related field between coverage selection and the map pin.
  final Widget? beforePin;
  final bool compact;
  @override
  State<ServiceLocationFields> createState() => _ServiceLocationFieldsState();
}

class _ServiceLocationFieldsState extends State<ServiceLocationFields> {
  late Future<List<ServiceAreaOption>> _areas;
  @override
  void initState() {
    super.initState();
    _areas = widget.loadAreas();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FutureBuilder<List<ServiceAreaOption>>(
            future: _areas,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return TextButton.icon(
                    onPressed: () =>
                        setState(() => _areas = widget.loadAreas()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Could not load service areas. Retry'));
              if (!snapshot.hasData)
                return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Loading service areas…'));
              final areas = snapshot.data!;
              if (!widget.multiple)
                return DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: widget.selected.isNotEmpty &&
                            areas.any((a) => a.id == widget.selected.first)
                        ? widget.selected.first
                        : null,
                    decoration: const InputDecoration(
                        labelText: 'Rental service area',
                        helperText:
                            'Choose the most specific supported area for this rental unit.',
                        helperMaxLines: 3),
                    items: areas
                        .map((a) => DropdownMenuItem(
                            value: a.id,
                            child:
                                Text(a.name, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    validator: (v) =>
                        v == null ? 'Choose a rental service area.' : null,
                    onChanged: widget.enabled
                        ? (v) {
                            if (v != null) widget.onChanged({v});
                          }
                        : null);
              return FormField<Set<String>>(
                  initialValue: widget.selected,
                  validator: (_) => widget.selected.isEmpty
                      ? 'Select at least one service area.'
                      : null,
                  builder: (field) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!widget.compact) ...[
                              const Text('Service coverage',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                            ],
                            Text(widget.compact
                                ? 'Choose the areas you serve.'
                                : 'Select the areas you serve. A city-wide area includes its listed neighbourhoods.'),
                            LayoutBuilder(
                                builder: (context, constraints) => Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: areas
                                        .map((a) => ConstrainedBox(
                                            constraints: BoxConstraints(
                                                maxWidth: constraints.maxWidth),
                                            child: FilterChip(
                                                label: Text(a.name),
                                                labelStyle: widget.compact
                                                    ? Theme.of(context)
                                                        .chipTheme
                                                        .labelStyle
                                                        ?.copyWith(
                                                            fontFamily: Theme
                                                                    .of(context)
                                                                .textTheme
                                                                .bodyMedium
                                                                ?.fontFamily)
                                                    : null,
                                                selected: widget.selected
                                                    .contains(a.id),
                                                onSelected: widget.enabled
                                                    ? (checked) {
                                                        final next = {
                                                          ...widget.selected
                                                        };
                                                        checked
                                                            ? next.add(a.id)
                                                            : next.remove(a.id);
                                                        widget.onChanged(next);
                                                        field.didChange(next);
                                                      }
                                                    : null)))
                                        .toList())),
                            if (field.hasError)
                              Text(field.errorText!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error)),
                          ]));
            }),
        const SizedBox(height: 16),
        if (widget.beforePin != null) ...[
          widget.beforePin!,
          const SizedBox(height: 16),
        ],
        TextFormField(
            controller: widget.pinController,
            enabled: widget.enabled,
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: validateMapPin,
            maxLength: 2048,
            decoration: InputDecoration(
                labelText: widget.multiple
                    ? widget.compact
                        ? 'Starting map pin (optional)'
                        : 'Private starting pin link (optional)'
                    : 'Rental map pin link (optional)',
                hintText: widget.compact
                    ? 'https://www.google.com/maps?q=3.18,101.70'
                    : 'Full Google Maps link to a selected pin',
                helperText: widget.multiple
                    ? widget.compact
                        ? 'Private · used for approximate distance. Leave empty to match by service area only.'
                        : 'Your pin stays private. Owners see only approximate distance. Leave empty to show your service areas only.'
                    : 'Add a selected map pin to enable approximate distance. A street address alone is not converted into coordinates.',
                helperMaxLines: 4,
                counterText: '')),
        const SizedBox(height: 14),
      ]);
}
