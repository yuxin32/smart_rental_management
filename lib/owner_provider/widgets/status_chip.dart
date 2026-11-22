// lib/widgets/status_chip.dart
import 'package:flutter/material.dart';
import '../models/demo_data.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.onDark = false});
  final BookingStatus status;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final accent = onDark
        ? Colors.white
        : Theme.of(context).brightness == Brightness.dark
            ? Color.lerp(status.color, Colors.white, 0.42)!
            : status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            onDark ? Colors.white.withOpacity(0.16) : accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: onDark ? Colors.white38 : accent.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
                color: accent, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
