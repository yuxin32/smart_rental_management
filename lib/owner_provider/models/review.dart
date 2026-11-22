// lib/models/review.dart

class Review {
  const Review({
    required this.id,
    required this.bookingId,
    required this.providerName,
    required this.ownerName,
    required this.rating,
    required this.comment,
    required this.tags,
    required this.timestamp,
  });
  final String id;
  final String bookingId;
  final String providerName;
  final String ownerName;
  final int rating; // 1..5
  final String comment;
  final List<String> tags;
  final DateTime timestamp;

  Review copyWith({String? comment, int? rating, List<String>? tags}) {
    return Review(
      id: id, bookingId: bookingId,
      providerName: providerName, ownerName: ownerName,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      tags: tags ?? this.tags,
      timestamp: timestamp,
    );
  }
}
