import 'package:flame/collisions.dart';
import 'package:flame_spatial_grid/src/collisions/collision_prospect/collision_prospect.dart';

/// This pool is used to not create unnecessary [CollisionProspect] objects
/// during collision detection, but to re-use the ones that have already been
/// created.
class ProspectPoolGrouped extends ProspectPool<ShapeHitbox> {
  ProspectPoolGrouped({super.incrementSize = 1000});

  final _storage = <CollisionProspectGrouped>[];

  @override
  int get length => _storage.length;

  /// The size of the pool will expand with [incrementSize] amount of
  /// [CollisionProspect]s that are initially populated with two [dummyItem]s.
  @override
  void expand(ShapeHitbox dummyItem) {
    for (var i = 0; i < incrementSize; i++) {
      _storage.add(CollisionProspectGrouped(dummyItem, dummyItem));
    }
  }

  @override
  CollisionProspect<ShapeHitbox> operator [](int index) => _storage[index];
}
