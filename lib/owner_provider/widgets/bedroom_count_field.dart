import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Common values stay one tap away, while larger existing properties retain
/// their exact count. The connected database accepts 1 through 100 bedrooms.
class BedroomCountField extends StatefulWidget {
  const BedroomCountField(
      {super.key, required this.controller, this.enabled = true});
  final TextEditingController controller;
  final bool enabled;
  @override
  State<BedroomCountField> createState() => _BedroomCountFieldState();
}

class _BedroomCountFieldState extends State<BedroomCountField> {
  String? selected;
  @override
  void initState() {
    super.initState();
    final number = int.tryParse(widget.controller.text);
    selected = number == null
        ? null
        : number >= 1 && number <= 6
            ? '$number'
            : 'other';
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          key: const Key('property-bedrooms'),
          value: selected,
          isExpanded: true,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: const InputDecoration(
              labelText: 'Bedrooms',
              hintText: 'Select number of bedrooms',
              floatingLabelBehavior: FloatingLabelBehavior.always),
          items: [
            for (var n = 1; n <= 6; n++)
              DropdownMenuItem(
                  value: '$n',
                  child: Text('$n ${n == 1 ? 'bedroom' : 'bedrooms'}')),
            const DropdownMenuItem(value: 'other', child: Text('Other (7–100)'))
          ],
          validator: (v) => v == null ? 'Select the number of bedrooms' : null,
          onChanged: !widget.enabled
              ? null
              : (v) => setState(() {
                    if (v == 'other') {
                      if (selected != 'other') widget.controller.clear();
                    } else {
                      widget.controller.text = v ?? '';
                    }
                    selected = v;
                  }),
        ),
        if (selected == 'other') ...[
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('property-bedrooms-other'),
            controller: widget.controller,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 3,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
                labelText: 'Number of bedrooms',
                hintText: 'e.g. 8',
                helperText: 'Enter a whole number from 7 to 100.'),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n != null && n >= 7 && n <= 100
                  ? null
                  : 'Enter a number from 7 to 100';
            },
          ),
        ],
      ]);
}
