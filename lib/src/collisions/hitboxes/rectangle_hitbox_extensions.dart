part of 'bounding_hitbox.dart';

extension SpatialGridRectangleHitbox on RectangleHitbox {
  Vector2 get aabbCenter {
    final hitbox = this;
    if (hitbox is BoundingHitbox) {
      return hitbox.aabbCenter;
    }

    var cache = HasGridSupport.cachedCenters[this];
    if (cache == null) {
      HasGridSupport.cachedCenters[this] = aabb.center;
      cache = HasGridSupport.cachedCenters[this];
    }
    return cache!;
  }

  bool isFullyInsideRect(Rect rect) {
    final boundingRect = aabb.toRect();
    return rect.topLeft < boundingRect.topLeft &&
        rect.bottomRight > boundingRect.bottomRight;
  }
}
