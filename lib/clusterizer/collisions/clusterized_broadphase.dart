import 'dart:collection';

import 'package:cluisterizer_test/clusterizer/clusterized_component.dart';
import 'package:flame/collisions.dart';

import '../cell.dart';
import '../clusterizer.dart';

/// Performs Quad Tree broadphase check.
///
/// See [HasQuadTreeCollisionDetection.initializeCollisionDetection] for a
/// detailed description of its initialization parameters.
class ClusterizedBroadphase<T extends Hitbox<T>> extends Broadphase<T> {
  ClusterizedBroadphase({
    super.items,
    required this.clusterizer,
    required this.broadphaseCheck,
    required this.minimumDistanceCheck,
  });

  final Clusterizer clusterizer;

  final activeCollisions = HashSet<T>();
  final passiveCollisionsByCell = <Cell, List<T>>{};

  ExternalBroadphaseCheck broadphaseCheck;
  ExternalMinDistanceCheck minimumDistanceCheck;
  final _broadphaseCheckCache = <T, Map<T, bool>>{};

  final _potentials = HashSet<CollisionProspect<T>>();
  final _potentialsTmp = <List<ShapeHitbox>>[];

  @override
  HashSet<CollisionProspect<T>> query() {
    // return _potentials;
    _potentials.clear();
    _potentialsTmp.clear();

    for (final activeItem in activeCollisions) {
      final asShapeItem = activeItem as ShapeHitbox;

      if (asShapeItem.isRemoving || asShapeItem.parent == null) {
        continue;
      }

      final itemCenter = asShapeItem.center;
      final cellsToCheck =
          asShapeItem.clusterizedParent?.currentCell?.neighboursAndMe;

      final potentiallyCollide = <T>[];
      if (cellsToCheck == null) continue;
      for (final cell in cellsToCheck) {
        final items = passiveCollisionsByCell[cell];
        if (items != null && items.isNotEmpty) {
          potentiallyCollide.addAll(items);
        }
      }
      for (final potential in potentiallyCollide) {
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
          asShapePotential.aabbCenter,
        );
        if (distanceCloseEnough == false) {
          continue;
        }

        _potentialsTmp.add([asShapeItem, asShapePotential]);
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

  void clear() {
    activeCollisions.clear();
    _broadphaseCheckCache.clear();
  }
}
