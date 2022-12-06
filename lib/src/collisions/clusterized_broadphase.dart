import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';

typedef ExternalMinDistanceCheckClusterized = bool Function(
  ClusterizedComponent activeItem,
  ClusterizedComponent potential,
);

/// Performs Quad Tree broadphase check.
///
/// See [HasQuadTreeCollisionDetection.initializeCollisionDetection] for a
/// detailed description of its initialization parameters.
class ClusterizedBroadphase<T extends Hitbox<T>> extends Broadphase<T> {
  ClusterizedBroadphase({
    super.items,
    required this.clusterizer,
    required this.broadphaseCheck,
    required this.minimumDistanceCheck,
  });

  final Clusterizer clusterizer;

  final activeCollisions = HashSet<T>();
  final passiveCollisionsByCell = <Cell, HashSet<ShapeHitbox>>{};
  final optimizedCollisionsByGroupBox =
      <Cell, Map<GroupHitbox, OptimizedCollisionList>>{};

  ExternalBroadphaseCheck broadphaseCheck;
  ExternalMinDistanceCheckClusterized minimumDistanceCheck;
  final _broadphaseCheckCache = <T, Map<T, bool>>{};

  final _potentials = HashSet<CollisionProspect<T>>();
  final _potentialsTmp = <List<ShapeHitbox>>[];

  HashSet<CollisionProspect<T>> querySubset(
      HashSet<CollisionProspect<ShapeHitbox>> potentials) {
    _potentials.clear();
    _potentialsTmp.clear();
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

      final cell = groupBox.clusterizedParent?.currentCell;
      if (cell == null) continue;
      final hitboxes =
          optimizedCollisionsByGroupBox[cell]?[groupBox]?.hitboxes.toList();
      if (hitboxes == null || hitboxes.isEmpty) continue;

      _compareItemWithPotentials(componentHitbox, hitboxes);
    }

    _runExternalBroadphaseCheck();
    return _potentials;
  }

  @override
  HashSet<CollisionProspect<T>> query() {
    _potentials.clear();
    _potentialsTmp.clear();

    for (final activeItem in activeCollisions) {
      final asShapeItem = activeItem as ShapeHitbox;

      if (asShapeItem.isRemoving || asShapeItem.parent == null) {
        continue;
      }

      final cellsToCheck =
          asShapeItem.clusterizedParent?.currentCell?.neighboursAndMe;

      final potentiallyCollide = HashSet<ShapeHitbox>();
      if (cellsToCheck == null) continue;
      for (final cell in cellsToCheck) {
        final items = passiveCollisionsByCell[cell];
        if (items != null && items.isNotEmpty) {
          potentiallyCollide.addAll(items);
        }
      }
      _compareItemWithPotentials(
          asShapeItem, potentiallyCollide.toList(growable: false));
    }

    _runExternalBroadphaseCheck();

    return _potentials;
  }

  void _compareItemWithPotentials(
      ShapeHitbox asShapeItem, List<ShapeHitbox> potentials) {
    for (final potential in potentials) {
      final checkCache = _broadphaseCheckCache[asShapeItem]?[potential];
      if (checkCache == false) {
        continue;
      }

      if (potential.parent == asShapeItem.parent &&
          asShapeItem.parent != null) {
        continue;
      }
      final activeClusterizedComponent = asShapeItem.clusterizedParent;
      final potentialClusterizedComponent = potential.clusterizedParent;
      if (activeClusterizedComponent != null &&
          potentialClusterizedComponent != null) {
        final distanceCloseEnough = minimumDistanceCheck.call(
          activeClusterizedComponent,
          potentialClusterizedComponent,
        );
        if (distanceCloseEnough == false) {
          continue;
        }
      }

      _potentialsTmp.add([asShapeItem, potential]);
    }
  }

  void _runExternalBroadphaseCheck() {
    if (_potentialsTmp.isNotEmpty) {
      for (var i = 0; i < _potentialsTmp.length; i++) {
        final item0 = _potentialsTmp[i].first;
        final item1 = _potentialsTmp[i].last;
        if (broadphaseCheck(item0, item1)) {
          _potentials.add(CollisionProspect(item0 as T, item1 as T));
        } else {
          if (_broadphaseCheckCache[item0 as T] == null) {
            _broadphaseCheckCache[item0 as T] = {};
          }
          _broadphaseCheckCache[item0 as T]![item1 as T] = false;
        }
      }
    }
  }

  void clear() {
    activeCollisions.clear();
    _broadphaseCheckCache.clear();
  }
}

class OptimizedCollisionList {
  OptimizedCollisionList(HashSet<ShapeHitbox> hitboxes, this.parentLayer) {
    _hitboxes = hitboxes;
    _updateBoundingBox();
  }

  List<ShapeHitbox> get hitboxes => _hitboxes.toList(growable: false);
  var _hitboxes = HashSet<ShapeHitbox>();
  var _boundingBox = GroupHitbox()..hasParent = false;
  final PositionComponent parentLayer;

  GroupHitbox get boundingBox => _boundingBox;

  void add(ShapeHitbox hitbox) {
    if (!_hitboxes.contains(hitbox)) {
      _hitboxes.add(hitbox);
      _updateBoundingBox();
    }
  }

  void remove(ShapeHitbox hitbox) {
    final found = _hitboxes.remove(hitbox);
    if (found) {
      _updateBoundingBox();
    }
  }

  _updateBoundingBox() {
    if (_boundingBox.hasParent) {
      parentLayer.remove(_boundingBox);
    }
    var rect = Rect.zero;
    for (final hitbox in _hitboxes) {
      if (rect == Rect.zero) {
        rect = (hitbox.parent as PositionComponent).toRect();
        continue;
      }
      rect =
          rect.expandToInclude((hitbox.parent as PositionComponent).toRect());
    }
    _boundingBox = GroupHitbox(
        // parentLayer: parentLayer,
        position: rect.topLeft.toVector2(),
        size: rect.size.toVector2())
      ..collisionType = CollisionType.passive;
    parentLayer.add(_boundingBox);
  }
}

class GroupHitbox extends RectangleHitbox {
  GroupHitbox({super.position, super.size}) {
    isSolid = true;
  }

  bool hasParent = true;
}
