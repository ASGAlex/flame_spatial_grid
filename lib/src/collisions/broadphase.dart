import 'dart:collection';
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

import 'collision_optimizer.dart';

typedef ExternalMinDistanceCheckSpatialGrid = bool Function(
  ShapeHitbox activeItem,
  ShapeHitbox potential,
);

/// Performs Quad Tree broadphase check.
///
/// See [HasQuadTreeCollisionDetection.initializeCollisionDetection] for a
/// detailed description of its initialization parameters.
class SpatialGridBroadphase<T extends Hitbox<T>> extends Broadphase<T> {
  SpatialGridBroadphase({
    super.items,
    required this.spatialGrid,
    required this.broadphaseCheck,
    ExternalMinDistanceCheckSpatialGrid? minimumDistanceCheck,
  }) {
    this.minimumDistanceCheck = minimumDistanceCheck ?? _minimumDistanceCheck;
  }

  final SpatialGrid spatialGrid;

  @protected
  final activeCollisions = HashSet<T>();

  @protected
  final passiveCollisionsByCell = <Cell, HashSet<ShapeHitbox>>{};

  @protected
  final activeCollisionsByCell = <Cell, HashSet<ShapeHitbox>>{};

  final optimizedCollisionsByGroupBox =
      <Cell, Map<GroupHitbox, OptimizedCollisionList>>{};

  ExternalBroadphaseCheck broadphaseCheck;
  late ExternalMinDistanceCheckSpatialGrid minimumDistanceCheck;

  @internal
  final broadphaseCheckCache = HashMap<T, HashMap<T, bool>>();

  final _activePreviouslyChecked = HashMap<T, HashMap<T, bool>>();

  @internal
  final scheduledOperations = <ScheduledHitboxOperation>[];

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
          if (cell.state != CellState.suspended) {
            var list = passiveCollisionsByCell[cell];
            list ??= passiveCollisionsByCell[cell] = HashSet<ShapeHitbox>();
            list.add(operation.hitbox);
          }
        }
      } else {
        final cell = operation.cell;
        if (operation.active) {
          activeCollisions.remove(operation.hitbox as T);
          activeCollisionsByCell[cell]?.remove(operation.hitbox);
        } else {
          passiveCollisionsByCell[cell]?.remove(operation.hitbox);
        }
      }
    }
    scheduledOperations.clear();
  }

  HashSet<CollisionProspect<T>> querySubset(
      HashSet<CollisionProspect<ShapeHitbox>> potentials) {
    final result = HashSet<CollisionProspect<T>>();
    _activePreviouslyChecked.clear();
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
      if (cell == null) continue;
      final hitboxes =
          optimizedCollisionsByGroupBox[cell]?[groupBox]?.hitboxes.toList();
      if (hitboxes == null || hitboxes.isEmpty) continue;

      _compareItemWithPotentials(componentHitbox, hitboxes, result);
    }

    return result;
  }

  @override
  HashSet<CollisionProspect<T>> query() {
    final result = HashSet<CollisionProspect<T>>();
    _activePreviouslyChecked.clear();
    for (final activeItem in activeCollisions) {
      final asShapeItem = activeItem as ShapeHitbox;
      final withGridSupport = asShapeItem.parentWithGridSupport;
      if (withGridSupport == null ||
          asShapeItem.isRemoving ||
          asShapeItem.parent == null) continue;

      var cellsToCheck = <Cell>[];

      if (withGridSupport.isOutOfCellBounds) {
        cellsToCheck = withGridSupport.currentCell?.neighboursAndMe ?? [];
      } else {
        final cell = withGridSupport.currentCell;
        if (cell != null) {
          cellsToCheck = [cell];
        } else {
          cellsToCheck = [];
        }
      }

      final potentiallyCollide = <ShapeHitbox>[];
      if (cellsToCheck.isEmpty) continue;
      for (final cell in cellsToCheck) {
        final items = passiveCollisionsByCell[cell];
        if (items != null && items.isNotEmpty) {
          potentiallyCollide.addAll(items);
        }

        final itemsActive = activeCollisionsByCell[cell];
        if (itemsActive != null && itemsActive.isNotEmpty) {
          potentiallyCollide.addAll(itemsActive);
        }
      }
      _compareItemWithPotentials(asShapeItem, potentiallyCollide, result);
    }

    return result;
  }

  void _compareItemWithPotentials(ShapeHitbox asShapeItem,
      List<ShapeHitbox> potentials, HashSet<CollisionProspect<T>> result) {
    for (final potential in potentials) {
      if (potential.parent == asShapeItem.parent &&
          asShapeItem.parent != null) {
        continue;
      }
      final canToCollide = broadphaseCheckCache[asShapeItem]?[potential] ??
          _runExternalBroadphaseCheck(asShapeItem, potential);
      if (!canToCollide) {
        continue;
      }

      final distanceCloseEnough = minimumDistanceCheck.call(
        asShapeItem,
        potential,
      );
      if (distanceCloseEnough == false) {
        continue;
      }

      result.add(CollisionProspect(asShapeItem as T, potential as T));
    }
  }

  bool _minimumDistanceCheck(
    ShapeHitbox activeItem,
    ShapeHitbox potential,
  ) {
    final activeItemCenter = activeItem.aabbCenter;
    final potentialCenter = potential.aabbCenter;
    var minDistanceX = 0.0;
    var minDistanceY = 0.0;
    if (activeItem is BoundingHitbox && potential is BoundingHitbox) {
      minDistanceX = max(activeItem.minDistanceX, potential.minDistanceX);
      minDistanceY = max(activeItem.minDistanceY, potential.minDistanceY);
    } else {
      minDistanceX = max(activeItem.size.x, potential.size.x);
      minDistanceY = max(activeItem.size.y, potential.size.y);
    }
    if ((activeItemCenter.x - potentialCenter.x).abs() < minDistanceX &&
        (activeItemCenter.y - potentialCenter.y).abs() < minDistanceY) {
      return true;
    }
    return false;
  }

  bool _runExternalBroadphaseCheck(ShapeHitbox item0, ShapeHitbox item1) {
    if (item0 is GroupHitbox || item1 is GroupHitbox) {
      return true;
    }
    final canToCollide = broadphaseCheck(item0, item1);
    if (broadphaseCheckCache[item0 as T] == null) {
      broadphaseCheckCache[item0 as T] = HashMap<T, bool>();
    }
    broadphaseCheckCache[item0 as T]![item1 as T] = canToCollide;

    if (broadphaseCheckCache[item1 as T] == null) {
      broadphaseCheckCache[item1 as T] = HashMap<T, bool>();
    }
    broadphaseCheckCache[item1 as T]![item0 as T] = canToCollide;

    return canToCollide;
  }

  void clear() {
    activeCollisions.clear();
    broadphaseCheckCache.clear();
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
          scheduledOperations.add(ScheduledHitboxOperation.addActive(
              hitbox: hitbox, cell: currentCell));
          scheduledOperations.add(ScheduledHitboxOperation.removePassive(
              hitbox: hitbox, cell: currentCell));
          break;
        case CollisionType.passive:
          scheduledOperations.add(ScheduledHitboxOperation.removeActive(
              hitbox: hitbox, cell: currentCell));
          scheduledOperations.add(ScheduledHitboxOperation.addPassive(
              hitbox: hitbox, cell: currentCell));
          break;
        case CollisionType.inactive:
          scheduledOperations.add(ScheduledHitboxOperation.removeActive(
              hitbox: hitbox, cell: currentCell));
          scheduledOperations.add(ScheduledHitboxOperation.removePassive(
              hitbox: hitbox, cell: currentCell));
          break;
      }
    }
  }
}

@internal
@immutable
class ScheduledHitboxOperation {
  const ScheduledHitboxOperation(
      {required this.add,
      required this.active,
      required this.hitbox,
      required this.cell});

  const ScheduledHitboxOperation.addActive(
      {required this.hitbox, required this.cell})
      : add = true,
        active = true;

  const ScheduledHitboxOperation.addPassive(
      {required this.hitbox, required this.cell})
      : add = true,
        active = false;

  const ScheduledHitboxOperation.removeActive(
      {required this.hitbox, required this.cell})
      : add = false,
        active = true;

  const ScheduledHitboxOperation.removePassive(
      {required this.hitbox, required this.cell})
      : add = false,
        active = false;

  final bool add;
  final bool active;
  final ShapeHitbox hitbox;
  final Cell cell;
}
