import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class CollisionOptimizer {
  CollisionOptimizer(this.parentLayer);

  final CellLayer parentLayer;
  final _createdCollisionLists = <OptimizedCollisionList>[];

  bool get isEmpty => _createdCollisionLists.isEmpty;

  int get maximumItemsInGroup => game.collisionOptimizerGroupLimit;

  final _alreadyProcessed = HashSet<ShapeHitbox>();

  HasSpatialGridFramework get game => parentLayer.game;

  void optimize() {
    final cell = clear();
    if (cell == null) {
      return;
    }

    final optimizedCollisionsByGroupBox =
        game.collisionDetection.broadphase.optimizedCollisionsByGroupBox;
    final collisionsListByGroup = optimizedCollisionsByGroupBox[cell]!;

    for (final child in parentLayer.children) {
      if (child is! HasGridSupport) {
        continue;
      }
      if (cell.state != CellState.inactive) {
        child.boundingBox.collisionType =
            child.boundingBox.defaultCollisionType;
      }
    }

    for (final child in parentLayer.children) {
      if (child is! HasGridSupport) {
        continue;
      }
      if (child.boundingBox.collisionType == CollisionType.inactive) {
        continue;
      }
      if (_alreadyProcessed.contains(child.boundingBox)) {
        continue;
      }
      final hitboxes = _findOverlappingRects(child.boundingBox).toList();
      if (hitboxes.length > 1) {
        hitboxes.sort((a, b) {
          if (a.aabbCenter == b.aabbCenter) {
            return 0;
          }
          if (a.aabbCenter.y < b.aabbCenter.y) {
            return -1;
          } else if (a.aabbCenter.y == b.aabbCenter.y) {
            return a.aabbCenter.x < b.aabbCenter.x ? -1 : 1;
          } else {
            return 1;
          }
        });

        if (hitboxes.length > maximumItemsInGroup) {
          var totalInChunk = 0;
          var chunk = <ShapeHitbox>[];
          for (final hbInChunk in hitboxes) {
            if (totalInChunk == maximumItemsInGroup) {
              final optimized = OptimizedCollisionList(
                <ShapeHitbox>{}..addAll(chunk),
                parentLayer,
              );
              collisionsListByGroup[optimized.boundingBox] = optimized;
              _createdCollisionLists.add(optimized);
              totalInChunk = 0;
              chunk = <ShapeHitbox>[];
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
          final optimized = OptimizedCollisionList(
            hitboxes.toSet(),
            parentLayer,
          );
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
    for (final otherChild in parentLayer.children) {
      if (otherChild is! HasGridSupport) {
        continue;
      }
      if (otherChild.boundingBox.collisionType == CollisionType.inactive) {
        continue;
      }
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

  Cell? clear() {
    final cell = parentLayer.currentCell;
    if (cell == null) {
      return null;
    }

    final optimizedCollisionsByGroupBox =
        game.collisionDetection.broadphase.optimizedCollisionsByGroupBox;
    var collisionsListByGroup = optimizedCollisionsByGroupBox[cell];

    if (collisionsListByGroup == null) {
      optimizedCollisionsByGroupBox[cell] = collisionsListByGroup = {};
    }
    for (final optimized in _createdCollisionLists) {
      collisionsListByGroup.remove(optimized.boundingBox);
      optimized.clear();
    }
    _createdCollisionLists.clear();
    _alreadyProcessed.clear();
    return cell;
  }
}

extension RectSpecialOverlap on Rect {
  /// Whether `other` has a nonzero area of overlap with this rectangle.
  bool overlapsSpecial(Rect other) {
    if (topLeft == other.bottomRight ||
        topRight == other.bottomLeft ||
        bottomLeft == other.topRight ||
        bottomRight == other.topLeft) {
      return false;
    }
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
    if (_boundingBox.parent != null) {
      parentLayer.remove(_boundingBox, internalCall: true);
    }
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
    parentLayer.add(_boundingBox, internalCall: true);
  }

  void clear() {
    _hitboxes.clear();
    if (_boundingBox.parent != null) {
      parentLayer.remove(_boundingBox, internalCall: true);
    }
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
