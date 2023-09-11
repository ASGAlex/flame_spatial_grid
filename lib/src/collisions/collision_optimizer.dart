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

  int? _maximumItemsInGroup;

  set maximumItemsInGroup(int? value) {
    _maximumItemsInGroup = value;
  }

  int get maximumItemsInGroup =>
      _maximumItemsInGroup ?? game.collisionOptimizerGroupLimit;

  final _alreadyProcessed = HashSet<ShapeHitbox>();

  HasSpatialGridFramework get game => parentLayer.game;

  List<HasGridSupport> _componentsForOptimisation = [];

  void optimize() {
    final cell = clear();
    if (cell == null) {
      return;
    }

    final optimizedCollisionsByGroupBox =
        game.collisionDetection.broadphase.optimizedCollisionsByGroupBox;
    final collisionsListByGroup = optimizedCollisionsByGroupBox[cell]!;

    _componentsForOptimisation =
        parentLayer.children.query<HasGridSupport>().toList(growable: false);
    for (final child in _componentsForOptimisation) {
      if (cell.state != CellState.inactive) {
        child.boundingBox.collisionType =
            child.boundingBox.defaultCollisionType;
        child.boundingBox.group = null;
      }
    }

    for (final child in _componentsForOptimisation) {
      if (child.boundingBox.collisionType == CollisionType.inactive) {
        continue;
      }
      if (_alreadyProcessed.contains(child.boundingBox)) {
        continue;
      }
      final hitboxesUnsorted = _findOverlappingRects(child.boundingBox);
      if (hitboxesUnsorted.length > 1) {
        if (hitboxesUnsorted.length > maximumItemsInGroup) {
          final hitboxesSorted = hitboxesUnsorted.toList(growable: false);
          hitboxesSorted.sort((a, b) {
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
          var totalInChunk = 0;
          var chunk = <ShapeHitbox>[];
          for (final hbInChunk in hitboxesSorted) {
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
            hitboxesUnsorted,
            parentLayer,
          );
          collisionsListByGroup[optimized.boundingBox] = optimized;
          _createdCollisionLists.add(optimized);
        }
        for (final hb in hitboxesUnsorted) {
          hb.collisionType = CollisionType.inactive;
        }
        if (hitboxesUnsorted.length >= _componentsForOptimisation.length) {
          break;
        }
      }
    }

    _componentsForOptimisation = [];
    _alreadyProcessed.clear();
  }

  LinkedHashSet<BoundingHitbox> _findOverlappingRects(
    BoundingHitbox hitbox, [
    HashSet<BoundingHitbox>? exception,
  ]) {
    exception ??= HashSet<BoundingHitbox>();
    // ignore: prefer_collection_literals
    final hitboxes = LinkedHashSet<BoundingHitbox>();
    hitboxes.add(hitbox);
    exception.add(hitbox);
    for (final otherChild in _componentsForOptimisation) {
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
    _componentsForOptimisation = [];
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
  OptimizedCollisionList(Iterable<ShapeHitbox> hitboxes, this.parentLayer) {
    _hitboxes.addAll(hitboxes);
    _updateBoundingBox();
  }

  List<ShapeHitbox> get hitboxes => _hitboxes;
  final _hitboxes = <ShapeHitbox>[];
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
    _boundingBox.removeFromParent();
    var rect = Rect.zero;
    for (final hitbox in _hitboxes) {
      if (rect == Rect.zero) {
        rect = hitbox.toRectSpecial();
        continue;
      }
      rect = rect.expandToInclude(hitbox.toRectSpecial());
    }
    final collisionType = parentLayer.currentCell!.state == CellState.inactive
        ? CollisionType.inactive
        : CollisionType.passive;
    _boundingBox = GroupHitbox(
      tag: parentLayer.name,
      parentWithGridSupport: parentLayer,
      position: rect.topLeft.toVector2(),
      size: rect.size.toVector2(),
    )..collisionType = collisionType;
    parentLayer.add(_boundingBox);
    for (final h in _hitboxes) {
      if (h is BoundingHitbox) {
        h.group = _boundingBox;
      }
    }
  }

  void clear() {
    _hitboxes.clear();
    if (_boundingBox.parent != null) {
      _boundingBox.removeFromParent();
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
