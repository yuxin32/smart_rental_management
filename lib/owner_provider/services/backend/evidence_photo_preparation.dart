import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'evidence_photo_models.dart';
import 'photo_encoder_native.dart'
    if (dart.library.js_interop) 'photo_encoder_web.dart' as encoder;
export 'evidence_photo_models.dart';

bool _preparingPhoto = false;

img.Decoder _decoder(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > EvidencePhotoPolicy.maxInputBytes) {
    throw const PhotoPreparationException(
      'Choose a JPEG or PNG image up to 20 MB.',
    );
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return img.JpegDecoder(maxPixels: EvidencePhotoPolicy.maxInputPixels);
  }
  const png = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length >= 8 &&
      List.generate(8, (i) => bytes[i] == png[i]).every((v) => v)) {
    return img.PngDecoder(maxPixels: EvidencePhotoPolicy.maxInputPixels);
  }
  throw const PhotoPreparationException(
    'Choose a JPEG or PNG photo. Export HEIC or other formats as JPEG first.',
  );
}

img.DecodeInfo _inspect(img.Decoder decoder, Uint8List bytes) {
  final info = decoder.startDecode(bytes);
  if (info == null || info.width <= 0 || info.height <= 0) {
    throw const PhotoPreparationException(
      'This image could not be read. Choose another photo.',
    );
  }
  if (info.width * info.height > EvidencePhotoPolicy.maxInputPixels ||
      math.max(info.width, info.height) > EvidencePhotoPolicy.maxInputEdge) {
    throw const PhotoPreparationException(
      'This photo has too many pixels. Choose a smaller copy (up to 24 megapixels).',
    );
  }
  if (info.numFrames > 1) {
    throw const PhotoPreparationException(
      'Choose a still photo, not an animated image.',
    );
  }
  return info;
}

/// Native: expensive work uses an isolate. Web uses native canvas codecs.
/// One expensive preparation runs at a time, even when a previous route closes.
Future<PreparedEvidencePhoto> prepareEvidencePhoto(Uint8List bytes) async {
  if (_preparingPhoto) {
    throw const PhotoPreparationException(
      'Another photo is being prepared. Wait a moment and try again.',
    );
  }
  _preparingPhoto = true;
  try {
    final info = _inspect(_decoder(bytes), bytes);
    if (!kIsWeb && info.width * info.height <= 256 * 256) {
      return prepareEvidencePhotoSync(bytes);
    }
    return await encoder.encodePhoto(bytes, prepareEvidencePhotoSync);
  } on PhotoPreparationException {
    rethrow;
  } catch (_) {
    throw const PhotoPreparationException(
      'This image could not be processed. Choose a different JPEG or PNG photo.',
    );
  } finally {
    _preparingPhoto = false;
  }
}

/// Decodes actual pixels, normalizes orientation, strips metadata by drawing
/// onto a fresh RGB canvas, and re-encodes a bounded immutable upload candidate.
PreparedEvidencePhoto prepareEvidencePhotoSync(Uint8List bytes) {
  try {
    var decoder = _decoder(bytes);
    final info = _inspect(decoder, bytes);
    if (decoder is img.JpegDecoder) {
      var scale = 1;
      while (scale < 8 &&
          math.max(info.width, info.height) / (scale * 2) >=
              EvidencePhotoPolicy.maxOutputEdge) {
        scale *= 2;
      }
      decoder = img.JpegDecoder(
        maxPixels: EvidencePhotoPolicy.maxInputPixels,
        scale: scale,
      );
      _inspect(decoder, bytes);
    }
    var image = decoder.decodeFrame(0);
    if (image == null) {
      throw const PhotoPreparationException(
        'This image is incomplete or damaged. Choose another photo.',
      );
    }
    // The current JPEG decoder already bakes orientation. PNG EXIF may still
    // carry it, so only bake when a non-default orientation actually remains.
    if (image.hasExif &&
        image.exif.imageIfd.hasOrientation &&
        image.exif.imageIfd.orientation != 1) {
      image = img.bakeOrientation(image);
    }
    final edge = math.max(image.width, image.height);
    if (edge > EvidencePhotoPolicy.maxOutputEdge) {
      image = img.copyResize(
        image,
        width: math.max(
          1,
          (image.width * EvidencePhotoPolicy.maxOutputEdge / edge).round(),
        ),
        height: math.max(
          1,
          (image.height * EvidencePhotoPolicy.maxOutputEdge / edge).round(),
        ),
        interpolation: img.Interpolation.average,
      );
    }
    var clean =
        img.Image(width: image.width, height: image.height, numChannels: 3);
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, image);
    // No EXIF/GPS, comments, thumbnails or source ICC/text chunks are copied.
    for (final quality in [82, 74, 66]) {
      final output =
          img.encodeJpg(clean, quality: quality, chroma: img.JpegChroma.yuv420);
      if (output.length <= EvidencePhotoPolicy.maxOutputBytes) {
        return PreparedEvidencePhoto(
          bytes: output,
          inputBytes: bytes.length,
          width: clean.width,
          height: clean.height,
        );
      }
    }
    if (math.max(clean.width, clean.height) > 1280) {
      final ratio = 1280 / math.max(clean.width, clean.height);
      clean = img.copyResize(
        clean,
        width: math.max(1, (clean.width * ratio).round()),
        height: math.max(1, (clean.height * ratio).round()),
        interpolation: img.Interpolation.average,
      );
      final output =
          img.encodeJpg(clean, quality: 74, chroma: img.JpegChroma.yuv420);
      if (output.length <= EvidencePhotoPolicy.maxOutputBytes) {
        return PreparedEvidencePhoto(
          bytes: output,
          inputBytes: bytes.length,
          width: clean.width,
          height: clean.height,
        );
      }
    }
    throw const PhotoPreparationException(
      'This photo is still too large after optimisation. Choose a smaller copy.',
    );
  } on PhotoPreparationException {
    rethrow;
  } catch (_) {
    throw const PhotoPreparationException(
      'This image is incomplete or damaged. Choose another JPEG or PNG photo.',
    );
  }
}
