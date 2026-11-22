// lib/services/booking_store.dart
//
// In-memory booking repository used by the local preview. The formal data
// source will be Supabase, but the same lifecycle policy is shared by both.

import 'package:flutter/foundation.dart';

import '../features/bookings/domain/booking_status_change.dart';
import '../models/demo_data.dart';
import 'provider_store.dart';
import 'property_store.dart';

enum BookingAcceptanceFailure {
  bookingNotFound,
  invalidState,
  providerNotAssigned,
  propertyNotRegistered,
  providerUnavailable,
  rentalWindowIncompatible,
  slotConflict,
}

class BookingAcceptanceResult {
  const BookingAcceptanceResult.success()
      : accepted = true,
        failure = null;

  const BookingAcceptanceResult.failure(this.failure) : accepted = false;

  final bool accepted;
  final BookingAcceptanceFailure? failure;

  String get message => switch (failure) {
        BookingAcceptanceFailure.bookingNotFound => 'Booking not found.',
        BookingAcceptanceFailure.invalidState =>
          'Only a Pending request can be accepted.',
        BookingAcceptanceFailure.providerNotAssigned =>
          'A provider must be assigned before acceptance.',
        BookingAcceptanceFailure.propertyNotRegistered =>
          'The rental unit is no longer registered. The request remains Pending.',
        BookingAcceptanceFailure.providerUnavailable =>
          'The provider is no longer available for the full interval. The request remains Pending.',
        BookingAcceptanceFailure.rentalWindowIncompatible =>
          'The interval is outside the rental-unit cleaning window. The request remains Pending.',
        BookingAcceptanceFailure.slotConflict =>
          'The requested time is no longer available. The request remains Pending.',
        null => 'Booking accepted.',
      };
}

class BookingStore extends ChangeNotifier {
  BookingStore({
    ProviderStore? providerStore,
    PropertyStore? propertyStore,
    List<DemoBooking>? initialBookings,
  })  : _providerStore = providerStore,
        _propertyStore = propertyStore,
        _bookings = List.of(initialBookings ?? DemoBooking.all());

  final ProviderStore? _providerStore;
  final PropertyStore? _propertyStore;

  List<DemoBooking> _bookings;
  final Map<String, List<BookingStatusChange>> _history = {};
  int _localSequence = 0;
  List<DemoBooking> get bookings => List.unmodifiable(_bookings);

  /// Seeded demo bookings have no invented historical events. New requests
  /// and successful local transitions are recorded from this point onward.
  List<BookingStatusChange> historyFor(String bookingId) =>
      List.unmodifiable(_history[bookingId] ?? const <BookingStatusChange>[]);

  void _recordTransition(
    DemoBooking booking,
    BookingStatus? previousStatus,
    BookingStatus newStatus, {
    required String changedBy,
    String? reason,
  }) {
    _history.putIfAbsent(booking.id, () => []).add(BookingStatusChange(
          bookingId: booking.id,
          previousStatus: previousStatus,
          newStatus: newStatus,
          changedAt: DateTime.now(),
          changedBy: changedBy,
          reason: reason,
        ));
  }

  String? _lastUpdatedId;
  String? get lastUpdatedId => _lastUpdatedId;

  DemoBooking? byId(String id) {
    try {
      return _bookings.firstWhere((booking) => booking.id == id);
    } catch (_) {
      return null;
    }
  }

  List<DemoBooking> forProvider(String providerName) => _bookings
      .where((booking) => booking.providerName == providerName)
      .toList();

  List<DemoBooking> forProperty(String property) =>
      _bookings.where((booking) => booking.property == property).toList();

  DemoBooking add({
    required String property,
    required String serviceType,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    String? providerName,
    String? specialInstructions,
    bool isRecurring = false,
    int totalDays = 1,
  }) {
    final selectedProvider = _providerStore?.providers
        .where((provider) => provider.name == providerName)
        .firstOrNull;
    final newBooking = DemoBooking(
      id: _nextLocalId(),
      property: property,
      serviceType: serviceType,
      providerName: providerName,
      hourlyRateAtBooking: selectedProvider?.hourlyRate,
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      status: BookingStatus.pending,
      specialInstructions: specialInstructions,
      isRecurring: isRecurring,
      totalDays: totalDays,
    );
    _bookings = [newBooking, ..._bookings];
    _recordTransition(
      newBooking,
      null,
      BookingStatus.pending,
      changedBy: 'Property Owner',
    );
    _notifyUpdated(newBooking.id);
    return newBooking;
  }

  /// Performs the local equivalent of the transaction-safe acceptance check.
  /// The Supabase implementation will repeat this check and commit the status
  /// plus history record atomically on the server.
  BookingAcceptanceResult acceptPending(String id) {
    final booking = byId(id);
    if (booking == null) {
      return const BookingAcceptanceResult.failure(
        BookingAcceptanceFailure.bookingNotFound,
      );
    }
    if (booking.status != BookingStatus.pending) {
      return const BookingAcceptanceResult.failure(
        BookingAcceptanceFailure.invalidState,
      );
    }
    if (booking.providerName == null) {
      return const BookingAcceptanceResult.failure(
        BookingAcceptanceFailure.providerNotAssigned,
      );
    }
    if (_providerStore != null) {
      final assigned = _providerStore.providers
          .where((provider) => provider.name == booking.providerName)
          .firstOrNull;
      if (assigned == null ||
          !assigned.availabilitySchedule
              .covers(booking.scheduledStart, booking.scheduledEnd)) {
        return const BookingAcceptanceResult.failure(
          BookingAcceptanceFailure.providerUnavailable,
        );
      }
      final property = _propertyFor(booking.property);
      if (_propertyStore != null && property == null) {
        return const BookingAcceptanceResult.failure(
          BookingAcceptanceFailure.propertyNotRegistered,
        );
      }
      if (property != null) {
        final date = booking.scheduledStart;
        final windowStart = DateTime(
            date.year,
            date.month,
            date.day,
            property.cleaningWindowStart.hour,
            property.cleaningWindowStart.minute);
        final windowEnd = DateTime(date.year, date.month, date.day,
            property.cleaningWindowEnd.hour, property.cleaningWindowEnd.minute);
        if (booking.scheduledStart.isBefore(windowStart) ||
            booking.scheduledEnd.isAfter(windowEnd)) {
          return const BookingAcceptanceResult.failure(
            BookingAcceptanceFailure.rentalWindowIncompatible,
          );
        }
      }
    }
    if (_hasBlockingOverlap(booking)) {
      return const BookingAcceptanceResult.failure(
        BookingAcceptanceFailure.slotConflict,
      );
    }

    final accepted = _applyStatus(id, BookingStatus.accepted);
    return accepted
        ? const BookingAcceptanceResult.success()
        : const BookingAcceptanceResult.failure(
            BookingAcceptanceFailure.invalidState,
          );
  }

  bool _hasBlockingOverlap(DemoBooking candidate) => _bookings.any(
        (existing) =>
            existing.id != candidate.id &&
            existing.providerName == candidate.providerName &&
            existing.status.blocksProviderSlot &&
            candidate.scheduledStart.isBefore(existing.scheduledEnd) &&
            existing.scheduledStart.isBefore(candidate.scheduledEnd),
      );

  DemoProperty? _propertyFor(String display) =>
      _propertyStore?.byDisplay(display) ??
      DemoProperty.all.where((item) => item.display == display).firstOrNull;

  /// Applies the authoritative six-state lifecycle.
  bool updateStatus(String id, BookingStatus next) {
    if (next == BookingStatus.accepted) {
      return acceptPending(id).accepted;
    }
    // Cancellation requires an authorised actor and a recorded reason.
    if (next == BookingStatus.cancelled) return false;
    return _applyStatus(id, next);
  }

  bool cancelBooking(
    String id, {
    required BookingActor actor,
    required String reason,
  }) {
    final booking = byId(id);
    final cleanedReason = reason.trim();
    if (booking == null ||
        cleanedReason.isEmpty ||
        cleanedReason.length > 300 ||
        !BookingLifecycle.canCancel(booking.status, actor)) {
      return false;
    }
    final index = _bookings.indexWhere((item) => item.id == id);
    final now = DateTime.now();
    _bookings = List.of(_bookings)
      ..[index] = booking.copyWith(
        status: BookingStatus.cancelled,
        cancelledAt: now,
        cancellationReason: cleanedReason,
      );
    _recordTransition(
      booking,
      booking.status,
      BookingStatus.cancelled,
      changedBy: actor == BookingActor.owner
          ? 'Property Owner'
          : 'Cleaning Service Provider',
      reason: cleanedReason,
    );
    _notifyUpdated(id);
    return true;
  }

  bool _applyStatus(String id, BookingStatus next) {
    final index = _bookings.indexWhere((booking) => booking.id == id);
    if (index < 0) return false;

    final current = _bookings[index];
    if (!BookingLifecycle.canTransition(current.status, next)) return false;
    if (next == BookingStatus.completed && !current.hasCompletionEvidence) {
      return false;
    }

    final now = DateTime.now();
    final updated = current.copyWith(
      status: next,
      acceptedAt: next == BookingStatus.accepted ? now : current.acceptedAt,
      startedAt: next == BookingStatus.inProgress ? now : current.startedAt,
      completedAt: next == BookingStatus.completed ? now : current.completedAt,
      declinedAt: next == BookingStatus.declined ? now : current.declinedAt,
      cancelledAt: next == BookingStatus.cancelled ? now : current.cancelledAt,
    );

    final updatedBookings = List.of(_bookings)..[index] = updated;
    DemoBooking? nextOccurrence;

    // A recurring occurrence still requires provider acceptance. It therefore
    // creates a new Pending request rather than silently reserving a slot.
    if (next == BookingStatus.completed &&
        updated.isRecurring &&
        updated.recurrencePattern != null) {
      final nextStart =
          updated.recurrencePattern!.nextAfter(updated.scheduledEnd);
      final duration = updated.scheduledEnd.difference(updated.scheduledStart);
      nextOccurrence = DemoBooking(
        id: _nextLocalId(),
        property: updated.property,
        serviceType: updated.serviceType,
        providerName: updated.providerName,
        hourlyRateAtBooking: updated.hourlyRateAtBooking,
        scheduledStart: nextStart,
        scheduledEnd: nextStart.add(duration),
        status: BookingStatus.pending,
        specialInstructions: updated.specialInstructions,
        isRecurring: true,
        recurrencePattern: updated.recurrencePattern,
      );
      updatedBookings.insert(0, nextOccurrence);
    }

    _bookings = updatedBookings;
    _recordTransition(
      updated,
      current.status,
      next,
      changedBy: next == BookingStatus.cancelled
          ? 'Property Owner'
          : 'Cleaning Service Provider',
    );
    if (nextOccurrence != null) {
      _recordTransition(
        nextOccurrence,
        null,
        BookingStatus.pending,
        changedBy: 'System',
      );
    }
    _notifyUpdated(id);
    return true;
  }

  void update(DemoBooking updated) {
    final index = _bookings.indexWhere((booking) => booking.id == updated.id);
    if (index < 0) return;
    if (updated.status != _bookings[index].status) return;
    _bookings = List.of(_bookings)..[index] = updated;
    _notifyUpdated(updated.id);
  }

  /// A provider may decline only an incoming Pending request.
  bool declineBooking(String id, {String? reason}) {
    final booking = byId(id);
    if (booking == null || booking.status != BookingStatus.pending) {
      return false;
    }

    final index = _bookings.indexWhere((item) => item.id == id);
    _bookings = List.of(_bookings)
      ..[index] = booking.copyWith(
        status: BookingStatus.declined,
        declineReason: (reason?.trim().isEmpty ?? true) ? null : reason!.trim(),
        declinedAt: DateTime.now(),
      );
    _recordTransition(
      booking,
      BookingStatus.pending,
      BookingStatus.declined,
      changedBy: 'Cleaning Service Provider',
      reason: reason?.trim().isEmpty ?? true ? null : reason!.trim(),
    );
    _notifyUpdated(id);
    return true;
  }

  /// Revises date, time, and instructions without creating a Rescheduled
  /// lifecycle state. Only Pending requests can be revised.
  DemoBooking? revisePendingBooking({
    required String id,
    required DateTime newStart,
    required DateTime newEnd,
    String? specialInstructions,
  }) {
    final error = revisionError(id: id, newStart: newStart, newEnd: newEnd);
    if (error != null) return null;
    final booking = byId(id)!;

    final index = _bookings.indexWhere((item) => item.id == id);
    final updated = booking.copyWith(
      scheduledStart: newStart,
      scheduledEnd: newEnd,
      specialInstructions: specialInstructions,
    );
    _bookings = List.of(_bookings)..[index] = updated;
    _notifyUpdated(id);
    return updated;
  }

  /// Checks a Pending revision against the latest local property, provider
  /// declaration and blocking bookings. The backend must repeat this check.
  String? revisionError({
    required String id,
    required DateTime newStart,
    required DateTime newEnd,
    DateTime? now,
  }) {
    final booking = byId(id);
    if (booking == null || booking.status != BookingStatus.pending) {
      return 'Only a Pending request can be edited.';
    }
    if (!newEnd.isAfter(newStart) || !newStart.isAfter(now ?? DateTime.now())) {
      return 'Choose a valid future date, time and duration.';
    }
    final property = _propertyFor(booking.property);
    if (_propertyStore != null && property == null) {
      return 'The rental unit is no longer registered.';
    }
    if (property != null) {
      final windowStart = DateTime(
        newStart.year,
        newStart.month,
        newStart.day,
        property.cleaningWindowStart.hour,
        property.cleaningWindowStart.minute,
      );
      final windowEnd = DateTime(
        newStart.year,
        newStart.month,
        newStart.day,
        property.cleaningWindowEnd.hour,
        property.cleaningWindowEnd.minute,
      );
      if (newStart.isBefore(windowStart) || newEnd.isAfter(windowEnd)) {
        return 'The requested interval is outside the rental-unit cleaning window.';
      }
    }
    if (_providerStore != null) {
      final provider = _providerStore.providers
          .where((item) => item.name == booking.providerName)
          .firstOrNull;
      if (provider == null ||
          !provider.availabilitySchedule.covers(newStart, newEnd)) {
        return 'The assigned provider is unavailable for the full interval.';
      }
    }
    final candidate = booking.copyWith(
      scheduledStart: newStart,
      scheduledEnd: newEnd,
    );
    if (_hasBlockingOverlap(candidate)) {
      return 'The interval conflicts with an Accepted or In Progress booking.';
    }
    return null;
  }

  void setProofPath(String id, {required bool isBefore, required String path}) {
    final booking = byId(id);
    if (booking == null) return;
    update(
      isBefore
          ? booking.copyWith(beforeImagePath: path)
          : booking.copyWith(afterImagePath: path),
    );
  }

  void setCompletionRemarks(String id, String remarks) {
    final booking = byId(id);
    if (booking == null) return;
    update(booking.copyWith(completionRemarks: remarks.trim()));
  }

  void rateCompleted(String id, {required int rating, String? comment}) {
    assert(rating >= 1 && rating <= 5, 'rating must be 1..5');
    final booking = byId(id);
    if (booking == null || booking.status != BookingStatus.completed) return;
    update(
      booking.copyWith(
        ownerRating: rating,
        ownerRatingComment: comment,
      ),
    );
  }

  static bool canTransitionTo(BookingStatus from, BookingStatus to) =>
      BookingLifecycle.canTransition(from, to);

  @visibleForTesting
  static bool debugIsValidTransition(BookingStatus from, BookingStatus to) =>
      BookingLifecycle.canTransition(from, to);

  void _notifyUpdated(String id) {
    _lastUpdatedId = id;
    notifyListeners();
  }

  String _nextLocalId() {
    _localSequence += 1;
    return 'b-local-${DateTime.now().microsecondsSinceEpoch}-$_localSequence';
  }
}
