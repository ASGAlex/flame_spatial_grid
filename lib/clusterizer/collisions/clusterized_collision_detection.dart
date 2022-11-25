import 'package:cluisterizer_test/clusterizer/clusterized_component.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/foundation.dart';

import 'clusterized_broadphase.dart';

class ClusterizedCollisionDetection
    extends StandardCollisionDetection<ClusterizedBroadphase<ShapeHitbox>> {
  ClusterizedCollisionDetection(
      {required ExternalBroadphaseCheck onComponentTypeCheck,
      required ExternalMinDistanceCheck minimumDistanceCheck})
      : super(
            broadphase: ClusterizedBroadphase<ShapeHitbox>(
          broadphaseCheck: onComponentTypeCheck,
          minimumDistanceCheck: minimumDistanceCheck,
        ));

  final _listenerCollisionType = <ShapeHitbox, VoidCallback>{};
  final _listenerClusterizedSuspend = <ShapeHitbox, VoidCallback>{};
  final _scheduledUpdate = <ShapeHitbox>{};

  @override
  void add(ShapeHitbox item) {
    super.add(item);

    item.onAabbChanged = () => _scheduledUpdate.add(item);
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

    final clusterizedComponent = item.clusterizedParent;
    if (clusterizedComponent != null) {
      item.defaultCollisionType; //init defaults with current value;
      // ignore: prefer_function_declarations_over_variables
      final listenerClusterizerSuspend = () {
        if (clusterizedComponent.toggleCollisionOnSuspendChange) {
          if (clusterizedComponent.isSuspended) {
            item.collisionType = CollisionType.inactive;
          } else {
            item.collisionType = item.defaultCollisionType;
          }
          listenerCollisionType();
        }
      };
      clusterizedComponent.suspendNotifier
          .addListener(listenerClusterizerSuspend);
      _listenerClusterizedSuspend[item] = listenerClusterizerSuspend;
    }

    broadphase.add(item);
  }

  @override
  void addAll(Iterable<ShapeHitbox> items) {
    items.forEach(add);
  }

  @override
  void remove(ShapeHitbox item) {
    item.onAabbChanged = null;
    final listenerCollisionType = _listenerCollisionType[item];
    if (listenerCollisionType != null) {
      item.collisionTypeNotifier.removeListener(listenerCollisionType);
      _listenerCollisionType.remove(item);
    }

    final clusterizedComponent = item.clusterizedParent;
    if (clusterizedComponent != null) {
      final listenerClusterizerSuspend = _listenerCollisionType[item];
      if (listenerClusterizerSuspend != null) {
        clusterizedComponent.suspendNotifier
            .removeListener(listenerClusterizerSuspend);
        _listenerClusterizedSuspend.remove(item);
      }
    }

    broadphase.remove(item);
    super.remove(item);
  }

  @override
  void removeAll(Iterable<ShapeHitbox> items) {
    broadphase.clear();
    items.forEach(remove);
  }

  void _updateTransform(ShapeHitbox item) {
    final clusterizedComponent = item.clusterizedParent;
    if (clusterizedComponent == null) return;
    clusterizedComponent.updateTransform();
  }

  @override
  void run() {
    _scheduledUpdate.forEach(_updateTransform);
    _scheduledUpdate.clear();
    super.run();
  }
}
