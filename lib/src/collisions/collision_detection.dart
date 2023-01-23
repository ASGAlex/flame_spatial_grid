import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/broadphase.dart';
import 'package:flutter/foundation.dart';

class SpatialGridCollisionDetection
    extends StandardCollisionDetection<SpatialGridBroadphase<ShapeHitbox>> {
  SpatialGridCollisionDetection({
    required ExternalBroadphaseCheck onComponentTypeCheck,
    ExternalMinDistanceCheckSpatialGrid? minimumDistanceCheck,
    required this.spatialGrid,
  }) : super(
          broadphase: SpatialGridBroadphase<ShapeHitbox>(
            spatialGrid: spatialGrid,
            broadphaseCheck: onComponentTypeCheck,
            minimumDistanceCheck: minimumDistanceCheck,
          ),
        );

  final _listenerCollisionType = <ShapeHitbox, VoidCallback>{};
  final _scheduledUpdateAfterTransform = <ShapeHitbox>{};
  final SpatialGrid spatialGrid;

  @override
  void add(ShapeHitbox item) {
    // ignore: invalid_use_of_internal_member
    item.onAabbChanged = () => _scheduledUpdateAfterTransform.add(item);
    final withGridSupportComponent = item.parentWithGridSupport;
    if (withGridSupportComponent != null) {
      withGridSupportComponent.setSpatialGrid(spatialGrid);
      // ignore: prefer_function_declarations_over_variables
      final listenerCollisionType = () {
        if (item.isMounted) {
          broadphase.updateHitboxIndexes(item);
        }
      };

      // ignore: invalid_use_of_internal_member
      item.collisionTypeNotifier.addListener(listenerCollisionType);
      _listenerCollisionType[item] = listenerCollisionType;

      item.defaultCollisionType; //init defaults with current value;
      withGridSupportComponent.updateTransform();

      broadphase.updateHitboxIndexes(item);
    }
  }

  @override
  void addAll(Iterable<ShapeHitbox> items) {
    items.forEach(add);
  }

  @override
  void remove(ShapeHitbox item) {
    // ignore: invalid_use_of_internal_member
    item.onAabbChanged = null;
    final listenerCollisionType = _listenerCollisionType[item];
    if (listenerCollisionType != null) {
      // ignore: invalid_use_of_internal_member
      item.collisionTypeNotifier.removeListener(listenerCollisionType);
      _listenerCollisionType.remove(item);
    }

    final spatialGridSupportComponent = item.parentWithGridSupport;
    if (spatialGridSupportComponent != null) {
      final currentCell = spatialGridSupportComponent.currentCell;
      if (currentCell != null) {
        broadphase.scheduledOperations.add(
          ScheduledHitboxOperation.removePassive(
            hitbox: item,
            cell: currentCell,
          ),
        );
        broadphase.scheduledOperations.add(
          ScheduledHitboxOperation.removeActive(
            hitbox: item,
            cell: currentCell,
          ),
        );
      }
    }

    broadphase.remove(item);

    item.clearGridComponentCaches();
  }

  @override
  void removeAll(Iterable<ShapeHitbox> items) {
    broadphase.clear();
    items.forEach(remove);
  }

  final HashSet<CollisionProspect<ShapeHitbox>> _lastPotentials =
      HashSet<CollisionProspect<ShapeHitbox>>();

  @override
  void run() {
    _scheduledUpdateAfterTransform.forEach(_updateTransform);
    _scheduledUpdateAfterTransform.clear();
    broadphase.update();
    final allPotentials = broadphase.query();
    final repeatBroadphaseForItems = _runForPotentials(allPotentials);
    if (repeatBroadphaseForItems.isNotEmpty) {
      final additionalPotentials =
          broadphase.querySubset(repeatBroadphaseForItems);
      _runForPotentials(additionalPotentials);
      allPotentials.addAll(additionalPotentials);
    }
    // Handles callbacks for an ended collision that the broadphase didn't
    // reports as a potential collision anymore.
    _lastPotentials.difference(allPotentials).forEach((tuple) {
      if (tuple.a.collidingWith(tuple.b)) {
        handleCollisionEnd(tuple.a, tuple.b);
      }
    });
    _lastPotentials
      ..clear()
      ..addAll(allPotentials);
  }

  void _updateTransform(ShapeHitbox item) {
    if (item is BoundingHitbox) {
      item.aabbCenter = item.aabb.center;
    } else {
      HasGridSupport.cachedCenters.remove(item);
      item.aabbCenter;
    }
    final withGridSupportComponent = item.parentWithGridSupport;
    if (withGridSupportComponent == null) {
      return;
    }
    if (item == withGridSupportComponent.boundingBox) {
      withGridSupportComponent.updateTransform();
    }
  }

  HashSet<CollisionProspect<ShapeHitbox>> _runForPotentials(
    HashSet<CollisionProspect<ShapeHitbox>> potentials,
  ) {
    final repeatBroadphaseForItems = HashSet<CollisionProspect<ShapeHitbox>>();
    for (final tuple in potentials) {
      final itemA = tuple.a;
      final itemB = tuple.b;

      if (itemA.possiblyIntersects(itemB)) {
        final intersectionPoints = intersections(itemA, itemB);
        if (intersectionPoints.isNotEmpty) {
          if (itemA is GroupHitbox || itemB is GroupHitbox) {
            var handleCollisions = false;
            if (itemA is BoundingHitbox && itemB is GroupHitbox) {
              handleCollisions = itemA.groupCollisionsTags.contains(itemB.tag);
            } else if (itemB is BoundingHitbox && itemA is GroupHitbox) {
              handleCollisions = itemB.groupCollisionsTags.contains(itemA.tag);
            }

            if (!handleCollisions) {
              repeatBroadphaseForItems.add(tuple);
              continue;
            }
          }
          if (!itemA.collidingWith(itemB)) {
            handleCollisionStart(intersectionPoints, itemA, itemB);
          }
          handleCollision(intersectionPoints, itemA, itemB);
        } else if (itemA.collidingWith(itemB)) {
          handleCollisionEnd(itemA, itemB);
        }
      } else if (itemA.collidingWith(itemB)) {
        handleCollisionEnd(itemA, itemB);
      }
    }
    return repeatBroadphaseForItems;
  }
}
