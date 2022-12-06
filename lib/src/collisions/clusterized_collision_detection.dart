import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';
import 'package:flutter/foundation.dart';

class ClusterizedCollisionDetection
    extends StandardCollisionDetection<ClusterizedBroadphase<ShapeHitbox>> {
  ClusterizedCollisionDetection(
      {required ExternalBroadphaseCheck onComponentTypeCheck,
      required ExternalMinDistanceCheckClusterized minimumDistanceCheck,
      required this.clusterizer})
      : super(
            broadphase: ClusterizedBroadphase<ShapeHitbox>(
          clusterizer: clusterizer,
          broadphaseCheck: onComponentTypeCheck,
          minimumDistanceCheck: minimumDistanceCheck,
        ));

  final _listenerCollisionType = <ShapeHitbox, VoidCallback>{};
  final _listenerClusterizedSuspend = <ShapeHitbox, VoidCallback>{};
  final _scheduledUpdate = <ShapeHitbox>{};
  final Clusterizer clusterizer;

  @override
  void add(ShapeHitbox hitbox) {
    super.add(hitbox);

    hitbox.onAabbChanged = () => _scheduledUpdate.add(hitbox);
    final clusterizedComponent = hitbox.clusterizedParent;
    if (clusterizedComponent != null) {
      clusterizedComponent.setClusterizer(clusterizer);
      // ignore: prefer_function_declarations_over_variables
      final listenerCollisionType = () {
        if (hitbox.isMounted) {
          _onClusterizedCollisionTypeChange(clusterizedComponent, hitbox);
        }
      };

      hitbox.collisionTypeNotifier.addListener(listenerCollisionType);
      _listenerCollisionType[hitbox] = listenerCollisionType;

      _onClusterizedCollisionTypeChange(clusterizedComponent, hitbox);

      hitbox.defaultCollisionType; //init defaults with current value;

      // ignore: prefer_function_declarations_over_variables
      final listenerClusterizerSuspend = () {
        _onComponentSuspend(clusterizedComponent, hitbox);
      };
      clusterizedComponent.suspendNotifier
          .addListener(listenerClusterizerSuspend);
      _listenerClusterizedSuspend[hitbox] = listenerClusterizerSuspend;

      clusterizedComponent.onClusterizerMounted();
    } else {
      // ignore: prefer_function_declarations_over_variables
      final listenerCollisionType = () {
        if (hitbox.isMounted) {
          if (hitbox.collisionType == CollisionType.active) {
            broadphase.activeCollisions.add(hitbox);
          } else {
            broadphase.activeCollisions.remove(hitbox);
          }
        }
      };
      hitbox.collisionTypeNotifier.addListener(listenerCollisionType);
      _listenerCollisionType[hitbox] = listenerCollisionType;
    }
  }

  void _onComponentSuspend(ClusterizedComponent component, ShapeHitbox hitbox) {
    if (component.toggleCollisionOnSuspendChange) {
      if (component.isSuspended) {
        hitbox.collisionType = CollisionType.inactive;
      } else {
        hitbox.collisionType = hitbox.defaultCollisionType;
      }
      _onClusterizedCollisionTypeChange(component, hitbox);
    }
  }

  void _onClusterizedCollisionTypeChange(
      ClusterizedComponent component, ShapeHitbox hitbox) {
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

  void _addHotboxToPassives(
      ClusterizedComponent component, ShapeHitbox hitbox) {
    final cell = component.currentCell;
    if (cell != null && cell.state != CellState.suspended) {
      var list = broadphase.passiveCollisionsByCell[cell];
      list ??=
          broadphase.passiveCollisionsByCell[cell] = HashSet<ShapeHitbox>();
      list.add(hitbox);
    }
  }

  void _removeHitboxFromPassives(
      ClusterizedComponent component, ShapeHitbox hitbox) {
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

    final clusterizedComponent = hitbox.clusterizedParent;
    if (clusterizedComponent != null) {
      final listenerClusterizerSuspend = _listenerCollisionType[hitbox];
      if (listenerClusterizerSuspend != null) {
        clusterizedComponent.suspendNotifier
            .removeListener(listenerClusterizerSuspend);
        _listenerClusterizedSuspend.remove(hitbox);
      }
      _removeHitboxFromPassives(clusterizedComponent, hitbox);
      broadphase.activeCollisions.remove(hitbox);
    }

    hitbox.clearClusterizedParent();
    super.remove(hitbox);
  }

  @override
  void removeAll(Iterable<ShapeHitbox> items) {
    broadphase.clear();
    items.forEach(remove);
  }

  void _updateTransform(ShapeHitbox item) {
    final clusterizedComponent = item.clusterizedParent;
    if (clusterizedComponent == null) return;
    final previousCell = clusterizedComponent.currentCell;
    final cellChanged = clusterizedComponent.updateTransform();
    //suspend hitbox, if was moved to suspended cell.
    if (cellChanged && !clusterizedComponent.isTracked) {
      final onCellSuspend = _listenerClusterizedSuspend[item];
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
    for (var tuple in potentials) {
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
