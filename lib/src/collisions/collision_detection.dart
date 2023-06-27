import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/broadphase.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

class SpatialGridCollisionDetection
    extends StandardCollisionDetection<SpatialGridBroadphase<ShapeHitbox>> {
  SpatialGridCollisionDetection({
    required ExternalBroadphaseCheck onComponentExtendedTypeCheck,
    required PureTypeCheck pureTypeCheck,
    required this.spatialGrid,
  }) : super(
          broadphase: SpatialGridBroadphase<ShapeHitbox>(
            spatialGrid: spatialGrid,
            extendedTypeCheck: onComponentExtendedTypeCheck,
            globalPureTypeCheck: pureTypeCheck,
          ),
        );

  final _listenerCollisionType = <ShapeHitbox, VoidCallback>{};
  final _scheduledUpdateAfterTransform = <ShapeHitbox>{};
  final SpatialGrid spatialGrid;

  @internal
  double dt = 0;

  @override
  void add(ShapeHitbox item) {
    // ignore: invalid_use_of_internal_member
    item.onAabbChanged = () => _scheduledUpdateAfterTransform.add(item);
    final withGridSupportComponent = item.parentWithGridSupport;
    if (withGridSupportComponent != null) {
      withGridSupportComponent.spatialGrid = spatialGrid;
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
      withGridSupportComponent.onSpatialGridInitialized();
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

    final withGridSupportComponent = item.parentWithGridSupport;
    if (withGridSupportComponent != null) {
      final currentCell = withGridSupportComponent.currentCell;
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
      if (withGridSupportComponent.parent == null) {
        withGridSupportComponent.currentCell = null;
      }
    }

    broadphase.remove(item);

    item.clearGridComponentCaches();
  }

  @override
  void removeAll(Iterable<ShapeHitbox> items) {
    broadphase.dispose();
    items.forEach(remove);
  }

  final HashSet<CollisionProspect<ShapeHitbox>> _lastPotentials =
      HashSet<CollisionProspect<ShapeHitbox>>();

  @override
  void run() {
    broadphase.dt = dt;
    broadphase.update();
    _scheduledUpdateAfterTransform.forEach(_updateTransform);
    _scheduledUpdateAfterTransform.clear();
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
      final distances = (item.aabb.max - item.aabb.min) / 2;
      item.minCollisionDistanceX = distances.x;
      item.minCollisionDistanceY = distances.y;
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

  @override
  void handleCollisionStart(
    Set<Vector2> intersectionPoints,
    ShapeHitbox hitboxA,
    ShapeHitbox hitboxB,
  ) {
    broadphase.hasCollisionsLastTime.add(hitboxA);
    super.handleCollisionStart(intersectionPoints, hitboxA, hitboxB);
  }

  @override
  void handleCollisionEnd(ShapeHitbox hitboxA, ShapeHitbox hitboxB) {
    if (hitboxA.activeCollisions.isEmpty) {
      broadphase.hasCollisionsLastTime.remove(hitboxA);
    }
    super.handleCollisionEnd(hitboxA, hitboxB);
  }

  void dispose() {
    spatialGrid.dispose();
    _scheduledUpdateAfterTransform.clear();
    broadphase.dispose();
  }
}
