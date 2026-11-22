import 'package:flutter/material.dart';
import '../services/backend/booking_rate_limit.dart';

class RateLimitNotice extends StatelessWidget {
  const RateLimitNotice({super.key, required this.limit});
  final ServerActionLimit limit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final message = limit.action == BookingLimitedAction.message;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(16),),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.hourglass_top_rounded,
              color: colors.onSecondaryContainer, size: 22,),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(message ? 'Sending paused' : 'Photo uploads paused',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colors.onSecondaryContainer,),),
                const SizedBox(height: 4),
                Text(
                    'Please wait about ${limit.waitLabel} before trying again. '
                    '${message ? 'Your draft is kept.' : 'Your selected photo is kept; you do not need to choose it again.'}',
                    style: TextStyle(
                        color: colors.onSecondaryContainer, height: 1.4,),),
              ],),),
        ],),
      ),
    );
  }
}
