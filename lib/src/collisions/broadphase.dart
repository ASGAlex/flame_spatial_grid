import 'dart:collection';
import 'dart:math';
import 'dart:ui';

import 'package:dart_bloom_filter/dart_bloom_filter.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/collision_prospect/prospect_pool.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/optimized_collisions_list.dart';
import 'package:flame_spatial_grid/src/components/utility/pure_type_check_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

part 'broadphase/bloom_filter_provider.dart';
part 'broadphase/collisions_cache.dart';
part 'broadphase/comparator.dart';
part 'broadphase/schedule_hitbox_operation.dart';
part 'broadphase/typedef.dart';

/// Performs Quad Tree broadphase check.
///
/// See [HasQuadTreeCollisionDetection.initializeCollisionDetection] for a
/// detailed description of its initialization parameters.
class SpatialGridBroadphase extends Broadphase<ShapeHitbox> {
  SpatialGridBroadphase({
    required this.spatialGrid,
    required this.extendedTypeCheck,
    required PureTypeCheck globalPureTypeCheck,
  }) {
    comparator._globalPureTypeCheck = globalPureTypeCheck;
    comparator._bloomFilter = _bloomFilterProvider;
    dispose();
    fastDistanceCheckMinX = spatialGrid.cellSize.width / 3;
    fastDistanceCheckMinY = spatialGrid.cellSize.height / 3;
  }

  final SpatialGrid spatialGrid;

  final _prospectPool = ProspectPoolGrouped();
  var _prospectPoolIndex = 0;
  final _dummyHitbox = DummyHitbox();
  final _potentials = <int, CollisionProspect<ShapeHitbox>>{};

  var _activeCollisionsUnmodifiable = <ShapeHitbox>[];
  var _activeChecked = <List<bool>>[];
  var _activeCheckedRecreated = false;

  @internal
  final collisionsCache = CollisionsCache();

  @internal
  final comparator = Comparator();

  final _bloomFilterProvider = BloomFilterProvider();

  @internal
  final optimizedCollisionsByGroupBox =
      <Cell, Map<GroupHitbox, OptimizedCollisionList>>{};

  @internal
  double dt = 0;

  final hasCollisionsLastTime = HashSet<ShapeHitbox>();

  ExternalBroadphaseCheck extendedTypeCheck;

  @internal
  static final broadphaseCheckCache =
      HashMap<ShapeHitbox, HashMap<ShapeHitbox, bool>>();

  @internal
  final scheduledOperations = <ScheduledHitboxOperation>[];

  @internal
  double fastDistanceCheckMinX = -1;

  @internal
  double fastDistanceCheckMinY = -1;

  @override
  void update() {
    collisionsCache.preUpdate();
    scheduledOperations.forEach(collisionsCache.processOperation);
    scheduledOperations.clear();
    if (collisionsCache.activeCollisionsChanged) {
      _raytraceHitboxesUpdated = false;
      _activeCollisionsUnmodifiable =
          collisionsCache.activeCollisions.toList(growable: false);
      _activeChecked = List<List<bool>>.filled(
        _activeCollisionsUnmodifiable.length,
        List<bool>.filled(_activeCollisionsUnmodifiable.length, false),
      );
      _activeCheckedRecreated = true;
      for (var i = 0; i < _activeCollisionsUnmodifiable.length; i++) {
        _activeCollisionsUnmodifiable[i].broadphaseActiveIndex = i;
      }
      collisionsCache.activeUnmodifiableCacheClear();
    }
    if (collisionsCache.passiveCollisionsChanged) {
      _raytraceHitboxesUpdated = false;
      collisionsCache.passiveUnmodifiableCacheClear();
    }
  }

  Iterable<CollisionProspect<ShapeHitbox>> querySubset(
    List<CollisionProspect<ShapeHitbox>?> potentials,
  ) {
    _potentials.clear();
    for (final tuple in potentials) {
      if (tuple == null) {
        break;
      }
      ShapeHitbox componentHitbox;
      GroupHitbox groupBox;

      if (tuple.a is GroupHitbox && tuple.b is GroupHitbox) {
        throw 'not implemented';
      }

      if (tuple.a is GroupHitbox) {
        groupBox = tuple.a as GroupHitbox;
        componentHitbox = tuple.b;
      } else {
        groupBox = tuple.b as GroupHitbox;
        componentHitbox = tuple.a;
      }
      if (componentHitbox is! BoundingHitbox) {
        continue;
      }

      final cell = groupBox.parentWithGridSupport?.currentCell;
      if (cell == null) {
        continue;
      }
      final hitboxes = optimizedCollisionsByGroupBox[cell]?[groupBox]?.hitboxes;
      if (hitboxes == null || hitboxes.isEmpty) {
        continue;
      }

      _compareItemWithPotentials(componentHitbox, hitboxes, null, true);
    }

    return _potentials.values;
  }

  @override
  Iterable<CollisionProspect<ShapeHitbox>> query() {
    _potentials.clear();
    _prospectPoolIndex = 0;
    if (_activeCheckedRecreated) {
      _activeCheckedRecreated = false;
    } else {
      for (final list in _activeChecked) {
        list.fillRange(0, list.length, false);
      }
    }
    for (final activeItem in _activeCollisionsUnmodifiable) {
      final withGridSupport = activeItem.parentWithGridSupport;
      if (withGridSupport == null ||
          activeItem.isRemoving ||
          activeItem.parent == null ||
          activeItem is! BoundingHitbox) {
        continue;
      }

      if (activeItem.collisionCheckFrequency != -1) {
        if (!hasCollisionsLastTime.contains(activeItem)) {
          if (activeItem.collisionCheckCounter <
              activeItem.collisionCheckFrequency) {
            activeItem.collisionCheckCounter += dt;
            continue;
          } else {
            activeItem.collisionCheckCounter = 0;
          }
        }
      }

      final currentCell = withGridSupport.currentCell;
      if (currentCell == null) {
        continue;
      }

      if (currentCell.hasOutOfBoundsComponents) {
        for (final cell in currentCell.neighboursAndMe) {
          if (cell == null) {
            continue;
          }

          _compareCellItems(activeItem, cell, isPotentialActive: false);
          _compareCellItems(activeItem, cell, isPotentialActive: true);
        }
      } else {
        _compareCellItems(activeItem, currentCell, isPotentialActive: false);
        _compareCellItems(activeItem, currentCell, isPotentialActive: true);
      }
    }

    return _potentials.values;
  }

  void _compareCellItems(
    BoundingHitbox activeItem,
    Cell cell, {
    required bool isPotentialActive,
  }) {
    final itemsActiveByType = isPotentialActive
        ? collisionsCache.activeCollisionsByCell[cell]
        : collisionsCache.passiveCollisionsByCell[cell];
    if (itemsActiveByType != null) {
      for (final entry in itemsActiveByType.entries) {
        final type = entry.key;
        final canToCollide = comparator.globalTypeCheck(
          activeItem.runtimeType,
          type,
          potentialCanBeActive: isPotentialActive,
        );
        if (canToCollide) {
          final unmodifiableList = collisionsCache.unmodifiableCacheStore(
            cell,
            type,
            entry.value,
            isActive: isPotentialActive,
          );

          _compareItemWithPotentials(
            activeItem,
            unmodifiableList,
            isPotentialActive ? _activeChecked : null,
          );
        }
      }
    }
  }

  void _compareItemWithPotentials(
    BoundingHitbox activeItem,
    List<ShapeHitbox> potentials, [
    List<List<bool>>? alreadyChecked,
    bool excludePureTypeCheck = false,
  ]) {
    final activeParent = activeItem.hitboxParent;
    final potentialsLength = potentials.length;
    for (var i = 0; i < potentialsLength; i++) {
      final potential = potentials[i];
      if (potential.parent == null) {
        continue;
      }
      final potentialParent = potential.hitboxParent;
      if (!activeItem.allowSiblingCollision &&
          !potential.allowSiblingCollision &&
          potentialParent == activeParent) {
        continue;
      }
      if (alreadyChecked != null && potential.broadphaseActiveIndex != -1) {
        try {
          final isChecked = alreadyChecked[activeItem.broadphaseActiveIndex]
              [potential.broadphaseActiveIndex];
          if (isChecked) {
            continue;
          } else {
            alreadyChecked[potential.broadphaseActiveIndex]
                [activeItem.broadphaseActiveIndex] = true;
          }
        } on RangeError catch (_) {
          if (kDebugMode) {
            print('Invalid index on active check!');
          }
        }
      }
      if (excludePureTypeCheck) {
        if (activeItem.doExtendedTypeCheck) {
          final canToCollide = activeItem.getBroadphaseCheckCache(potential) ??
              _runExternalBroadphaseCheck(activeItem, potential);
          if (!canToCollide) {
            continue;
          }
        }
      } else {
        final canToCollide = _canPairToCollide(
          activeItem,
          activeParent,
          potential,
          potentialParent,
        );

        if (!canToCollide) {
          continue;
        }
      }

      final distanceCloseEnough = _minimumDistanceCheck(
        activeItem,
        potential,
      );
      if (distanceCloseEnough == false) {
        continue;
      }

      _prospectPoolIndex++;
      if (_prospectPool.length <= _prospectPoolIndex) {
        _prospectPool.expand(_dummyHitbox);
      }
      final prospect = _prospectPool[_prospectPoolIndex]
        ..set(
          activeItem,
          potential,
        );
      _potentials[prospect.hash] = prospect;
    }
  }

  bool _canPairToCollide(
    BoundingHitbox activeItem,
    PositionComponent activeParent,
    ShapeHitbox potentialItem,
    PositionComponent potentialParent,
  ) {
    var canToCollide = true;

    if (potentialItem is BoundingHitbox) {
      canToCollide = comparator.componentInternalTypeCheck(
        activeItem,
        potentialItem,
      );

      if (canToCollide &&
          activeParent is PureTypeCheckInterface &&
          potentialParent is PureTypeCheckInterface) {
        if (potentialParent is CellLayer) {
          if (potentialParent.primaryComponentType == null) {
            if (kDebugMode) {
              print('Possible collision with CellLayer with no components');
            }
            canToCollide = false;
          } else {
            canToCollide = comparator.globalTypeCheck(
              activeParent.runtimeType,
              potentialParent.primaryComponentType!,
            );
          }
        } else {
          canToCollide = comparator.componentFullTypeCheck(
            activeParent as PureTypeCheckInterface,
            potentialParent as PureTypeCheckInterface,
          );
        }
      }

      /// 3. Run extended type check for components - as for ordinary hitbox
      if (canToCollide && activeItem.doExtendedTypeCheck) {
        canToCollide = activeItem.getBroadphaseCheckCache(potentialItem) ??
            _runExternalBroadphaseCheck(activeItem, potentialItem);
      }
    } else if (activeItem.doExtendedTypeCheck) {
      /// This is default extended type check for hitbox. It invokes into
      /// hitbox, then propagating to hitboxParent, then propagating to
      /// parents recursively until end of components tree. This cycle stops
      /// at overridden function without call of "super"
      canToCollide = activeItem.getBroadphaseCheckCache(potentialItem) ??
          _runExternalBroadphaseCheck(activeItem, potentialItem);
    }

    return canToCollide;
  }

  void pureTypeCheckWarmUp(List<PositionComponent> components) {
    final result = <int, bool>{};
    for (var i = 0; i < components.length; i++) {
      final active = components[i];
      for (var j = 0; j < components.length; j++) {
        final potential = components[j];
        var canToCollide = true;
        if (active is PureTypeCheckInterface &&
            potential is PureTypeCheckInterface) {
          canToCollide = comparator.componentFullTypeCheck(
            active as PureTypeCheckInterface,
            potential as PureTypeCheckInterface,
          );
        }
        //store result here
        final key =
            active.runtimeType.hashCode & potential.runtimeType.hashCode;
        result[key] = canToCollide;
      }
    }

    _bloomFilterProvider.init(result);
  }

  bool _minimumDistanceCheck(
    BoundingHitbox activeItem,
    ShapeHitbox potential,
  ) {
    if (activeItem.parent is DebuggerPause) {
      //print('123');
    }
    final activeItemCenter = activeItem.aabbCenter;
    final potentialCenter = potential.aabbCenter;
    var minDistanceX = 0.0;
    var minDistanceY = 0.0;

    var potentialFastDistanceCheckAvailable = true;
    if (potential is BoundingHitbox) {
      potentialFastDistanceCheckAvailable =
          potential.isFastDistanceCheckAvailable;
    }

    if (potential is BoundingHitbox &&
        activeItem.isDistanceCallbackEnabled &&
        potential.isDistanceCallbackEnabled) {
      minDistanceX =
          activeItem.minCollisionDistanceX + potential.minCollisionDistanceX;
      minDistanceY =
          activeItem.minCollisionDistanceY + potential.minCollisionDistanceY;

      final diffX = activeItemCenter.x - potentialCenter.x;
      final diffY = activeItemCenter.y - potentialCenter.y;

      final distanceX = diffX < 0 ? -diffX : diffX;
      final distanceY = diffY < 0 ? -diffY : diffY;

      final component = activeItem.parentWithGridSupport;
      final other = potential.parentWithGridSupport;
      if (component != null && other != null) {
        component.onCalculateDistance(other, distanceX, distanceY);
        other.onCalculateDistance(component, distanceX, distanceY);
      }

      if (distanceX < minDistanceX && distanceY < minDistanceY) {
        return true;
      }
      return false;
    } else {
      if (_doSkipDistance(activeItem) && _doSkipDistance(potential)) {
        var skipTimes = activeItem.broadphaseMinimumDistanceSkip[potential];
        if (skipTimes != null && skipTimes != 0) {
          skipTimes--;
          activeItem.broadphaseMinimumDistanceSkip[potential] = skipTimes;
          return false;
        }
      }

      if (activeItem.isFastDistanceCheckAvailable &&
          potentialFastDistanceCheckAvailable) {
        final (canCollideFast, distanceX, distanceY) =
            _fastDistanceCheck(activeItemCenter, potentialCenter);
        if (canCollideFast) {
          minDistanceX = activeItem.minCollisionDistanceX;
          minDistanceY = activeItem.minCollisionDistanceY;

          if (potential is BoundingHitbox) {
            minDistanceX += potential.minCollisionDistanceX;
            minDistanceY += potential.minCollisionDistanceY;
          } else {
            minDistanceX += potential.size.x / 2;
            minDistanceY += potential.size.y / 2;
          }
          if (distanceX < minDistanceX && distanceY < minDistanceY) {
            return true;
          }
          return false;
        } else {
          if (_doSkipDistance(activeItem) && _doSkipDistance(potential)) {
            final parentSpeed = activeItem.parentSpeedGetter?.call();
            if (parentSpeed != null && parentSpeed > 0) {
              final skipTimes =
                  min(distanceX / parentSpeed, distanceY / parentSpeed).floor();
              activeItem.broadphaseMinimumDistanceSkip[potential] = skipTimes;
            }
          }
          return false;
        }
      } else {
        final diffX = activeItemCenter.x - potentialCenter.x;
        final diffY = activeItemCenter.y - potentialCenter.y;

        final distanceX = diffX < 0 ? -diffX : diffX;
        final distanceY = diffY < 0 ? -diffY : diffY;

        minDistanceX = activeItem.minCollisionDistanceX;
        minDistanceY = activeItem.minCollisionDistanceY;

        if (potential is BoundingHitbox) {
          minDistanceX += potential.minCollisionDistanceX;
          minDistanceY += potential.minCollisionDistanceY;
        } else {
          minDistanceX += potential.size.x / 2;
          minDistanceY += potential.size.y / 2;
        }
        if (distanceX < minDistanceX && distanceY < minDistanceY) {
          return true;
        }
        return false;
      }
    }
  }

  bool _doSkipDistance(ShapeHitbox item) =>
      (item is BoundingHitbox && item.collisionCheckFrequency <= 0) ||
      item is! BoundingHitbox;

  (bool, double, double) _fastDistanceCheck(
    Vector2 activeItemCenter,
    Vector2 potentialCenter,
  ) {
    final diffX = activeItemCenter.x - potentialCenter.x;
    final distanceX = diffX < 0 ? -diffX : diffX;
    if (distanceX < fastDistanceCheckMinX) {
      final diffY = activeItemCenter.y - potentialCenter.y;
      final distanceY = diffY < 0 ? -diffY : diffY;
      if (distanceY < fastDistanceCheckMinY) {
        return (true, distanceX, distanceY);
      }
    }

    return (false, 0, 0);
  }

  bool _runExternalBroadphaseCheck(
      BoundingHitbox active, ShapeHitbox potential) {
    if (active is GroupHitbox || potential is GroupHitbox) {
      return true;
    }
    final canToCollide = extendedTypeCheck(active, potential);
    active.storeBroadphaseCheckCache(potential, canToCollide);

    return canToCollide;
  }

  @override
  void remove(ShapeHitbox item) {
    final checkCache = broadphaseCheckCache[item];
    if (checkCache != null) {
      for (final hitbox in checkCache.keys) {
        if (hitbox is BoundingHitbox) {
          hitbox.removeBroadphaseCheckItem(item);
        } else {
          broadphaseCheckCache[hitbox]?.remove(item);
        }
      }
      broadphaseCheckCache.remove(item);
    }
    hasCollisionsLastTime.remove(item);
  }

  @internal
  void saveHitboxCell(ShapeHitbox hitbox, Cell? cell, [Cell? oldCell]) {
    if (oldCell != null) {
      scheduledOperations.add(
        ScheduledHitboxOperation.removeFromAll(
          hitbox: hitbox,
          cell: oldCell,
        ),
      );
    }
    if (cell != null) {
      scheduledOperations.add(
        ScheduledHitboxOperation.addToAll(
          hitbox: hitbox,
          cell: cell,
        ),
      );
    }
  }

  @internal
  void updateHitboxIndexes(ShapeHitbox hitbox, [Cell? oldCell]) {
    if (oldCell != null) {
      scheduledOperations.addAll([
        ScheduledHitboxOperation.removeActive(hitbox: hitbox, cell: oldCell),
        ScheduledHitboxOperation.removePassive(hitbox: hitbox, cell: oldCell),
      ]);
    }
    final currentCell = hitbox.parentWithGridSupport?.currentCell;
    if (currentCell != null) {
      switch (hitbox.collisionType) {
        case CollisionType.active:
          scheduledOperations.add(
            ScheduledHitboxOperation.addActive(
              hitbox: hitbox,
              cell: currentCell,
            ),
          );
          scheduledOperations.add(
            ScheduledHitboxOperation.removePassive(
              hitbox: hitbox,
              cell: currentCell,
            ),
          );
          break;
        case CollisionType.passive:
          scheduledOperations.add(
            ScheduledHitboxOperation.removeActive(
              hitbox: hitbox,
              cell: currentCell,
            ),
          );
          scheduledOperations.add(
            ScheduledHitboxOperation.addPassive(
              hitbox: hitbox,
              cell: currentCell,
            ),
          );
          break;
        case CollisionType.inactive:
          scheduledOperations.add(
            ScheduledHitboxOperation.removeActive(
              hitbox: hitbox,
              cell: currentCell,
            ),
          );
          scheduledOperations.add(
            ScheduledHitboxOperation.removePassive(
              hitbox: hitbox,
              cell: currentCell,
            ),
          );
          break;
      }
    }
  }

  @override
  void add(ShapeHitbox item) => throw UnimplementedError();

  bool _raytraceHitboxesUpdated = false;

  bool get raytraceHitboxUpdated => _raytraceHitboxesUpdated;
  Rect? _activeCellRect;
  final _raytraceHitboxes = <ShapeHitbox>{};
  RayTraceMode rayTraceMode = RayTraceMode.groupedHitboxes;

  @override
  List<ShapeHitbox> get items {
    final activeCell = spatialGrid.currentCell;
    if (activeCell == null) {
      return <ShapeHitbox>[];
    }
    if (_activeCellRect == activeCell.rect && _raytraceHitboxesUpdated) {
      return _raytraceHitboxes.toList(growable: false);
    } else {
      _raytraceHitboxes.clear();
      _activeCellRect = activeCell.rect;
      final cells = spatialGrid.activeRadiusCells;
      for (final cell in cells) {
        final collisions = collisionsCache.allCollisionsByCell[cell];
        if (collisions == null) {
          continue;
        }

        for (final hitbox in collisions) {
          if (hitbox.parent is CellLayer) {
            continue;
          }
          if (rayTraceMode == RayTraceMode.allHitboxes) {
            if (hitbox is GroupHitbox) {
              continue;
            }
          } else {
            if (hitbox is BoundingHitbox &&
                hitbox.optimized &&
                hitbox.group != null) {
              _raytraceHitboxes.add(hitbox.group!);
              continue;
            }
          }
          _raytraceHitboxes.add(hitbox);
        }
      }
      _raytraceHitboxesUpdated = true;
    }

    return _raytraceHitboxes.toList(growable: false);
  }

  void dispose() {
    scheduledOperations.clear();
    broadphaseCheckCache.clear();
    comparator.clear();
    hasCollisionsLastTime.clear();
    optimizedCollisionsByGroupBox.clear();
    collisionsCache.clear();
  }
}
