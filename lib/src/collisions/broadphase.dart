import 'dart:collection';
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/collision_optimizer.dart';
import 'package:meta/meta.dart';

typedef ExternalMinDistanceCheckSpatialGrid = bool Function(
  ShapeHitbox activeItem,
  ShapeHitbox potential,
);

typedef PureTypeCheck = bool Function(
  Type activeItemType,
  Type potentialItemType,
);

typedef ComponentExternalTypeCheck = bool Function(
  PositionComponent first,
  PositionComponent second,
);

mixin DebuggerPause {}

/// Performs Quad Tree broadphase check.
///
/// See [HasQuadTreeCollisionDetection.initializeCollisionDetection] for a
/// detailed description of its initialization parameters.
class SpatialGridBroadphase<T extends Hitbox<T>> extends Broadphase<T> {
  SpatialGridBroadphase({
    required this.spatialGrid,
    required this.extendedTypeCheck,
    this.globalPureTypeCheck,
  }) {
    dispose();
    fastDistanceCheckMinX = spatialGrid.blockSize.width / 3;
    fastDistanceCheckMinY = spatialGrid.blockSize.height / 3;
  }

  final SpatialGrid spatialGrid;

  @protected
  final activeCollisions = HashSet<T>();

  @internal
  final passiveCollisionsByCell = <Cell, HashSet<ShapeHitbox>>{};

  @internal
  final activeCollisionsByCell = <Cell, HashSet<ShapeHitbox>>{};

  @internal
  final optimizedCollisionsByGroupBox =
      <Cell, Map<GroupHitbox, OptimizedCollisionList>>{};

  @internal
  double dt = 0;

  final hasCollisionsLastTime = HashSet<ShapeHitbox>();

  ExternalBroadphaseCheck extendedTypeCheck;

  PureTypeCheck? globalPureTypeCheck;

  final _checkByTypeCache = HashMap<Type, Map<Type, bool>>();

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
    for (final operation in scheduledOperations) {
      if (operation.add) {
        final cell = operation.cell;
        if (operation.active) {
          activeCollisions.add(operation.hitbox as T);
          var list = activeCollisionsByCell[cell];
          list ??= activeCollisionsByCell[cell] = HashSet<ShapeHitbox>();
          list.add(operation.hitbox);
        } else {
          var list = passiveCollisionsByCell[cell];
          list ??= passiveCollisionsByCell[cell] = HashSet<ShapeHitbox>();
          list.add(operation.hitbox);
        }
      } else {
        final cell = operation.cell;
        if (operation.active) {
          activeCollisions.remove(operation.hitbox as T);
          final cellCollisions = activeCollisionsByCell[cell];
          if (cellCollisions != null) {
            cellCollisions.remove(operation.hitbox);
            if (cellCollisions.isEmpty) {
              activeCollisionsByCell.remove(cell);
            }
          }
        } else {
          final cellCollisions = passiveCollisionsByCell[cell];
          if (cellCollisions != null) {
            cellCollisions.remove(operation.hitbox);
            if (cellCollisions.isEmpty) {
              passiveCollisionsByCell.remove(cell);
            }
          }
        }
      }
    }
    scheduledOperations.clear();
  }

  HashSet<CollisionProspect<T>> querySubset(
    HashSet<CollisionProspect<ShapeHitbox>> potentials,
  ) {
    final result = HashSet<CollisionProspect<T>>();
    for (final tuple in potentials) {
      RectangleHitbox componentHitbox;
      GroupHitbox groupBox;

      if (tuple.a is GroupHitbox && tuple.b is GroupHitbox) {
        throw 'not implemented';
      }

      if (tuple.a is GroupHitbox) {
        groupBox = tuple.a as GroupHitbox;
        componentHitbox = tuple.b as RectangleHitbox;
      } else {
        groupBox = tuple.b as GroupHitbox;
        componentHitbox = tuple.a as RectangleHitbox;
      }

      final cell = groupBox.parentWithGridSupport?.currentCell;
      if (cell == null) {
        continue;
      }
      final hitboxes = optimizedCollisionsByGroupBox[cell]?[groupBox]?.hitboxes;
      if (hitboxes == null || hitboxes.isEmpty) {
        continue;
      }

      _compareItemWithPotentials(componentHitbox, hitboxes, result, null, true);
    }

    return result;
  }

  @override
  HashSet<CollisionProspect<T>> query() {
    final result = HashSet<CollisionProspect<T>>();
    final activeChecked = HashMap<ShapeHitbox, HashSet<ShapeHitbox>>();
    for (final activeItem in activeCollisions) {
      final asShapeItem = activeItem as ShapeHitbox;
      final withGridSupport = asShapeItem.parentWithGridSupport;
      if (withGridSupport == null ||
          asShapeItem.isRemoving ||
          asShapeItem.parent == null) {
        continue;
      }

      if (activeItem is BoundingHitbox) {
        final boundingHitbox = activeItem as BoundingHitbox;
        if (boundingHitbox.collisionCheckFrequency != -1) {
          if (!hasCollisionsLastTime.contains(asShapeItem)) {
            if (boundingHitbox.collisionCheckCounter <
                boundingHitbox.collisionCheckFrequency) {
              boundingHitbox.collisionCheckCounter += dt;
              continue;
            } else {
              boundingHitbox.collisionCheckCounter = 0;
            }
          }
        }
      }

      var cellsToCheck = <Cell>[];
      final currentCell = withGridSupport.currentCell;
      if (currentCell == null) {
        continue;
      }

      if (currentCell.hasOutOfBoundsComponents) {
        cellsToCheck = currentCell.neighboursAndMe;
      } else {
        cellsToCheck = [currentCell];
      }

      for (final cell in cellsToCheck) {
        final items = passiveCollisionsByCell[cell];
        if (items != null && items.isNotEmpty) {
          _compareItemWithPotentials(
            asShapeItem,
            items,
            result,
          );
        }

        final itemsActive = activeCollisionsByCell[cell];
        if (itemsActive != null && itemsActive.isNotEmpty) {
          _compareItemWithPotentials(
            asShapeItem,
            itemsActive,
            result,
            activeChecked,
          );
        }
      }
    }
    return result;
  }

  void _compareItemWithPotentials(
    ShapeHitbox activeItem,
    Set<ShapeHitbox> potentials,
    HashSet<CollisionProspect<T>> result, [
    HashMap<ShapeHitbox, HashSet<ShapeHitbox>>? activeChecked,
    bool excludePureTypeCheck = false,
  ]) {
    final activeParent = activeItem.hitboxParent;
    for (final potential in potentials) {
      final potentialParent = potential.hitboxParent;
      if (potentialParent == activeParent) {
        continue;
      }
      if (activeChecked != null) {
        if (activeChecked[activeItem]?.contains(potential) ?? false) {
          continue;
        } else {
          var checked = activeChecked[potential];
          checked ??= activeChecked[potential] = HashSet<ShapeHitbox>();
          checked.add(activeItem);
        }
      }
      if (excludePureTypeCheck) {
        final canToCollide = activeItem.getBroadphaseCheckCache(potential) ??
            _runExternalBroadphaseCheck(activeItem, potential);
        if (!canToCollide) {
          continue;
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

      result.add(CollisionProspect(activeItem as T, potential as T));
    }
  }

  bool _canPairToCollide(ShapeHitbox activeItem, PositionComponent activeParent,
      ShapeHitbox potentialItem, PositionComponent potentialParent) {
    var canToCollide = true;

    if (activeItem is BoundingHitbox) {
      /// 1. Checking types of hitboxes only (also checking type cache);
      ///    Also checking GroupHitbox elements type (component!);
      var potentialType = potentialItem.runtimeType;
      if (potentialParent is CellLayer) {
        potentialType =
            potentialParent.primaryHitboxCollisionType ?? potentialType;
      }
      final cache =
          _getPureTypeCheckCache(activeItem.runtimeType, potentialType);
      if (cache == null) {
        canToCollide =
            _pureTypeCheckHitbox(activeItem, potentialItem, potentialType);
        _saveCheckByPureTypeCache(
          activeItem.runtimeType,
          potentialType,
          canToCollide,
        );
      } else {
        canToCollide = cache;
      }

      /// 2. Checking types of components itself.
      if (canToCollide) {
        if (potentialParent is! CellLayer) {
          potentialType = potentialParent.runtimeType;
        }
        final activeItemParentType = activeParent.runtimeType;
        final cache =
            _getPureTypeCheckCache(activeItemParentType, potentialType);

        if (cache == null) {
          canToCollide = _pureTypeCheckComponent(activeParent, potentialParent);
          _saveCheckByPureTypeCache(
            activeItemParentType,
            potentialType,
            canToCollide,
          );
        } else {
          canToCollide = cache;
        }
      }

      /// 3. Run extended type check for components - as for ordinary hitbox
      if (canToCollide) {
        canToCollide = activeItem.getBroadphaseCheckCache(potentialItem) ??
            _runExternalBroadphaseCheck(activeItem, potentialItem);
      }
    } else {
      /// This is default extended type check for hitbox. It invokes into
      /// hitbox, then propagating to hitboxParent, then propagating to
      /// parents recursively until end of components tree. This cycle stops
      /// at overridden function without call of "super"
      canToCollide = activeItem.getBroadphaseCheckCache(potentialItem) ??
          _runExternalBroadphaseCheck(activeItem, potentialItem);
    }

    return canToCollide;
  }

  bool _globalTypeCheck(Type activeType, Type potentialType) {
    if (globalPureTypeCheck == null) {
      return true;
    }

    return globalPureTypeCheck!.call(
          activeType,
          potentialType,
        ) &&
        globalPureTypeCheck!.call(
          potentialType,
          activeType,
        );
  }

  bool _pureTypeCheckHitbox(
    BoundingHitbox active,
    ShapeHitbox potential,
    Type potentialType,
  ) {
    final canToCollide = _globalTypeCheck(active.runtimeType, potentialType);

    if (canToCollide) {
      final activeCanCollide = active.pureTypeCheck(potentialType);
      var potentialCanCollide = true;
      if (potential is BoundingHitbox) {
        potentialCanCollide = potential.pureTypeCheck(active.runtimeType);
      }
      return activeCanCollide && potentialCanCollide;
    }
    return canToCollide;
  }

  bool _pureTypeCheckComponent(
    PositionComponent active,
    PositionComponent potential,
  ) {
    final canToCollide =
        _globalTypeCheck(active.runtimeType, potential.runtimeType);

    if (canToCollide) {
      var activeCanCollide = true;
      if (active is HasGridSupport) {
        activeCanCollide = active.pureTypeCheck(potential);
      }
      var potentialCanCollide = true;
      if (potential is HasGridSupport) {
        potentialCanCollide = potential.pureTypeCheck(active);
      }
      return activeCanCollide && potentialCanCollide;
    }
    return canToCollide;
  }

  bool? _getPureTypeCheckCache(Type activeType, Type potentialType) =>
      _checkByTypeCache[activeType]?[potentialType] ??
      _checkByTypeCache[potentialType]?[activeType];

  void _saveCheckByPureTypeCache(
    Type activeType,
    Type potentialType,
    bool canToCollide,
  ) {
    var itemTypeCache = _checkByTypeCache[activeType];
    itemTypeCache ??= _checkByTypeCache[activeType] = <Type, bool>{};
    itemTypeCache[potentialType] = canToCollide;

    var potentialTypeCache = _checkByTypeCache[potentialType];
    potentialTypeCache ??= _checkByTypeCache[potentialType] = <Type, bool>{};
    potentialTypeCache[activeType] = canToCollide;
  }

  bool _minimumDistanceCheck(
    ShapeHitbox activeItem,
    ShapeHitbox potential,
  ) {
    if (activeItem.parent is DebuggerPause) {
      //print('123');
    }
    final activeItemCenter = activeItem.aabbCenter;
    final potentialCenter = potential.aabbCenter;
    var minDistanceX = 0.0;
    var minDistanceY = 0.0;

    var activeFastDistanceCheckAvailable = true;
    var potentialFastDistanceCheckAvailable = true;
    if (activeItem is BoundingHitbox) {
      activeFastDistanceCheckAvailable =
          activeItem.isFastDistanceCheckAvailable;
    }
    if (potential is BoundingHitbox) {
      potentialFastDistanceCheckAvailable =
          potential.isFastDistanceCheckAvailable;
    }

    if (activeItem is BoundingHitbox &&
        potential is BoundingHitbox &&
        activeItem.isDistanceCallbackEnabled &&
        potential.isDistanceCallbackEnabled) {
      minDistanceX =
          activeItem.minCollisionDistanceX + potential.minCollisionDistanceX;
      minDistanceY =
          activeItem.minCollisionDistanceY + potential.minCollisionDistanceY;

      final distanceX = (activeItemCenter.x - potentialCenter.x).abs();
      final distanceY = (activeItemCenter.y - potentialCenter.y).abs();

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
      if (activeItem is BoundingHitbox) {
        var skipTimes = activeItem.broadphaseMinimumDistanceSkip[potential];
        if (skipTimes != null) {
          if (skipTimes <= 0) {
            activeItem.broadphaseMinimumDistanceSkip.remove(potential);
          } else {
            skipTimes--;
            activeItem.broadphaseMinimumDistanceSkip[potential] = skipTimes;
            return false;
          }
        }
      }

      if (activeFastDistanceCheckAvailable &&
          potentialFastDistanceCheckAvailable) {
        final (canCollideFast, distanceX, distanceY) =
            _fastDistanceCheck(activeItemCenter, potentialCenter);
        if (canCollideFast) {
          if (activeItem is BoundingHitbox) {
            minDistanceX = activeItem.minCollisionDistanceX;
            minDistanceY = activeItem.minCollisionDistanceY;
          } else {
            minDistanceX = activeItem.size.x / 2;
            minDistanceY = activeItem.size.y / 2;
          }

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
          if (activeItem is BoundingHitbox) {
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
        final distanceX = (activeItemCenter.x - potentialCenter.x).abs();
        final distanceY = (activeItemCenter.y - potentialCenter.y).abs();

        if (activeItem is BoundingHitbox) {
          minDistanceX = activeItem.minCollisionDistanceX;
          minDistanceY = activeItem.minCollisionDistanceY;
        } else {
          minDistanceX = activeItem.size.x / 2;
          minDistanceY = activeItem.size.y / 2;
        }

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

  (bool, double, double) _fastDistanceCheck(
    Vector2 activeItemCenter,
    Vector2 potentialCenter,
  ) {
    final distanceX = (activeItemCenter.x - potentialCenter.x).abs();
    final distanceY = (activeItemCenter.y - potentialCenter.y).abs();

    if (distanceX < fastDistanceCheckMinX &&
        distanceY < fastDistanceCheckMinY) {
      return (true, distanceX, distanceY);
    }
    return (false, 0, 0);
  }

  bool _runExternalBroadphaseCheck(ShapeHitbox active, ShapeHitbox potential) {
    if (active is GroupHitbox || potential is GroupHitbox) {
      return true;
    }
    final canToCollide = extendedTypeCheck(active, potential);
    if (active is BoundingHitbox) {
      active.storeBroadphaseCheckCache(potential, canToCollide);
    } else {
      active.storeBroadphaseCheckCache(potential, canToCollide);
    }

    return canToCollide;
  }

  @override
  void remove(T item) {
    final checkCache = broadphaseCheckCache[item];
    if (checkCache != null) {
      for (final hitbox in checkCache.keys) {
        if (hitbox is BoundingHitbox) {
          hitbox.removeBroadphaseCheckItem(item as ShapeHitbox);
        } else {
          broadphaseCheckCache[hitbox]?.remove(item);
        }
      }
      broadphaseCheckCache.remove(item);
    }
    hasCollisionsLastTime.remove(item);
  }

  @internal
  void updateHitboxIndexes(ShapeHitbox hitbox, [Cell? oldCell]) {
    if (oldCell != null) {
      scheduledOperations.addAll([
        ScheduledHitboxOperation.removeActive(hitbox: hitbox, cell: oldCell),
        ScheduledHitboxOperation.removePassive(hitbox: hitbox, cell: oldCell)
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
  void add(T item) => throw UnimplementedError();

  @override
  List<T> get items => throw UnimplementedError();

  void dispose() {
    scheduledOperations.clear();
    activeCollisions.clear();
    broadphaseCheckCache.clear();
    _checkByTypeCache.clear();
    hasCollisionsLastTime.clear();
    passiveCollisionsByCell.clear();
    activeCollisionsByCell.clear();
    optimizedCollisionsByGroupBox.clear();
  }
}

@internal
@immutable
class ScheduledHitboxOperation {
  const ScheduledHitboxOperation({
    required this.add,
    required this.active,
    required this.hitbox,
    required this.cell,
  });

  const ScheduledHitboxOperation.addActive({
    required this.hitbox,
    required this.cell,
  })  : add = true,
        active = true;

  const ScheduledHitboxOperation.addPassive({
    required this.hitbox,
    required this.cell,
  })  : add = true,
        active = false;

  const ScheduledHitboxOperation.removeActive({
    required this.hitbox,
    required this.cell,
  })  : add = false,
        active = true;

  const ScheduledHitboxOperation.removePassive({
    required this.hitbox,
    required this.cell,
  })  : add = false,
        active = false;

  final bool add;
  final bool active;
  final ShapeHitbox hitbox;
  final Cell cell;
}
