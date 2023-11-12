import 'dart:collection';
import 'dart:math';
import 'dart:ui';

import 'package:dart_bloom_filter/dart_bloom_filter.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/optimized_collisions_list.dart';
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
class SpatialGridBroadphase extends Broadphase<ShapeHitbox> {
  SpatialGridBroadphase({
    required this.spatialGrid,
    required this.extendedTypeCheck,
    this.globalPureTypeCheck,
  }) {
    dispose();
    fastDistanceCheckMinX = spatialGrid.cellSize.width / 3;
    fastDistanceCheckMinY = spatialGrid.cellSize.height / 3;
  }

  final SpatialGrid spatialGrid;

  final _prospectPool = ProspectPool<ShapeHitbox>();
  var _prospectPoolIndex = 0;
  final _dummyHitbox = DummyHitbox();
  final _potentials = <int, CollisionProspect<ShapeHitbox>>{};

  @protected
  final activeCollisions = <ShapeHitbox>{};
  var _activeCollisionsUnmodifiable = <ShapeHitbox>[];
  var _activeChecked = <List<bool>>[];
  var _activeCheckedRecreated = false;

  @internal
  final allCollisionsByCell = <Cell, HashSet<ShapeHitbox>>{};

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

  final _checkByTypeCache = <int, bool>{};
  BloomFilter<int>? _checkByTypeCacheBloomTrue;
  BloomFilter<int>? _checkByTypeCacheBloomFalse;

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
    var activeCollisionsChanged = false;
    var passiveCollisionsChanged = false;
    for (final operation in scheduledOperations) {
      if (operation.add) {
        final cell = operation.cell;
        if (operation.all) {
          var list = allCollisionsByCell[cell];
          list ??= allCollisionsByCell[cell] = HashSet<ShapeHitbox>();
          list.add(operation.hitbox);
        } else {
          if (operation.active) {
            activeCollisions.add(operation.hitbox);
            var list = activeCollisionsByCell[cell];
            list ??= activeCollisionsByCell[cell] = HashSet<ShapeHitbox>();
            list.add(operation.hitbox);
            activeCollisionsChanged = true;
          } else {
            var list = passiveCollisionsByCell[cell];
            list ??= passiveCollisionsByCell[cell] = HashSet<ShapeHitbox>();
            list.add(operation.hitbox);
            passiveCollisionsChanged = true;
          }
        }
      } else {
        final cell = operation.cell;
        if (operation.all) {
          final cellCollisions = allCollisionsByCell[cell];
          if (cellCollisions != null) {
            cellCollisions.remove(operation.hitbox);
            if (cellCollisions.isEmpty) {
              allCollisionsByCell.remove(cell);
            }
          }
        } else {
          if (operation.active) {
            activeCollisions.remove(operation.hitbox);
            operation.hitbox.broadphaseActiveIndex = -1;
            activeCollisionsChanged = true;
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
              passiveCollisionsChanged = true;
            }
          }
        }
      }
    }
    scheduledOperations.clear();
    if (activeCollisionsChanged) {
      _activeCollisionsUnmodifiable = activeCollisions.toList(growable: false);
      _activeChecked = List<List<bool>>.filled(
        _activeCollisionsUnmodifiable.length,
        List<bool>.filled(_activeCollisionsUnmodifiable.length, false),
      );
      _activeCheckedRecreated = true;
      for (var i = 0; i < _activeCollisionsUnmodifiable.length; i++) {
        _activeCollisionsUnmodifiable[i].broadphaseActiveIndex = i;
      }
      _activeByCellUnmodifiable.clear();
    }
    if (passiveCollisionsChanged) {
      _passiveByCellUnmodifiable.clear();
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

  final _passiveByCellUnmodifiable = <Cell, List<ShapeHitbox>?>{};
  final _activeByCellUnmodifiable = <Cell, List<ShapeHitbox>?>{};

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
          activeItem.parent == null) {
        continue;
      }

      if (activeItem is BoundingHitbox) {
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
      }

      var cellsToCheck = <Cell?>[];
      final currentCell = withGridSupport.currentCell;
      if (currentCell == null) {
        continue;
      }

      if (currentCell.hasOutOfBoundsComponents) {
        cellsToCheck = currentCell.neighboursAndMe;
      } else {
        cellsToCheck = List<Cell>.filled(1, currentCell);
      }

      for (final cell in cellsToCheck) {
        if (cell == null) {
          continue;
        }
        var items = _passiveByCellUnmodifiable[cell];
        if (items == null) {
          items = passiveCollisionsByCell[cell]?.toList(growable: false);
          _passiveByCellUnmodifiable[cell] = items;
        }
        if (items != null && items.isNotEmpty) {
          _compareItemWithPotentials(
            activeItem,
            items,
          );
        }

        var itemsActive = _activeByCellUnmodifiable[cell];
        if (itemsActive == null) {
          itemsActive = activeCollisionsByCell[cell]?.toList(growable: false);
          _activeByCellUnmodifiable[cell] = itemsActive;
        }
        if (itemsActive != null && itemsActive.isNotEmpty) {
          _compareItemWithPotentials(
            activeItem,
            itemsActive,
            _activeChecked,
          );
        }
      }
    }

    return _potentials.values;
  }

  void _compareItemWithPotentials(
    ShapeHitbox activeItem,
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
        } on RangeError catch (e) {
          print('Invalid index on active check!');
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
      final CollisionProspect<ShapeHitbox> prospect;
      if (_prospectPool.length <= _prospectPoolIndex) {
        _prospectPool.expand(_dummyHitbox);
      }
      prospect = _prospectPool[_prospectPoolIndex]..set(activeItem, potential);
      _potentials[prospect.hash] = prospect;
    }
  }

  var _key1 = 0;
  var _canToCollide1 = true;
  var _key2 = 0;
  var _canToCollide2 = true;

  bool _canPairToCollide(
    ShapeHitbox activeItem,
    PositionComponent activeParent,
    ShapeHitbox potentialItem,
    PositionComponent potentialParent,
  ) {
    var canToCollide = true;

    if (activeItem is BoundingHitbox) {
      /// 1. Checking types of hitboxes only (also checking type cache);
      ///    Also checking GroupHitbox elements type (component!);
      var potentialType = potentialItem.runtimeType;
      if (potentialParent is CellLayer) {
        potentialType =
            potentialParent.primaryHitboxCollisionType ?? potentialType;
      }
      var key = activeItem.runtimeType.hashCode & potentialType.hashCode;
      if (key == _key1) {
        canToCollide = _canToCollide1;
      } else {
        _key1 = key;
        final bloomCheck = _bloomCacheCheck(key);
        if (bloomCheck == null) {
          final cache = _checkByTypeCache[key];
          if (cache == null) {
            canToCollide =
                _pureTypeCheckHitbox(activeItem, potentialItem, potentialType);
            _checkByTypeCache[key] = canToCollide;
          } else {
            canToCollide = cache;
          }
          _canToCollide1 = canToCollide;
        } else {
          _canToCollide1 = canToCollide = bloomCheck;
        }
      }

      /// 2. Checking types of components itself.
      if (canToCollide) {
        if (potentialParent is! CellLayer) {
          potentialType = potentialParent.runtimeType;
        }
        final activeItemParentType = activeParent.runtimeType;
        key = activeItemParentType.hashCode & potentialType.hashCode;
        if (key == _key2) {
          canToCollide = _canToCollide2;
        } else {
          _key2 = key;
          final bloomCheck = _bloomCacheCheck(key);
          if (bloomCheck == null) {
            final cache = _checkByTypeCache[key];

            if (cache == null) {
              canToCollide =
                  _pureTypeCheckComponent(activeParent, potentialParent);
              _checkByTypeCache[key] = canToCollide;
            } else {
              canToCollide = cache;
            }
            _canToCollide2 = canToCollide;
          } else {
            canToCollide = bloomCheck;
            _canToCollide2 = canToCollide;
          }
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

  bool _globalTypeCheck(
    Type activeType,
    Type potentialType,
    bool potentialCanBeActive,
  ) {
    if (globalPureTypeCheck == null) {
      return true;
    }

    final canCollide = globalPureTypeCheck!.call(
      activeType,
      potentialType,
    );
    if (potentialCanBeActive) {
      return canCollide &&
          globalPureTypeCheck!.call(
            potentialType,
            activeType,
          );
    }
    return canCollide;
  }

  bool _pureTypeCheckHitbox(
    BoundingHitbox active,
    ShapeHitbox potential,
    Type potentialType,
  ) {
    final canToCollide = _globalTypeCheck(
      active.runtimeType,
      potentialType,
      potential.canBeActive,
    );

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
    final canToCollide = _globalTypeCheck(
      active.runtimeType,
      potential.runtimeType,
      potential.canBeActive,
    );

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

  void pureTypeCheckWarmUp(List<PositionComponent> components) {
    final result = <int, bool>{};
    for (var i = 0; i < components.length; i++) {
      final active = components[i];
      for (var j = 0; j < components.length; j++) {
        final potential = components[j];
        var canToCollide = true;
        if (active is BoundingHitbox && potential is ShapeHitbox) {
          canToCollide =
              _pureTypeCheckHitbox(active, potential, potential.runtimeType);
        }
        if (canToCollide) {
          canToCollide = _pureTypeCheckComponent(active, potential);
        }
        //store result here
        final key =
            active.runtimeType.hashCode & potential.runtimeType.hashCode;
        result[key] = canToCollide;
      }
    }

    _checkByTypeCacheBloomTrue = BloomFilter<int>(result.length, 0.01);
    _checkByTypeCacheBloomFalse = BloomFilter<int>(result.length, 0.01);
    for (final item in result.entries) {
      if (item.value) {
        _checkByTypeCacheBloomTrue!.add(item: item.key);
      } else {
        _checkByTypeCacheBloomFalse!.add(item: item.key);
      }
    }
  }

  bool? _bloomCacheCheck(int key) {
    if (_checkByTypeCacheBloomTrue == null) {
      return null;
    }

    final collide = _checkByTypeCacheBloomTrue!.contains(item: key);
    if (collide) {
      final noCollide = _checkByTypeCacheBloomFalse!.contains(item: key);
      if (!noCollide) {
        return true;
      } else {
        return false;
      }
    } else {
      return false;
    }
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
      if (activeItem is BoundingHitbox &&
          _doSkipDistance(activeItem) &&
          _doSkipDistance(potential)) {
        var skipTimes = activeItem.broadphaseMinimumDistanceSkip[potential];
        if (skipTimes != null && skipTimes != 0) {
          skipTimes--;
          activeItem.broadphaseMinimumDistanceSkip[potential] = skipTimes;
          return false;
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
          if (activeItem is BoundingHitbox &&
              _doSkipDistance(activeItem) &&
              _doSkipDistance(potential)) {
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

  bool _doSkipDistance(ShapeHitbox item) =>
      (item is BoundingHitbox && item.collisionCheckFrequency <= 0) ||
      item is! BoundingHitbox;

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

  Rect? _activeCellRect;
  final _raytraceHitboxes = <ShapeHitbox>[];

  @override
  List<ShapeHitbox> get items {
    final activeCell = spatialGrid.currentCell;
    if (activeCell == null) {
      return <ShapeHitbox>[];
    }
    if (_activeCellRect == activeCell.rect) {
      return _raytraceHitboxes;
    } else {
      _raytraceHitboxes.clear();
      _activeCellRect = activeCell.rect;
      final cells = spatialGrid.activeRadiusCells;
      for (final cell in cells) {
        final collisions = allCollisionsByCell[cell];
        if (collisions != null) {
          for (final hitbox in collisions) {
            if (hitbox is GroupHitbox || hitbox.parent is CellLayer) {
              continue;
            }
            _raytraceHitboxes.add(hitbox);
          }
        }
      }
    }

    return _raytraceHitboxes;
  }

  void dispose() {
    scheduledOperations.clear();
    activeCollisions.clear();
    broadphaseCheckCache.clear();
    _checkByTypeCache.clear();
    hasCollisionsLastTime.clear();
    passiveCollisionsByCell.clear();
    activeCollisionsByCell.clear();
    allCollisionsByCell.clear();
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
    required this.all,
  });

  const ScheduledHitboxOperation.addActive({
    required this.hitbox,
    required this.cell,
  })  : add = true,
        active = true,
        all = false;

  const ScheduledHitboxOperation.addPassive({
    required this.hitbox,
    required this.cell,
  })  : add = true,
        active = false,
        all = false;

  const ScheduledHitboxOperation.removeActive({
    required this.hitbox,
    required this.cell,
  })  : add = false,
        active = true,
        all = false;

  const ScheduledHitboxOperation.removePassive({
    required this.hitbox,
    required this.cell,
  })  : add = false,
        active = false,
        all = false;

  const ScheduledHitboxOperation.addToAll({
    required this.hitbox,
    required this.cell,
  })  : add = true,
        active = false,
        all = true;

  const ScheduledHitboxOperation.removeFromAll({
    required this.hitbox,
    required this.cell,
  })  : add = false,
        active = false,
        all = true;

  final bool add;
  final bool active;
  final bool all;
  final ShapeHitbox hitbox;
  final Cell cell;
}

class DummyHitbox extends BoundingHitbox {}
