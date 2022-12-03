import 'package:cluisterizer_test/clusterizer/cell.dart';
import 'package:cluisterizer_test/clusterizer/clusterized_component.dart';
import 'package:cluisterizer_test/clusterizer/clusterizer.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/foundation.dart';

import 'clusterized_broadphase.dart';

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
      clusterizedComponent.clusterizer = clusterizer;
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
      list ??= broadphase.passiveCollisionsByCell[cell] = [];
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

  @override
  void run() {
    _scheduledUpdate.forEach(_updateTransform);
    _scheduledUpdate.clear();
    super.run();
  }
}
