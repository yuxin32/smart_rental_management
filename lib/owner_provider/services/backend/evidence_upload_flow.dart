import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum EvidenceKind { before, after }

class EvidenceUploadRejected implements Exception {
  const EvidenceUploadRejected(this.reason);
  final String reason;
}

/// One immutable photo selection. Keep its ID and bytes for every retry.
class EvidencePhotoUpload {
  EvidencePhotoUpload({
    required this.kind,
    required Uint8List bytes,
    String? id,
    this.expectedPreviousPath,
  })  : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
        id = id ?? newId();

  final EvidenceKind kind;
  final Uint8List bytes;
  final String id;
  final String? expectedPreviousPath;
  static const maxBytes = 5 * 1024 * 1024;

  String get extension {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('Use a JPEG or PNG image up to 5 MB.');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) return 'jpg';
    const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (bytes.length >= png.length &&
        List.generate(png.length, (i) => bytes[i] == png[i]).every((v) => v)) {
      return 'png';
    }
    throw ArgumentError('Only JPEG or PNG is accepted.');
  }

  String get contentType => extension == 'jpg' ? 'image/jpeg' : 'image/png';
  String get digest => sha256.convert(bytes).toString();
  String pathFor(String bookingId) => '$bookingId/${kind.name}_$id.$extension';

  static String newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// Testable orchestration. The server, not the device, confirms existence,
/// attachment, competing edits and deletion eligibility.
class EvidenceUploadFlow {
  const EvidenceUploadFlow({
    required this.begin,
    required this.put,
    required this.attach,
  });
  final Future<Map<String, dynamic>> Function(EvidencePhotoUpload) begin;
  final Future<void> Function(String, EvidencePhotoUpload) put;
  final Future<Map<String, dynamic>> Function(String) attach;

  Future<String> run(String bookingId, EvidencePhotoUpload photo) async {
    final expectedPath = photo.pathFor(bookingId); // validates before any call
    final ticket = await begin(photo);
    if (ticket['path'] != expectedPath ||
        !['pending', 'attached'].contains(ticket['state'])) {
      throw EvidenceUploadRejected(
        ticket['state'] as String? ?? 'invalid_ticket',
      );
    }
    if (ticket['state'] == 'attached') return expectedPath;
    if (ticket['uploaded'] != true) {
      try {
        await put(expectedPath, photo);
      } on EvidenceUploadRejected {
        rethrow; // A definitive server rejection must never fall through.
      } catch (_) {
        // A lost validation response may still have stored/attested the
        // canonical object. The attach RPC decides; never overwrite it.
      }
    }
    final result = await attach(photo.id);
    if (result['attached'] != true || result['path'] != expectedPath) {
      throw EvidenceUploadRejected(
        result['reason'] as String? ?? 'upload_not_confirmed',
      );
    }
    return expectedPath;
  }
}
