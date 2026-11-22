import 'package:flutter/material.dart';

import '../../../features/matching/domain/provider_matching.dart';
import '../../../models/demo_data.dart';

/// A request being prepared by the owner. It is not a persisted booking.
class CleaningRequestDraft {
  const CleaningRequestDraft({
    required this.property,
    required this.service,
    required this.requestedStart,
    required this.duration,
    required this.instructions,
  });

  final DemoProperty property;
  final ServiceTypeOption service;
  final DateTime requestedStart;
  final Duration duration;
  final String instructions;

  DateTime get requestedEnd => requestedStart.add(duration);

  CleaningRequestDraft at(DateTime start) => CleaningRequestDraft(
        property: property,
        service: service,
        requestedStart: start,
        duration: duration,
        instructions: instructions,
      );

  ProviderMatchRequest get matchRequest {
    final date = requestedStart;
    DateTime atTime(TimeOfDay time) =>
        DateTime(date.year, date.month, date.day, time.hour, time.minute);

    return ProviderMatchRequest(
      serviceType: service.id,
      requestedStart: requestedStart,
      requestedEnd: requestedEnd,
      rentalWindowStart: atTime(property.cleaningWindowStart),
      rentalWindowEnd: atTime(property.cleaningWindowEnd),
    );
  }
}

class SelectedCleaningRequest {
  const SelectedCleaningRequest({required this.draft, required this.provider});

  final CleaningRequestDraft draft;
  final DemoProvider provider;
}

/// Local-preview implementation of the report's dynamic alternative-window
/// calculation. The local demo uses editable weekly slots and blocked dates.
class AlternativeWindowService {
  const AlternativeWindowService();

  List<DateTime> generate({
    required CleaningRequestDraft draft,
    required Iterable<DemoProvider> providers,
    required Iterable<DemoBooking> bookings,
    DateTime? now,
    int limit = 5,
  }) {
    if (draft.duration <= Duration.zero || limit <= 0) return const [];

    final request = draft.matchRequest;
    final bookingList = bookings.toList(growable: false);
    final candidates = <DateTime>{};
    final currentTime = now ?? DateTime.now();

    for (final provider in providers) {
      if (!provider.serviceTypes.contains(draft.service.id)) {
        continue;
      }

      DateTime atMinute(int minute) => DateTime(
            draft.requestedStart.year,
            draft.requestedStart.month,
            draft.requestedStart.day,
            minute ~/ 60,
            minute % 60,
          );

      void consider(DateTime freeStart, DateTime freeEnd) {
        final start = _later(freeStart, currentTime);
        final lastStart = freeEnd.subtract(draft.duration);
        if (lastStart.isBefore(start)) return;
        final closestStart = _clamp(draft.requestedStart, start, lastStart);
        if (closestStart == draft.requestedStart) return;

        // Reapply all mandatory eligibility checks after changing the time.
        final revised = draft.at(closestStart);
        final result = const ProviderMatchingService().match(
          providers: [provider],
          request: revised.matchRequest,
          bookings: bookingList,
        );
        if (result.rankedProviders.isNotEmpty) candidates.add(closestStart);
      }

      for (final slot
          in provider.availabilitySchedule.slotsFor(draft.requestedStart)) {
        final availableStart = _later(
          request.rentalWindowStart,
          atMinute(slot.startMinute),
        );
        final availableEnd = _earlier(
          request.rentalWindowEnd,
          atMinute(slot.endMinute),
        );
        if (!availableEnd.isAfter(availableStart)) continue;

        final blocking = bookingList
            .where((booking) =>
                booking.providerName == provider.name &&
                booking.status.blocksProviderSlot &&
                booking.scheduledStart.isBefore(availableEnd) &&
                availableStart.isBefore(booking.scheduledEnd))
            .toList()
          ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

        var cursor = availableStart;
        for (final booked in blocking) {
          final blockedStart = _later(booked.scheduledStart, availableStart);
          final blockedEnd = _earlier(booked.scheduledEnd, availableEnd);
          if (blockedStart.isAfter(cursor)) consider(cursor, blockedStart);
          cursor = _later(cursor, blockedEnd);
          if (!availableEnd.isAfter(cursor)) break;
        }
        if (availableEnd.isAfter(cursor)) consider(cursor, availableEnd);
      }
    }

    final ranked = candidates.toList()
      ..sort((a, b) {
        final aDistance =
            a.difference(draft.requestedStart).inMilliseconds.abs();
        final bDistance =
            b.difference(draft.requestedStart).inMilliseconds.abs();
        final byDistance = aDistance.compareTo(bDistance);
        return byDistance != 0 ? byDistance : a.compareTo(b);
      });
    return List.unmodifiable(ranked.take(limit));
  }

  static DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  static DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static DateTime _clamp(DateTime value, DateTime start, DateTime end) =>
      value.isBefore(start) ? start : (value.isAfter(end) ? end : value);
}
