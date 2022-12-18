import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/foundation.dart';

import 'collision_optimizer.dart';

class SpatialGridCollisionDetection
    extends StandardCollisionDetection<SpatialGridBroadphase<ShapeHitbox>> {
  SpatialGridCollisionDetection(
      {required ExternalBroadphaseCheck onComponentTypeCheck,
      required ExternalMinDistanceCheckSpatialGrid minimumDistanceCheck,
      required this.spatialGrid})
      : super(
            broadphase: SpatialGridBroadphase<ShapeHitbox>(
          spatialGrid: spatialGrid,
          broadphaseCheck: onComponentTypeCheck,
          minimumDistanceCheck: minimumDistanceCheck,
        ));

  final _listenerCollisionType = <ShapeHitbox, VoidCallback>{};
  final _listenerComponentInCellSuspend = <ShapeHitbox, VoidCallback>{};
  final _scheduledUpdate = <ShapeHitbox>{};
  final SpatialGrid spatialGrid;

  @override
  void add(ShapeHitbox item) {
    super.add(item);

    item.onAabbChanged = () => _scheduledUpdate.add(item);
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

      // ignore: prefer_function_declarations_over_variables
      final listenerComponentInCellSuspend = () {
        _onCellSuspendChanged(withGridSupportComponent, item);
      };
      withGridSupportComponent.suspendNotifier
          .addListener(listenerComponentInCellSuspend);
      _listenerComponentInCellSuspend[item] = listenerComponentInCellSuspend;

      withGridSupportComponent.onSpatialGridSupportComponentMounted();
    } else {
      // ignore: prefer_function_declarations_over_variables
      final listenerCollisionType = () {
        if (item.isMounted) {
          if (item.collisionType == CollisionType.active) {
            broadphase.activeCollisions.add(item);
          } else {
            broadphase.activeCollisions.remove(item);
          }
        }
      };
      item.collisionTypeNotifier.addListener(listenerCollisionType);
      _listenerCollisionType[item] = listenerCollisionType;
    }
  }

  void _onCellSuspendChanged(HasGridSupport component, ShapeHitbox hitbox) {
    if (component.toggleCollisionOnSuspendChange) {
      if (component.isSuspended) {
        hitbox.collisionType = CollisionType.inactive;
      } else {
        hitbox.collisionType = hitbox.defaultCollisionType;
      }
      _onSpatialGridCollisionTypeChange(component, hitbox);
    }
  }

  void _onSpatialGridCollisionTypeChange(
      HasGridSupport component, ShapeHitbox hitbox) {
    switch (hitbox.collisionType) {
      case CollisionType.active:
        broadphase.activeCollisions.add(hitbox);
        _removeHitboxFromPassives(component, hitbox);
        break;
      case CollisionType.passive:
        broadphase.activeCollisions.remove(hitbox);
        _addHotboxToPassives(component, hitbox);
        break;
      case CollisionType.inactive:
        broadphase.activeCollisions.remove(hitbox);
        _removeHitboxFromPassives(component, hitbox);
        break;
    }
  }

  void _addHotboxToPassives(HasGridSupport component, ShapeHitbox hitbox) {
    final cell = component.currentCell;
    if (cell != null && cell.state != CellState.suspended) {
      var list = broadphase.passiveCollisionsByCell[cell];
      list ??=
          broadphase.passiveCollisionsByCell[cell] = HashSet<ShapeHitbox>();
      list.add(hitbox);
    }
  }

  void _removeHitboxFromPassives(HasGridSupport component, ShapeHitbox hitbox) {
    final cell = component.currentCell;
    if (cell != null) {
      broadphase.passiveCollisionsByCell[cell]?.remove(hitbox);
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
        _listenerComponentInCellSuspend.remove(hitbox);
      }
      _removeHitboxFromPassives(spatialGridSupportComponent, hitbox);
      broadphase.activeCollisions.remove(hitbox);
    }

    hitbox.clearGridComponentParent();
    super.remove(hitbox);
  }

  @override
  void removeAll(Iterable<ShapeHitbox> items) {
    broadphase.clear();
    items.forEach(remove);
  }

  void _updateTransform(ShapeHitbox item) {
    final withGridSupportComponent = item.parentWithGridSupport;
    if (withGridSupportComponent == null) return;
    final previousCell = withGridSupportComponent.currentCell;
    final cellChanged = withGridSupportComponent.updateTransform();
    //suspend hitbox, if was moved to suspended cell.
    if (cellChanged) {
      final onCellSuspend = _listenerComponentInCellSuspend[item];
      if (onCellSuspend != null) {
        onCellSuspend();
      }
      if (item.collisionType == CollisionType.inactive &&
          previousCell != null) {
        final list = broadphase.passiveCollisionsByCell[previousCell];
        if (list != null) {
          list.remove(item);
        }
      }
    }
  }

  final Set<CollisionProspect<ShapeHitbox>> _lastPotentials = {};

  @override
  void run() {
    _scheduledUpdate.forEach(_updateTransform);
    _scheduledUpdate.clear();
    broadphase.update();
    _runForPotentials(broadphase.query());
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
