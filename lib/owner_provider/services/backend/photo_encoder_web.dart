import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'evidence_photo_models.dart';

/// Browser-native decoding/resizing/JPEG encoding, not a Dart pixel loop on the
/// UI isolate. Selected bytes stay local; temporary object URLs are revoked.
Future<PreparedEvidencePhoto> encodePhoto(
  Uint8List bytes,
  PreparedEvidencePhoto Function(Uint8List) _,
) async {
  final url = web.URL.createObjectURL(web.Blob(<JSAny>[bytes.toJS].toJS));
  final image = web.HTMLImageElement();
  final canvas = web.HTMLCanvasElement();
  final loaded = Completer<void>();
  final loadSubscription = image.onLoad.listen((_) {
    if (!loaded.isCompleted) loaded.complete();
  });
  final errorSubscription = image.onError.listen((_) {
    if (!loaded.isCompleted) {
      loaded.completeError(
        const PhotoPreparationException(
          'This image could not be read. Choose another photo.',
        ),
      );
    }
  });
  try {
    image.src = url;
    await loaded.future.timeout(const Duration(seconds: 20));
    final width = image.naturalWidth, height = image.naturalHeight;
    if (width <= 0 ||
        height <= 0 ||
        width * height > EvidencePhotoPolicy.maxInputPixels ||
        math.max(width, height) > EvidencePhotoPolicy.maxInputEdge) {
      throw const PhotoPreparationException(
        'This image is too large or could not be read. Choose another photo.',
      );
    }
    void draw(int edge) {
      final ratio = math.min(1.0, edge / math.max(width, height));
      canvas.width = math.max(1, (width * ratio).round());
      canvas.height = math.max(1, (height * ratio).round());
      final context = canvas.context2D;
      context.fillStyle = '#ffffff'.toJS;
      context.fillRect(0, 0, canvas.width.toDouble(), canvas.height.toDouble());
      context.drawImage(
        image,
        0,
        0,
        canvas.width.toDouble(),
        canvas.height.toDouble(),
      );
    }

    Future<Uint8List> encode(double quality) async {
      final result = Completer<web.Blob>();
      canvas.toBlob(
        (web.Blob? blob) {
          if (result.isCompleted) return;
          if (blob == null) {
            result.completeError(
              const PhotoPreparationException(
                'This browser could not prepare the photo. Choose another JPEG or PNG.',
              ),
            );
          } else {
            result.complete(blob);
          }
        }.toJS,
        'image/jpeg',
        quality.toJS,
      );
      final blob = await result.future.timeout(const Duration(seconds: 20));
      final buffer = (await blob.arrayBuffer().toDart).toDart;
      final output = Uint8List.fromList(buffer.asUint8List());
      if (output.length < 3 ||
          output[0] != 255 ||
          output[1] != 216 ||
          output[2] != 255) {
        throw const PhotoPreparationException(
          'This browser did not produce a valid JPEG photo.',
        );
      }
      return output;
    }

    PreparedEvidencePhoto prepared(Uint8List output) => PreparedEvidencePhoto(
          bytes: output,
          inputBytes: bytes.length,
          width: canvas.width,
          height: canvas.height,
        );
    draw(EvidencePhotoPolicy.maxOutputEdge);
    for (final quality in [0.82, 0.74, 0.66]) {
      final output = await encode(quality);
      if (output.length <= EvidencePhotoPolicy.maxOutputBytes) {
        return prepared(output);
      }
    }
    if (math.max(canvas.width, canvas.height) > 1280) {
      draw(1280);
      final output = await encode(0.74);
      if (output.length <= EvidencePhotoPolicy.maxOutputBytes) {
        return prepared(output);
      }
    }
    throw const PhotoPreparationException(
      'This photo is still too large after optimisation. Choose a smaller copy.',
    );
  } finally {
    await loadSubscription.cancel();
    await errorSubscription.cancel();
    image.src = '';
    canvas.width = 1;
    canvas.height = 1;
    web.URL.revokeObjectURL(url);
  }
}
