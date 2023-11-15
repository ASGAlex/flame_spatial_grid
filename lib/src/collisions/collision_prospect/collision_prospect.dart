import 'package:flame/collisions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

/// A [CollisionProspect] is a tuple that is used to contain two potentially
/// colliding hitboxes.
class CollisionProspectGrouped extends CollisionProspect<ShapeHitbox> {
  @override
  int get hash => _hashGrouped;
  int _hashGrouped;

  CollisionProspectGrouped(super.a, super.b)
      : _hashGrouped = a.hashCode ^
            ((b is GroupHitbox) ? b.hashCodeForCollisions : b.hashCode);

  @override
  void set(ShapeHitbox a, ShapeHitbox b) {
    super.set(a, b);
    _hashGrouped = a.hashCode ^
        ((b is GroupHitbox) ? b.hashCodeForCollisions : b.hashCode);
  }

  /// Sets the prospect to contain the content of [other].
  @override
  void setFrom(CollisionProspect<ShapeHitbox> other) {
    super.setFrom(other);
    if (other is CollisionProspectGrouped) {
      _hashGrouped = other._hashGrouped;
    }
  }

  /// Creates a new prospect object with the same content.
  @override
  CollisionProspect<ShapeHitbox> clone() => CollisionProspectGrouped(a, b);
}
