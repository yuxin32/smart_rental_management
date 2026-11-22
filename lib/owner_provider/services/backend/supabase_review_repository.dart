import 'package:supabase_flutter/supabase_flutter.dart';
import 'session_snapshot_cache.dart';

class BookingReviewRecord {
  const BookingReviewRecord({
    required this.bookingId,
    required this.rating,
    this.comment,
  });

  final String bookingId;
  final int rating;
  final String? comment;

  factory BookingReviewRecord.fromRow(Map<String, dynamic> row) =>
      BookingReviewRecord(
        bookingId: row['booking_id'] as String,
        rating: row['rating'] as int,
        comment: row['comment'] as String?,
      );
}

class SupabaseReviewRepository {
  const SupabaseReviewRepository(this.client, {this.snapshots});
  final SessionSnapshotCache? snapshots;

  final SupabaseClient client;

  Future<BookingReviewRecord?> forBooking(String bookingId) async {
    final row = await client
        .from('booking_review')
        .select('booking_id,rating,comment')
        .eq('booking_id', bookingId)
        .maybeSingle();
    return row == null ? null : BookingReviewRecord.fromRow(row);
  }

  Future<BookingReviewRecord> save(
    String bookingId,
    int rating,
    String? comment,
  ) async {
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'Must be 1 to 5.');
    }
    final trimmed = comment?.trim();
    if (trimmed != null && trimmed.length > 300) {
      throw ArgumentError.value(comment, 'comment', 'Maximum 300 characters.');
    }
    Future<dynamic> write() async =>
        await client.rpc('save_booking_review', params: {
          'p_booking_id': bookingId,
          'p_rating': rating,
          'p_comment': trimmed?.isEmpty == true ? null : trimmed,
        });
    final result = await (snapshots?.write(write) ?? write());
    return BookingReviewRecord.fromRow(
        Map<String, dynamic>.from(result as Map));
  }
}
