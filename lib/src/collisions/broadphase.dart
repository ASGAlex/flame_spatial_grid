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
  final optimizedCollisionsByGroupBox =
      <Cell, Map<GroupHitbox, OptimizedCollisionList>>{};

  ExternalBroadphaseCheck broadphaseCheck;
  late ExternalMinDistanceCheckSpatialGrid minimumDistanceCheck;

  @internal
  final broadphaseCheckCache = HashMap<T, HashMap<T, bool>>();

  final _potentials = HashSet<CollisionProspect<T>>();

  @internal
  final scheduledOperations = <ScheduledHitboxOperation>[];

  @override
  void update() {
    for (final operation in scheduledOperations) {
      if (operation.add) {
        if (operation.active) {
          activeCollisions.add(operation.hitbox as T);
        } else {
          final cell = operation.cell;
          if (cell != null && cell.state != CellState.suspended) {
            var list = passiveCollisionsByCell[cell];
            list ??= passiveCollisionsByCell[cell] = HashSet<ShapeHitbox>();
            list.add(operation.hitbox);
          }
        }
      } else {
        if (operation.active) {
          activeCollisions.remove(operation.hitbox as T);
        } else {
          final cell = operation.cell;
          if (cell != null) {
            passiveCollisionsByCell[cell]?.remove(operation.hitbox);
          }
        }
      }
    }
    scheduledOperations.clear();
  }

  HashSet<CollisionProspect<T>> querySubset(
      HashSet<CollisionProspect<ShapeHitbox>> potentials) {
    _potentials.clear();
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

      _compareItemWithPotentials(componentHitbox, hitboxes);
    }

    return _potentials;
  }

  @override
  HashSet<CollisionProspect<T>> query() {
    _potentials.clear();

    for (final activeItem in activeCollisions) {
      final asShapeItem = activeItem as ShapeHitbox;

      if (asShapeItem.isRemoving || asShapeItem.parent == null) {
        continue;
      }

      var cellsToCheck = <Cell>[];
      final withGridSupport = asShapeItem.parentWithGridSupport;
      if (withGridSupport == null) continue;

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

      final potentiallyCollide = HashSet<ShapeHitbox>();
      if (cellsToCheck.isEmpty) continue;
      for (final cell in cellsToCheck) {
        final items = passiveCollisionsByCell[cell];
        if (items != null && items.isNotEmpty) {
          potentiallyCollide.addAll(items);
        }
      }
      _compareItemWithPotentials(
          asShapeItem, potentiallyCollide.toList(growable: false));
    }

    return _potentials;
  }

  void _compareItemWithPotentials(
      ShapeHitbox asShapeItem, List<ShapeHitbox> potentials) {
    for (final potential in potentials) {
      final canToCollide = broadphaseCheckCache[asShapeItem]?[potential] ??
          _runExternalBroadphaseCheck(asShapeItem, potential);
      if (!canToCollide) {
        continue;
      }

      if (potential.parent == asShapeItem.parent &&
          asShapeItem.parent != null) {
        continue;
      }
      final distanceCloseEnough = minimumDistanceCheck.call(
        asShapeItem,
        potential,
      );
      if (distanceCloseEnough == false) {
        continue;
      }

      _potentials.add(CollisionProspect(asShapeItem as T, potential as T));
    }
  }

  bool _minimumDistanceCheck(
    ShapeHitbox activeItem,
    ShapeHitbox potential,
  ) {
    final activeItemCenter = activeItem.aabbCenter;
    final potentialCenter = potential.aabbCenter;
    final minDistanceX = max(activeItem.size.x, potential.size.x);
    final minDistanceY = max(activeItem.size.y, potential.size.y);
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
}

@internal
@immutable
class ScheduledHitboxOperation {
  const ScheduledHitboxOperation(
      {required this.add,
      required this.active,
      required this.hitbox,
      this.cell});

  const ScheduledHitboxOperation.addActive({required this.hitbox, this.cell})
      : add = true,
        active = true;

  const ScheduledHitboxOperation.addPassive(
      {required this.hitbox, required this.cell})
      : add = true,
        active = false;

  const ScheduledHitboxOperation.removeActive({required this.hitbox, this.cell})
      : add = false,
        active = true;

  const ScheduledHitboxOperation.removePassive(
      {required this.hitbox, required this.cell})
      : add = false,
        active = false;

  final bool add;
  final bool active;
  final ShapeHitbox hitbox;
  final Cell? cell;
}
