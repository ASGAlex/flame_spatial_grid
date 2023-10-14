import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

extension RectSpecialOverlap on Rect {
  /// Whether `other` has a nonzero area of overlap with this rectangle.
  bool overlapsSpecial(Rect other) {
    if (topLeft == other.bottomRight ||
        topRight == other.bottomLeft ||
        bottomLeft == other.topRight ||
        bottomRight == other.topLeft) {
      return false;
    }
    if (right < other.left || other.right < left) {
      return false;
    }
    if (bottom < other.top || other.bottom < top) {
      return false;
    }
    return true;
  }
}

extension ToRectSpecial on PositionComponent {
  Rect toRectSpecial() {
    final parentPosition = (parent as PositionComponent?)?.position;
    if (parentPosition == null) {
      return Rect.zero;
    }
    return Rect.fromLTWH(
      parentPosition.x + position.x,
      parentPosition.y + position.y,
      size.x,
      size.y,
    );
  }
}
