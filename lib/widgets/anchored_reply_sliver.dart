import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Compensates for a streaming reply growing at the start of a reversed
/// viewport. Unlike the estimated total extent of a lazy list, this sliver's
/// extent is exact, even while the reply is off screen.
class AnchoredReplySliver extends SingleChildRenderObjectWidget {
  const AnchoredReplySliver({
    super.key,
    required this.revision,
    required this.preservePosition,
    required super.child,
  });
  final int revision;
  final bool preservePosition;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderAnchoredReplySliver(revision, preservePosition);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderAnchoredReplySliver renderObject,
  ) {
    renderObject.update(revision, preservePosition);
  }
}

class RenderAnchoredReplySliver extends RenderProxySliver {
  RenderAnchoredReplySliver(this._revision, this._preservePosition);
  int _revision;
  bool _preservePosition;
  int? _laidOutRevision;
  double? _previousExtent;

  void update(int revision, bool preservePosition) {
    _revision = revision;
    _preservePosition = preservePosition;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    final extent = geometry!.scrollExtent;
    final previous = _previousExtent;
    final changed = _laidOutRevision != _revision;
    _previousExtent = extent;
    _laidOutRevision = _revision;
    // Only streaming updates trigger anchoring. Manual reasoning expansion
    // keeps its existing scroll behavior, and completion moves the same reply
    // into history without applying a second correction.
    if (_preservePosition &&
        changed &&
        previous != null &&
        constraints.scrollOffset > 0) {
      final correction = math.max(-constraints.scrollOffset, extent - previous);
      if (correction.abs() > precisionErrorTolerance) {
        geometry = SliverGeometry(scrollOffsetCorrection: correction);
      }
    }
  }
}
