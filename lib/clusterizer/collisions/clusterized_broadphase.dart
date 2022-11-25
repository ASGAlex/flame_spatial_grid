import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/extensions.dart';

/// Performs Quad Tree broadphase check.
///
/// See [HasQuadTreeCollisionDetection.initializeCollisionDetection] for a
/// detailed description of its initialization parameters.
class ClusterizedBroadphase<T extends Hitbox<T>> extends Broadphase<T> {
  ClusterizedBroadphase({
    super.items,
    required this.broadphaseCheck,
    required this.minimumDistanceCheck,
  });

  final activeCollisions = HashSet<T>();

  ExternalBroadphaseCheck broadphaseCheck;
  ExternalMinDistanceCheck minimumDistanceCheck;
  final _broadphaseCheckCache = <T, Map<T, bool>>{};

  final _cachedCenters = <ShapeHitbox, Vector2>{};

  final _potentials = HashSet<CollisionProspect<T>>();
  final _potentialsTmp = <List<ShapeHitbox>>[];

  @override
  HashSet<CollisionProspect<T>> query() {
    return _potentials;
    _potentials.clear();
    _potentialsTmp.clear();

    for (final activeItem in activeCollisions) {
      final asShapeItem = activeItem as ShapeHitbox;

      if (asShapeItem.isRemoving || asShapeItem.parent == null) {
        continue;
      }

      final itemCenter = activeItem.aabb.center;
      final potentiallyCollide = {}; //tree.query(activeItem);
      for (final potential in potentiallyCollide.entries.first.value) {
        if (potential.collisionType == CollisionType.inactive) {
          continue;
        }

        if (_broadphaseCheckCache[activeItem]?[potential] == false) {
          continue;
        }

        final asShapePotential = potential as ShapeHitbox;

        if (asShapePotential.parent == asShapeItem.parent &&
            asShapeItem.parent != null) {
          continue;
        }

        final distanceCloseEnough = minimumDistanceCheck.call(
          itemCenter,
          _cacheCenterOfHitbox(asShapePotential),
        );
        if (distanceCloseEnough == false) {
          continue;
        }

        _potentialsTmp.add([asShapeItem, potential]);
      }
    }

    if (_potentialsTmp.isNotEmpty) {
      for (var i = 0; i < _potentialsTmp.length; i++) {
        final item0 = _potentialsTmp[i].first;
        final item1 = _potentialsTmp[i].last;
        if (broadphaseCheck(item0, item1)) {
          _potentials.add(CollisionProspect(item0 as T, item1 as T));
        } else {
          if (_broadphaseCheckCache[item0 as T] == null) {
            _broadphaseCheckCache[item0 as T] = {};
          }
          _broadphaseCheckCache[item0 as T]![item1 as T] = false;
        }
      }
    }
    return _potentials;
  }

  void updateTransform(T item) {
    _cacheCenterOfHitbox(item as ShapeHitbox);
  }

  void add(T hitbox) {
    if (hitbox.collisionType == CollisionType.active) {
      activeCollisions.add(hitbox);
    }
    _cacheCenterOfHitbox(hitbox as ShapeHitbox);
  }

  void remove(T item) {
    _cachedCenters.remove(item);
    if (item.collisionType == CollisionType.active) {
      activeCollisions.remove(item);
    }
  }

  void clear() {
    activeCollisions.clear();
    _broadphaseCheckCache.clear();
    _cachedCenters.clear();
  }

  /// Caches hitbox center because calculating on-the-fly is too expensive
  /// whereas many of game objects could not change theirs position or size
  Vector2 _cacheCenterOfHitbox(ShapeHitbox hitbox) {
    var cache = _cachedCenters[hitbox];
    if (cache == null) {
      _cachedCenters[hitbox] = hitbox.aabb.center;
      cache = _cachedCenters[hitbox];
    }
    return cache!;
  }
}
