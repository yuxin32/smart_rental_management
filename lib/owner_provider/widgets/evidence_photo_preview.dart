import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Keep upload selections immutable, but give browser codecs a native byte
/// array. Reuse that copy across rebuilds so the image cache can reuse its key.
class EvidencePhotoPreview extends StatefulWidget {
  const EvidencePhotoPreview({
    super.key,
    required this.bytes,
    required this.cacheWidth,
    required this.errorBuilder,
  });

  final Uint8List bytes;
  final int cacheWidth;
  final ImageErrorWidgetBuilder errorBuilder;

  @override
  State<EvidencePhotoPreview> createState() => _EvidencePhotoPreviewState();
}

class _EvidencePhotoPreviewState extends State<EvidencePhotoPreview> {
  late Uint8List _displayBytes;

  void _bindBytes() =>
      _displayBytes = kIsWeb ? Uint8List.fromList(widget.bytes) : widget.bytes;

  @override
  void initState() {
    super.initState();
    _bindBytes();
  }

  @override
  void didUpdateWidget(EvidencePhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.bytes, oldWidget.bytes)) _bindBytes();
  }

  @override
  Widget build(BuildContext context) => Image.memory(
        _displayBytes,
        height: 160,
        width: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: widget.cacheWidth,
        errorBuilder: widget.errorBuilder,
      );
}
