import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Cache-built list children are NOT evidence of visibility. Check painted
/// geometry against the actual scrolling viewport after the frame instead.
class VisibleMessageReceipt extends SingleChildRenderObjectWidget {
  const VisibleMessageReceipt(
      {super.key, required this.onVisible, required super.child});
  final VoidCallback onVisible;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _VisibleReceipt(onVisible);
  @override
  void updateRenderObject(
      BuildContext context, covariant _VisibleReceipt renderObject) {
    renderObject.onVisible = onVisible;
    renderObject.markNeedsPaint();
  }
}

class _VisibleReceipt extends RenderProxyBox {
  _VisibleReceipt(this.onVisible);
  VoidCallback onVisible;
  bool _scheduled = false;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!attached || !hasSize) return;
      final viewport = RenderAbstractViewport.maybeOf(this);
      if (viewport == null || viewport is! RenderBox) return;
      final box = viewport as RenderBox;
      if (!box.attached || !box.hasSize) return;
      final mine = MatrixUtils.transformRect(getTransformTo(null), paintBounds);
      final window =
          MatrixUtils.transformRect(box.getTransformTo(null), box.paintBounds);
      final visible = mine.intersect(window);
      if (visible.width > 0 && visible.height >= 8) onVisible();
    });
  }
}
