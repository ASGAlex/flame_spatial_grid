import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class GroupHitbox extends BoundingHitbox {
  GroupHitbox({
    super.position,
    super.size,
    super.parentWithGridSupport,
    required this.tag,
  }) {
    isSolid = true;
    collisionType = CollisionType.passive;
    defaultCollisionType = collisionType;
    fastCollisionForRects = true;
  }

  final String tag;

  @override
  bool get optimized => false;

  @override
  void renderDebugMode(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTWH(position.x, position.y, size.x, size.y),
      Paint()
        ..color = const Color.fromRGBO(0, 0, 255, 1)
        ..style = PaintingStyle.stroke,
    );
  }
}
