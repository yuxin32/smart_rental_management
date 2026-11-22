import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Extra tasks stay requests for discussion, not an accepted change of scope
/// or a change to the server's saved quote. The original notes remain intact.
String bookingRequestInstructions(String instructions, String additionalTasks) {
  final notes = instructions.trim();
  final tasks = additionalTasks.trim();
  if (tasks.isEmpty) return notes;
  return [
    if (notes.isNotEmpty) notes,
    'Additional tasks to discuss (not included in the quote):\n$tasks',
  ].join('\n\n');
}

class CleaningServiceScope extends StatelessWidget {
  const CleaningServiceScope({super.key, this.description});

  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context);
    final details = description?.trim() ?? '';
    return Container(
      decoration: BoxDecoration(
        color: colors.primarySurface,
        border: Border.all(color: colors.primaryBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text('Service scope',
            style: TextStyle(
                color: colors.textPrimary, fontWeight: FontWeight.w700)),
        subtitle: const Text('What is included and how to request extras'),
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                details.isEmpty
                    ? 'Confirm what is included'
                    : 'Service description',
                style: TextStyle(
                    color: colors.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                details.isEmpty
                    ? 'A detailed task list has not been provided for this service. Confirm specific tasks with your provider before work starts.'
                    : details,
                style: TextStyle(color: colors.textSecondary, height: 1.5)),
            const SizedBox(height: 12),
            Text('Outside this service',
                style: TextStyle(
                    color: colors.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                'Extra tasks are not automatically included. Use Additional tasks to discuss below when reviewing your request. Agree on any changes with your provider before work starts; a new quote may be needed.',
                style: TextStyle(color: colors.textSecondary, height: 1.5)),
          ])
        ],
      ),
    );
  }
}
