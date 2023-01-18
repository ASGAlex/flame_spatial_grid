import 'dart:collection';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class CollisionOptimizer {
  CollisionOptimizer(this.parentLayer);

  final CellLayer parentLayer;
  final _createdCollisionLists = <OptimizedCollisionList>[];

  static const maximumItemsInGroup = 25;

  List<HasGridSupport> get gridChildren =>
      parentLayer.children.whereType<HasGridSupport>().toList(growable: false);

  List<HasGridSupport> get gridChildrenActiveOrPassive => parentLayer.children
      .whereType<HasGridSupport>()
      .where(
        (element) =>
            element.boundingBox.collisionType != CollisionType.inactive,
      )
      .toList(growable: false);

  final _alreadyProcessed = HashSet<ShapeHitbox>();

  HasSpatialGridFramework get game =>
      (parentLayer as HasGameReference<HasSpatialGridFramework>).game;

  void optimize() {
    final cell = parentLayer.currentCell;
    if (cell == null) {
      return;
    }

    final optimizedCollisionsByGroupBox =
        game.collisionDetection.broadphase.optimizedCollisionsByGroupBox;
    var collisionsListByGroup = optimizedCollisionsByGroupBox[cell];

    if (collisionsListByGroup == null) {
      optimizedCollisionsByGroupBox[cell] = collisionsListByGroup = {};
    }
    for (final optimized in _createdCollisionLists) {
      optimized.boundingBox.removeFromParent();
      collisionsListByGroup.remove(optimized.boundingBox);
      parentLayer.remove(optimized.boundingBox);
    }
    _createdCollisionLists.clear();
    _alreadyProcessed.clear();

    for (final child in gridChildren) {
      if (cell.state != CellState.inactive) {
        child.boundingBox.collisionType =
            child.boundingBox.defaultCollisionType;
      }
    }

    for (final child in gridChildrenActiveOrPassive) {
      if (_alreadyProcessed.contains(child.boundingBox)) {
        continue;
      }
      final hitboxes = _findOverlappingRects(child.boundingBox);
      if (hitboxes.length > 1) {
        if (hitboxes.length > maximumItemsInGroup) {
          var totalInChunk = 0;
          var chunk = <ShapeHitbox>{};
          for (final hbInChunk in hitboxes) {
            if (totalInChunk == maximumItemsInGroup) {
              final optimized = OptimizedCollisionList(
                HashSet<ShapeHitbox>()..addAll(chunk),
                parentLayer,
              );
              collisionsListByGroup[optimized.boundingBox] = optimized;
              _createdCollisionLists.add(optimized);
              totalInChunk = 0;
              chunk = <ShapeHitbox>{};
            } else {
              chunk.add(hbInChunk);
              totalInChunk++;
            }
          }
          if (chunk.isNotEmpty) {
            final optimized = OptimizedCollisionList(
              HashSet<ShapeHitbox>()..addAll(chunk),
              parentLayer,
            );
            collisionsListByGroup[optimized.boundingBox] = optimized;
            _createdCollisionLists.add(optimized);
          }
        } else {
          final optimized = OptimizedCollisionList(hitboxes, parentLayer);
          collisionsListByGroup[optimized.boundingBox] = optimized;
          _createdCollisionLists.add(optimized);
        }
        for (final hb in hitboxes) {
          hb.collisionType = CollisionType.inactive;
        }
      }
    }
  }

  LinkedHashSet<ShapeHitbox> _findOverlappingRects(
    ShapeHitbox hitbox, [
    HashSet<ShapeHitbox>? exception,
  ]) {
    exception ??= HashSet<ShapeHitbox>();
    // ignore: prefer_collection_literals
    final hitboxes = LinkedHashSet<ShapeHitbox>();
    hitboxes.add(hitbox);
    exception.add(hitbox);
    for (final otherChild in gridChildrenActiveOrPassive) {
      if (exception.contains(otherChild.boundingBox)) {
        continue;
      }
      if (hitbox
          .toRectSpecial()
          .overlapsSpecial(otherChild.boundingBox.toRectSpecial())) {
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
  OptimizedCollisionList(Set<ShapeHitbox> hitboxes, this.parentLayer) {
    _hitboxes = hitboxes;
    _updateBoundingBox();
  }

  List<ShapeHitbox> get hitboxes => _hitboxes.toList(growable: false);
  var _hitboxes = <ShapeHitbox>{};
  var _boundingBox = GroupHitbox(tag: '');
  final CellLayer parentLayer;

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

  void _updateBoundingBox() {
    var rect = Rect.zero;
    for (final hitbox in _hitboxes) {
      if (rect == Rect.zero) {
        rect = hitbox.toRectSpecial();
        continue;
      }
      rect = rect.expandToInclude(hitbox.toRectSpecial());
    }
    _boundingBox = GroupHitbox(
      tag: parentLayer.name,
      parentWithGridSupport: parentLayer,
      position: rect.topLeft.toVector2(),
      size: rect.size.toVector2(),
    )..collisionType = CollisionType.passive;
    parentLayer.add(_boundingBox);
  }
}

extension ToRectSpecial on PositionComponent {
  Rect toRectSpecial() {
    final parentPosition = (parent as PositionComponent?)?.position;
    if (parentPosition == null) {
      return Rect.zero;
    }
    return Rect.fromLTWH(
      parentPosition.x + position.x,
      parentPosition.y + position.y,
      size.x,
      size.y,
    );
  }
}
