import 'package:flame/collisions.dart';

class ClusterizedCollisionDetection
    extends StandardCollisionDetection<QuadTreeBroadphase<ShapeHitbox>> {
  @override
  void add(ShapeHitbox item) {
    super.add(item);
  }

  @override
  void addAll(Iterable<ShapeHitbox> items) {
    items.forEach(add);
  }

  @override
  void removeAll(Iterable<ShapeHitbox> items) {
    broadphase.clear();
    items.forEach(remove);
  }
}
