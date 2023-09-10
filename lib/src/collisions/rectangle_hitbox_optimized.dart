import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/src/geometry/polygon_ray_intersection.dart';
import 'package:flame_spatial_grid/src/collisions/polygon_rect_component.dart';
import 'package:flutter/foundation.dart';

class RectangleHitboxOptimized extends PolygonRectComponent
    with ShapeHitbox, PolygonRayIntersection<RectangleHitbox>
    implements RectangleHitbox {
  @override
  final bool shouldFillParent;

  RectangleHitboxOptimized({
    super.position,
    super.size,
    super.angle,
    super.anchor,
    super.priority,
    bool isSolid = false,
    CollisionType collisionType = CollisionType.active,
  })  : shouldFillParent = size == null && position == null,
        super(sizeToVertices(size ?? Vector2.zero(), anchor)) {
    this.isSolid = isSolid;
    this.collisionType = collisionType;
  }

  @override
  void fillParent() {
    refreshVertices(
      newVertices: sizeToVertices(size, anchor),
    );
  }

  @protected
  static List<Vector2> sizeToVertices(
    Vector2 size,
    Anchor? componentAnchor,
  ) {
    final anchor = componentAnchor ?? Anchor.topLeft;
    return [
      Vector2(-size.x * anchor.x, -size.y * anchor.y),
      Vector2(size.x - size.x * anchor.x, -size.y * anchor.y),
      Vector2(size.x - size.x * anchor.x, size.y - size.y * anchor.y),
      Vector2(-size.x * anchor.x, size.y - size.y * anchor.y),
    ];
  }
}
