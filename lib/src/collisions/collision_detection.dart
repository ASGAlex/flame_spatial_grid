import 'dart:collection';
import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/extensions.dart';
import 'package:flame/geometry.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/broadphase.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

class SpatialGridCollisionDetection
    extends StandardCollisionDetection<SpatialGridBroadphase> {
  SpatialGridCollisionDetection({
    required ExternalBroadphaseCheck onComponentExtendedTypeCheck,
    required PureTypeCheck pureTypeCheck,
    required this.spatialGrid,
  }) : super(
          broadphase: SpatialGridBroadphase(
            spatialGrid: spatialGrid,
            extendedTypeCheck: onComponentExtendedTypeCheck,
            globalPureTypeCheck: pureTypeCheck,
          ),
        );

  final _listenerCollisionType = <ShapeHitbox, VoidCallback>{};
  ShapeHitbox? _trackedComponentScheduledUpdate;
  final _scheduledUpdateAfterTransform = <ShapeHitbox>{};
  final SpatialGrid spatialGrid;

  @internal
  double dt = 0;

  set rayTraceMode(RayTraceMode value) {
    broadphase.rayTraceMode = value;
  }

  @override
  void add(ShapeHitbox item) {
    // ignore: invalid_use_of_internal_member
    item.onAabbChanged = () {
      var added = false;
      final withGridSupportComponent = item.parentWithGridSupport;
      if (withGridSupportComponent != null) {
        if (withGridSupportComponent.isTracked) {
          _trackedComponentScheduledUpdate = item;
          added = true;
        }
      }
      if (!added) {
        _scheduledUpdateAfterTransform.add(item);
      }
    };
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
      _scheduledUpdateAfterTransform.add(item);

      broadphase.updateHitboxIndexes(item);
      final componentCurrentCell = withGridSupportComponent.currentCell;
      if (componentCurrentCell != null) {
        broadphase.saveHitboxCell(item, componentCurrentCell);
      }
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
        broadphase.scheduledOperations.add(
          ScheduledHitboxOperation.removeFromAll(
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

  final _lastPotentials = HashSet<CollisionProspect<ShapeHitbox>>();

  @override
  void run() {
    if (!broadphase.queryRunning) {
      broadphase.dt = dt;
      broadphase.update();
      if (_trackedComponentScheduledUpdate != null) {
        _updateTransform(_trackedComponentScheduledUpdate!);
        _trackedComponentScheduledUpdate = null;
      }
      _scheduledUpdateAfterTransform.forEach(_updateTransform);
      _scheduledUpdateAfterTransform.clear();
    }

    final allPotentialsIterable = broadphase.query();
    if (broadphase.queryRunning) {
      print('running!');
      return;
    }
    final allPotentials = allPotentialsIterable.toList();
    final repeatBroadphaseForItems = _runForPotentials(allPotentials);
    if (repeatBroadphaseForItems.isNotEmpty &&
        repeatBroadphaseForItems[0] != null) {
      final additionalPotentials =
          broadphase.querySubset(repeatBroadphaseForItems);
      _runForPotentials(additionalPotentials);
      allPotentials.addAll(additionalPotentials);
    }
    final unmodifiableAllPotentials = allPotentials.toList(growable: false);

    final allHashes =
        Set.unmodifiable(unmodifiableAllPotentials.map((p) => p.hash));
    // Handles callbacks for an ended collision that the broadphase didn't
    // report as a potential collision anymore.
    for (final prospect in _lastPotentials) {
      if (!allHashes.contains(prospect.hash) &&
          (prospect.a.collidingWith(prospect.b) ||
              _isPotentialCollidingGroup(prospect.b, prospect.a))) {
        handleCollisionEnd(prospect.a, prospect.b);
      }
    }
    _updateLastPotentials(unmodifiableAllPotentials);
  }

  bool _isPotentialCollidingGroup(ShapeHitbox potential, ShapeHitbox active) {
    if (potential is GroupHitbox && potential.collidingWith(active)) {
      return true;
    }
    return false;
  }

  void _updateTransform(ShapeHitbox item) {
    if (item is BoundingHitbox) {
      item.aabbCenter = item.aabb.center;
      item.minCollisionDistance = (item.aabb.max - item.aabb.min) / 2;
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

  final _lastPotentialsPool = <CollisionProspect<ShapeHitbox>>[];

  void _updateLastPotentials(
    Iterable<CollisionProspect<ShapeHitbox>> potentials,
  ) {
    _lastPotentials.clear();
    for (final potential in potentials) {
      final CollisionProspect<ShapeHitbox> lastPotential;
      if (_lastPotentialsPool.length > _lastPotentials.length) {
        lastPotential = _lastPotentialsPool[_lastPotentials.length]
          ..setFrom(potential);
      } else {
        lastPotential = potential.clone();
        _lastPotentialsPool.add(lastPotential);
      }
      _lastPotentials.add(lastPotential);
    }
  }

  List<CollisionProspect<ShapeHitbox>?> _runForPotentials(
    Iterable<CollisionProspect<ShapeHitbox>> potentials,
  ) {
    final repeatBroadphaseForItems =
        List<CollisionProspect<ShapeHitbox>?>.filled(potentials.length, null);
    var i = 0;
    for (final tuple in potentials) {
      final itemA = tuple.a;
      final itemB = tuple.b;

      if (itemA.possiblyIntersects(itemB)) {
        final intersectionPoints = intersections(itemA, itemB);
        if (intersectionPoints.isNotEmpty) {
          if (itemA is GroupHitbox || itemB is GroupHitbox) {
            var handleCollisions = false;
            if (itemA is BoundingHitbox &&
                itemA.groupCollisionsTags.isNotEmpty &&
                itemB is GroupHitbox) {
              handleCollisions = itemA.groupCollisionsTags.contains(itemB.tag);
            } else if (itemB is BoundingHitbox &&
                itemB.groupCollisionsTags.isNotEmpty &&
                itemA is GroupHitbox) {
              handleCollisions = itemB.groupCollisionsTags.contains(itemA.tag);
            }

            if (!handleCollisions) {
              repeatBroadphaseForItems[i] = tuple;
              i++;
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

  @override
  RaycastResult<ShapeHitbox>? raycast(
    Ray2 ray, {
    double? maxDistance,
    bool Function(ShapeHitbox candidate)? hitboxFilter,
    List<ShapeHitbox>? ignoreHitboxes,
    List<Type>? ignoreHitboxesTypes,
    List<Type>? allowOnlyHitboxesTypes,
    Type? rayAsHitboxType,
    RaycastResult<ShapeHitbox>? out,
  }) {
    var finalResult = out?..reset();
    _updateRayAabb(ray, maxDistance);
    for (final item in items) {
      if (rayAsHitboxType != null) {
        final canCollide = broadphase.comparator
            .globalTypeCheck(rayAsHitboxType, item.runtimeType);
        if (!canCollide) {
          continue;
        }
      } else {
        if (ignoreHitboxesTypes?.contains(item.runtimeType) ?? false) {
          continue;
        }
        if (!(allowOnlyHitboxesTypes?.contains(item.runtimeType) ?? true)) {
          continue;
        }
      }
      if (ignoreHitboxes?.contains(item) ?? false) {
        continue;
      }
      if (hitboxFilter != null) {
        if (!hitboxFilter(item)) {
          continue;
        }
      }
      if (!item.aabb.intersectsWithAabb2(_temporaryRayAabb)) {
        continue;
      }
      final currentResult =
          item.rayIntersection(ray, out: _temporaryRaycastResult);
      final possiblyFirstResult = !(finalResult?.isActive ?? false);
      if (currentResult != null &&
          (possiblyFirstResult ||
              currentResult.distance! < finalResult!.distance!) &&
          currentResult.distance! <= (maxDistance ?? double.infinity)) {
        if (finalResult == null) {
          finalResult = currentResult.clone();
        } else {
          finalResult.setFrom(currentResult);
        }
      }
    }
    return (finalResult?.isActive ?? false) ? finalResult : null;
  }

  static Ray2? _cachedRay;
  static final _temporaryRayAabb = Aabb2();
  static final _temporaryRaycastResult = RaycastResult<ShapeHitbox>();

  void _updateRayAabb(Ray2 ray, double? maxDistance) {
    if (ray != _cachedRay) {
      _cachedRay = ray;
      final x1 = ray.origin.x;
      final y1 = ray.origin.y;
      double x2;
      double y2;

      if (maxDistance != null) {
        x2 = ray.origin.x + ray.direction.x * maxDistance;
        y2 = ray.origin.y + ray.direction.y * maxDistance;
      } else {
        x2 = ray.direction.x > 0 ? double.infinity : double.negativeInfinity;
        y2 = ray.direction.y > 0 ? double.infinity : double.negativeInfinity;
      }

      _temporaryRayAabb
        ..min.setValues(math.min(x1, x2), math.min(y1, y2))
        ..max.setValues(math.max(x1, x2), math.max(y1, y2));
    }
  }

  void dispose() {
    spatialGrid.dispose();
    _scheduledUpdateAfterTransform.clear();
    broadphase.dispose();
  }
}
