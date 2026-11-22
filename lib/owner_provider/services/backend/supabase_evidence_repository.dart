import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'evidence_upload_flow.dart';
import 'authenticated_memory_cache.dart';
import 'booking_rate_limit.dart';
export 'evidence_upload_flow.dart';

/// Private JPEG/PNG images of at most 5 MB. Bucket RLS is the authority for
/// assigned-provider uploads and participant-only reads.
class SupabaseEvidenceRepository {
  const SupabaseEvidenceRepository(this.client, {this.cache});
  final SupabaseClient client;
  final AuthenticatedMemoryCache? cache;

  static const bucket = 'cleaning-evidence';
  static const maxBytes = EvidencePhotoUpload.maxBytes;

  Future<BookingEvidenceRecord?> forBooking(String bookingId) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw const CacheSessionChanged();
    cache?.bindSession(userId);
    final generation = cache?.generation;
    final row = await client
        .from('booking_evidence')
        .select('booking_id,before_path,after_path,completion_remarks')
        .eq('booking_id', bookingId)
        .maybeSingle();
    if (client.auth.currentUser?.id != userId ||
        cache?.generation != generation) {
      throw const CacheSessionChanged();
    }
    final record = row == null ? null : BookingEvidenceRecord.fromMap(row);
    final current = {record?.beforePath, record?.afterPath};
    cache?.evictWhere(
      (key) =>
          key.startsWith('photo:$bookingId/') &&
          !current.contains(key.substring('photo:'.length)),
    );
    return record;
  }

  Future<String> upload({
    required String bookingId,
    required EvidenceKind kind,
    required Uint8List bytes,
    required String uploadId,
    required String? expectedPreviousPath,
  }) async {
    final photo = EvidencePhotoUpload(
      kind: kind,
      bytes: bytes,
      id: uploadId,
      expectedPreviousPath: expectedPreviousPath,
    );
    return withServerRateLimit(
      BookingLimitedAction.evidence,
      () => EvidenceUploadFlow(
        begin: (photo) async => Map<String, dynamic>.from(
          await client.rpc(
            'begin_evidence_upload',
            params: {
              'p_booking_id': bookingId,
              'p_upload_id': photo.id,
              'p_kind': kind.name,
              'p_extension': photo.extension,
              'p_byte_size': photo.bytes.length,
              'p_sha256': photo.digest,
              'p_expected_previous_path': photo.expectedPreviousPath,
            },
          ) as Map,
        ),
        put: (path, photo) async {
          try {
            final response = await client.functions.invoke(
              'evidence-validate',
              body: photo.bytes,
              headers: {
                'Content-Type': 'application/octet-stream',
                'x-booking-id': bookingId,
                'x-upload-id': photo.id,
              },
            );
            if (response.data is! Map ||
                response.data['verified'] != true ||
                response.data['path'] != path) {
              throw StateError('Photo validation was not confirmed.');
            }
          } on FunctionException catch (error) {
            final code = error.details is Map ? error.details['code'] : null;
            if (([413, 422].contains(error.status) &&
                    ['PHOTO_REJECTED', 'NEW_PHOTO_REQUIRED'].contains(code)) ||
                (error.status == 409 && code == 'UPLOAD_CLOSED')) {
              throw EvidenceUploadRejected(
                code == 'UPLOAD_CLOSED'
                    ? 'expired_or_closed'
                    : 'photo_rejected',
              );
            }
            rethrow; // Busy/network/unknown errors remain retryable.
          }
        },
        attach: (id) async => Map<String, dynamic>.from(
          await client.rpc(
            'attach_evidence_upload',
            params: {'p_booking_id': bookingId, 'p_upload_id': id},
          ) as Map,
        ),
      ).run(bookingId, photo),
    );
  }

  Future<void> saveRemarks(String bookingId, String remarks) async {
    final value = remarks.trim();
    if (value.length > 1000) throw ArgumentError('Use up to 1,000 characters.');
    await client.rpc(
      'save_evidence_remarks',
      params: {
        'p_booking_id': bookingId,
        'p_remarks': value,
      },
    );
  }

  Future<void> removePhoto(
      String bookingId, EvidenceKind kind, String expectedPath) async {
    final actor = client.auth.currentUser?.id;
    if (actor == null) throw const CacheSessionChanged();
    final result = Map<String, dynamic>.from(
        await client.rpc('remove_evidence_photo', params: {
      'p_booking_id': bookingId,
      'p_kind': kind.name,
      'p_expected_path': expectedPath,
    }) as Map);
    if (client.auth.currentUser?.id != actor) throw const CacheSessionChanged();
    if (result['removed'] != true) {
      throw EvidencePhotoRemovalRejected(
          result['reason'] as String? ?? 'unknown');
    }
    if (result['path'] != expectedPath)
      throw const FormatException('Unexpected photo removal result');
    cache?.evict('photo:$expectedPath');
    // Physical deletion is retried separately after the pointer is detached.
  }

  /// Only server-tombstoned unused objects can be removed. Storage API, never
  /// SQL DELETE, removes the actual bytes. At most 20 objects per pass.
  Future<bool> cleanup(String bookingId) async {
    final rows = List<Map<String, dynamic>>.from(
      await client.rpc(
        'claim_evidence_cleanup',
        params: {'p_booking_id': bookingId},
      ) as List,
    );
    var complete = rows.length < 20;
    for (final row in rows) {
      final path = row['object_path'] as String;
      await client.storage.from(bucket).remove([path]);
      final removed = await client.rpc(
        'finish_evidence_cleanup',
        params: {
          'p_booking_id': bookingId,
          'p_path': path,
        },
      );
      if (removed != true) complete = false;
    }
    return complete;
  }

  Future<Uint8List> download(String path) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw const CacheSessionChanged();
    final separator = path.indexOf('/');
    if (separator <= 0) throw ArgumentError('Invalid evidence path.');
    BookingEvidenceRecord? record;
    try {
      record = await forBooking(path.substring(0, separator));
    } catch (_) {
      cache?.evict('photo:$path');
      rethrow;
    }
    if (client.auth.currentUser?.id != userId) {
      throw const CacheSessionChanged();
    }
    // A cache hit is never evidence of permission. Recheck current participant
    // access and the live photo pointer before returning any private bytes.
    if (record == null ||
        (record.beforePath != path && record.afterPath != path)) {
      cache?.evict('photo:$path');
      throw StateError('This photo is not available in the current booking.');
    }
    Future<Uint8List> fetch() async {
      final bytes = await client.storage.from(bucket).download(path);
      if (client.auth.currentUser?.id != userId) {
        throw const CacheSessionChanged();
      }
      if (bytes.isEmpty || bytes.length > maxBytes) {
        throw StateError('Photo exceeds the download limit.');
      }
      return Uint8List.fromList(bytes).asUnmodifiableView();
    }

    if (cache == null) return fetch();
    return cache!.read(
      key: 'photo:$path',
      ttl: const Duration(minutes: 2),
      sizeOf: (bytes) => bytes.length,
      load: fetch,
    );
  }
}

class EvidencePhotoRemovalRejected implements Exception {
  const EvidencePhotoRemovalRejected(this.reason);
  final String reason;
}

class BookingEvidenceRecord {
  const BookingEvidenceRecord({
    required this.bookingId,
    this.beforePath,
    this.afterPath,
    required this.remarks,
  });

  final String bookingId;
  final String? beforePath;
  final String? afterPath;
  final String remarks;

  factory BookingEvidenceRecord.fromMap(Map<String, dynamic> row) {
    return BookingEvidenceRecord(
      bookingId: row['booking_id'] as String,
      beforePath: row['before_path'] as String?,
      afterPath: row['after_path'] as String?,
      remarks: row['completion_remarks'] as String? ?? '',
    );
  }
}
