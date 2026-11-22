/// Authoritative booking lifecycle defined by the final FYP report.
///
/// Normal path:
/// Pending -> Accepted -> In Progress -> Completed
///
/// Alternative terminal paths:
/// Pending -> Declined
/// Pending -> Cancelled
/// Accepted -> Cancelled (before work starts, with a reason)
enum BookingStatus {
  pending,
  accepted,
  inProgress,
  completed,
  declined,
  cancelled,
}

enum BookingActor { owner, provider }

extension BookingStatusX on BookingStatus {
  String get label => switch (this) {
        BookingStatus.pending => 'Pending',
        BookingStatus.accepted => 'Accepted',
        BookingStatus.inProgress => 'In Progress',
        BookingStatus.completed => 'Completed',
        BookingStatus.declined => 'Declined',
        BookingStatus.cancelled => 'Cancelled',
      };

  bool get isTerminal => switch (this) {
        BookingStatus.completed ||
        BookingStatus.declined ||
        BookingStatus.cancelled =>
          true,
        _ => false,
      };

  /// Only confirmed, unfinished work reserves provider capacity.
  bool get blocksProviderSlot =>
      this == BookingStatus.accepted || this == BookingStatus.inProgress;
}

/// Single authoritative transition policy for every application layer.
abstract final class BookingLifecycle {
  static const Map<BookingStatus, Set<BookingStatus>> permittedTransitions = {
    BookingStatus.pending: {
      BookingStatus.accepted,
      BookingStatus.declined,
      BookingStatus.cancelled,
    },
    BookingStatus.accepted: {
      BookingStatus.inProgress,
      BookingStatus.cancelled,
    },
    BookingStatus.inProgress: {BookingStatus.completed},
    BookingStatus.completed: {},
    BookingStatus.declined: {},
    BookingStatus.cancelled: {},
  };

  static bool canTransition(BookingStatus from, BookingStatus to) =>
      permittedTransitions[from]!.contains(to);

  static bool canCancel(BookingStatus status, BookingActor actor) =>
      (status == BookingStatus.pending && actor == BookingActor.owner) ||
      status == BookingStatus.accepted;
}
