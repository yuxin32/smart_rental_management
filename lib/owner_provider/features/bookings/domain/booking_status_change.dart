import 'booking_status.dart';

/// A recorded lifecycle transition, separate from the booking's current state.
/// Server-backed records will use the authenticated user's ID and server time.
class BookingStatusChange {
  const BookingStatusChange({
    required this.bookingId,
    required this.previousStatus,
    required this.newStatus,
    required this.changedAt,
    required this.changedBy,
    this.reason,
  });

  final String bookingId;
  final BookingStatus? previousStatus;
  final BookingStatus newStatus;
  final DateTime changedAt;
  final String changedBy;
  final String? reason;
}
