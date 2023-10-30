import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame_spatial_grid/src/collisions/hitboxes/bounding_hitbox.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/flat_buffers/flat_buffers_optimizer.dart'
    as fb;

final fb.BoundingHitboxObjectBuilder defaultBoundingHitboxObjectBuilder =
    fb.BoundingHitboxObjectBuilder();

extension FlatBufferHitbox on BoundingHitbox {
  fb.BoundingHitboxObjectBuilder toBuilder(int index) {
    final position = fb.Vector2ObjectBuilder(
      x: this.position.x,
      y: this.position.y,
    );
    fb.Vector2ObjectBuilder? parentPosition;
    final parentPositionVector = (parent as PositionComponent?)?.position;
    if (parentPositionVector != null) {
      parentPosition = fb.Vector2ObjectBuilder(
        x: parentPositionVector.x,
        y: parentPositionVector.y,
      );
    }
    final size = fb.Vector2ObjectBuilder(x: this.size.x, y: this.size.y);
    final aabb = fb.Aabb2ObjectBuilder(
      min: fb.Vector2ObjectBuilder(
        x: this.aabb.min.x,
        y: this.aabb.min.y,
      ),
      max: fb.Vector2ObjectBuilder(
        x: this.aabb.max.x,
        y: this.aabb.max.y,
      ),
    );
    return fb.BoundingHitboxObjectBuilder(
      position: position,
      parentPosition: parentPosition,
      size: size,
      index: index,
      skip: collisionType == CollisionType.inactive,
      aabb: aabb,
    );
  }
}
