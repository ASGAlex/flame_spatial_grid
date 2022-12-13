import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';

class CollisionOptimizer {
  CollisionOptimizer(this.parentLayer);

  final ClusterizedComponent parentLayer;
  final _createdCollisionLists = <OptimizedCollisionList>[];

  List<ClusterizedComponent> get clusterizedChildren => parentLayer.children
      .whereType<ClusterizedComponent>()
      .toList(growable: false);

  List<ClusterizedComponent> get clusterizedChildrenActiveOrPassive =>
      parentLayer.children
          .whereType<ClusterizedComponent>()
          .where((element) =>
              element.boundingBox.collisionType != CollisionType.inactive)
          .toList(growable: false);

  final _alreadyProcessed = HashSet<ShapeHitbox>();

  HasClusterizedCollisionDetection get game =>
      (parentLayer as HasGameReference<HasClusterizedCollisionDetection>).game;

  void optimize() {
    final cell = parentLayer.currentCell;
    if (cell == null) return;

    final optimizedCollisionsByGroupBox =
        game.collisionDetection.broadphase.optimizedCollisionsByGroupBox;
    var collisionsListByGroup = optimizedCollisionsByGroupBox[cell];

    if (collisionsListByGroup == null) {
      optimizedCollisionsByGroupBox[cell] = collisionsListByGroup = {};
    }
    for (final optimized in _createdCollisionLists) {
      optimized.boundingBox.removeFromParent();
      collisionsListByGroup.remove(optimized.boundingBox);
    }
    _createdCollisionLists.clear();
    _alreadyProcessed.clear();

    for (final child in clusterizedChildren) {
      if (cell.state != CellState.inactive) {
        child.boundingBox.collisionType =
            child.boundingBox.defaultCollisionType;
      }
    }

    for (final child in clusterizedChildrenActiveOrPassive) {
      if (_alreadyProcessed.contains(child.boundingBox)) continue;
      final hitboxes = _findOverlappingRects(child.boundingBox);
      if (hitboxes.isNotEmpty) {
        hitboxes.add(child.boundingBox);

        final optimized = OptimizedCollisionList(hitboxes, parentLayer);
        collisionsListByGroup[optimized.boundingBox] = optimized;
        _createdCollisionLists.add(optimized);
        for (final hb in hitboxes) {
          hb.collisionType = CollisionType.inactive;
        }
      }
    }
  }

  HashSet<ShapeHitbox> _findOverlappingRects(ShapeHitbox hitbox,
      [HashSet<ShapeHitbox>? exception]) {
    exception ??= HashSet<ShapeHitbox>();
    final hitboxes = HashSet<ShapeHitbox>();
    exception.add(hitbox);
    for (final otherChild in clusterizedChildrenActiveOrPassive) {
      if (exception.contains(otherChild.boundingBox)) continue;
      if (hitbox.toRect().overlapsSpecial(otherChild.boundingBox.toRect())) {
        hitboxes.add(otherChild.boundingBox);
        _alreadyProcessed.add(otherChild.boundingBox);
        hitboxes
            .addAll(_findOverlappingRects(otherChild.boundingBox, exception));
      }
    }
    return hitboxes;
  }
}

extension RectSpecialOverlap on Rect {
  /// Whether `other` has a nonzero area of overlap with this rectangle.
  bool overlapsSpecial(Rect other) {
    if (right < other.left || other.right < left) {
      return false;
    }
    if (bottom < other.top || other.bottom < top) {
      return false;
    }
    return true;
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
