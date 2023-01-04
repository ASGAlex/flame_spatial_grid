import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/foundation.dart';

import 'broadphase.dart';
import 'collision_optimizer.dart';

class SpatialGridCollisionDetection
    extends StandardCollisionDetection<SpatialGridBroadphase<ShapeHitbox>> {
  SpatialGridCollisionDetection(
      {required ExternalBroadphaseCheck onComponentTypeCheck,
      ExternalMinDistanceCheckSpatialGrid? minimumDistanceCheck,
      required this.spatialGrid})
      : super(
            broadphase: SpatialGridBroadphase<ShapeHitbox>(
          spatialGrid: spatialGrid,
          broadphaseCheck: onComponentTypeCheck,
          minimumDistanceCheck: minimumDistanceCheck,
        ));

  final _listenerCollisionType = <ShapeHitbox, VoidCallback>{};
  final _scheduledUpdateAfterTransform = <ShapeHitbox>{};
  final SpatialGrid spatialGrid;

  @override
  void add(ShapeHitbox item) {
    //super.add(item);

    item.onAabbChanged = () => _scheduledUpdateAfterTransform.add(item);
    final withGridSupportComponent = item.parentWithGridSupport;
    if (withGridSupportComponent != null) {
      withGridSupportComponent.setSpatialGrid(spatialGrid);
      // ignore: prefer_function_declarations_over_variables
      final listenerCollisionType = () {
        if (item.isMounted) {
          _onSpatialGridCollisionTypeChange(withGridSupportComponent, item);
        }
      };

      item.collisionTypeNotifier.addListener(listenerCollisionType);
      _listenerCollisionType[item] = listenerCollisionType;

      _onSpatialGridCollisionTypeChange(withGridSupportComponent, item);

      item.defaultCollisionType; //init defaults with current value;

      withGridSupportComponent.onSpatialGridSupportComponentMounted();
    }
  }

  void _onSpatialGridCollisionTypeChange(
      HasGridSupport component, ShapeHitbox hitbox) {
    switch (hitbox.collisionType) {
      case CollisionType.active:
        broadphase.scheduledOperations
            .add(ScheduledHitboxOperation.addActive(hitbox: hitbox));
        broadphase.scheduledOperations.add(
            ScheduledHitboxOperation.removePassive(
                hitbox: hitbox, cell: component.currentCell));
        break;
      case CollisionType.passive:
        broadphase.scheduledOperations
            .add(ScheduledHitboxOperation.removeActive(hitbox: hitbox));
        broadphase.scheduledOperations.add(ScheduledHitboxOperation.addPassive(
            hitbox: hitbox, cell: component.currentCell));
        break;
      case CollisionType.inactive:
        broadphase.scheduledOperations
            .add(ScheduledHitboxOperation.removeActive(hitbox: hitbox));
        broadphase.scheduledOperations.add(
            ScheduledHitboxOperation.removePassive(
                hitbox: hitbox, cell: component.currentCell));
        break;
    }
  }

  @override
  void addAll(Iterable<ShapeHitbox> items) {
    items.forEach(add);
  }

  @override
  void remove(ShapeHitbox hitbox) {
    hitbox.onAabbChanged = null;
    final listenerCollisionType = _listenerCollisionType[hitbox];
    if (listenerCollisionType != null) {
      hitbox.collisionTypeNotifier.removeListener(listenerCollisionType);
      _listenerCollisionType.remove(hitbox);
    }

    final spatialGridSupportComponent = hitbox.parentWithGridSupport;
    if (spatialGridSupportComponent != null) {
      final listenerComponentInCellSuspend = _listenerCollisionType[hitbox];
      if (listenerComponentInCellSuspend != null) {
        spatialGridSupportComponent.suspendNotifier
            .removeListener(listenerComponentInCellSuspend);
      }
      broadphase.scheduledOperations.add(ScheduledHitboxOperation.removePassive(
          hitbox: hitbox, cell: spatialGridSupportComponent.currentCell));
      broadphase.scheduledOperations
          .add(ScheduledHitboxOperation.removeActive(hitbox: hitbox));
    }

    final checkCache = broadphase.broadphaseCheckCache[hitbox];
    if (checkCache != null) {
      for (final entry in checkCache.entries) {
        broadphase.broadphaseCheckCache[entry.key]?.remove(hitbox);
      }
      broadphase.broadphaseCheckCache.remove(hitbox);
    }

    hitbox.clearGridComponentParent();
  }

  @override
  void removeAll(Iterable<ShapeHitbox> items) {
    broadphase.clear();
    items.forEach(remove);
  }

  final Set<CollisionProspect<ShapeHitbox>> _lastPotentials = {};

  @override
  void run() {
    _scheduledUpdateAfterTransform.forEach(_updateTransform);
    _scheduledUpdateAfterTransform.clear();
    broadphase.update();
    _runForPotentials(broadphase.query());
  }

  void _updateTransform(ShapeHitbox item) {
    final withGridSupportComponent = item.parentWithGridSupport;
    if (withGridSupportComponent == null) return;
    withGridSupportComponent.updateTransform();
  }

  void _runForPotentials(HashSet<CollisionProspect<ShapeHitbox>> potentials) {
    final repeatBroadphaseForItems = HashSet<CollisionProspect<ShapeHitbox>>();
    for (final tuple in potentials) {
      final itemA = tuple.a;
      final itemB = tuple.b;

      if (itemA.possiblyIntersects(itemB)) {
        final intersectionPoints = intersections(itemA, itemB);
        if (intersectionPoints.isNotEmpty) {
          if (itemA is GroupHitbox || itemB is GroupHitbox) {
            repeatBroadphaseForItems.add(tuple);
            continue;
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

    // Handles callbacks for an ended collision that the broadphase didn't
    // reports as a potential collision anymore.
    _lastPotentials.difference(potentials).forEach((tuple) {
      if (tuple.a.collidingWith(tuple.b)) {
        handleCollisionEnd(tuple.a, tuple.b);
      }
    });
    _lastPotentials
      ..clear()
      ..addAll(potentials);

    if (repeatBroadphaseForItems.isNotEmpty) {
      _runForPotentials(broadphase.querySubset(repeatBroadphaseForItems));
    }
  }
}
