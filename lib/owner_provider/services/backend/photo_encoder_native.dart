import 'package:flutter/foundation.dart';
import 'evidence_photo_models.dart';

Future<PreparedEvidencePhoto> encodePhoto(
  Uint8List bytes,
  PreparedEvidencePhoto Function(Uint8List) worker,
) =>
    compute(worker, bytes, debugLabel: 'prepare-cleaning-photo');
