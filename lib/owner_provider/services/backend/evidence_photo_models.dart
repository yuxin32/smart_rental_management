import 'dart:typed_data';

class PhotoPreparationException implements Exception {
  const PhotoPreparationException(this.message);
  final String message;
}

class PreparedEvidencePhoto {
  PreparedEvidencePhoto({
    required Uint8List bytes,
    required this.inputBytes,
    required this.width,
    required this.height,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List bytes;
  final int inputBytes, width, height;
  String get description =>
      '$width × $height · ${(bytes.length / 1024).ceil()} KB';
}

abstract final class EvidencePhotoPolicy {
  static const maxInputBytes = 20 * 1024 * 1024;
  static const maxInputPixels = 24 * 1000 * 1000;
  static const maxInputEdge = 10000;
  static const maxOutputBytes = 1024 * 1024;
  static const maxOutputEdge = 1600;
}
