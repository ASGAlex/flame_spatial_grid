import 'package:flame/collisions.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/collision_optimizer.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/extensions.dart';

class OptimizedCollisionList {
  OptimizedCollisionList(
    Iterable<ShapeHitbox> hitboxes,
    this.parentLayer, [
    Rect expandedBoundingRect = Rect.zero,
  ]) {
    _hitboxes.addAll(hitboxes);
    _updateBoundingBox(expandedBoundingRect);
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

  void _updateBoundingBox([
    Rect expandedBoundingRect = Rect.zero,
  ]) {
    _boundingBox.removeFromParent();
    var rect = Rect.zero;
    if (expandedBoundingRect == Rect.zero) {
      for (final hitbox in _hitboxes) {
        if (rect == Rect.zero) {
          rect = hitbox.toRectSpecial();
          continue;
        }
        rect = rect.expandToInclude(hitbox.toRectSpecial());
      }
    } else {
      rect = expandedBoundingRect;
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

class OptimizedCollisionListDehydrated {
  OptimizedCollisionListDehydrated(
      Iterable<BoundingHitboxDehydrated> hitboxes) {
    _hitboxes.addAll(hitboxes);
    _updateBoundingBox();
  }

  List<BoundingHitboxDehydrated> get hitboxes => _hitboxes;
  final _hitboxes = <BoundingHitboxDehydrated>[];

  Rect _expandedBoundingRect = Rect.zero;

  Rect get expandedBoundingRect => _expandedBoundingRect;

  void _updateBoundingBox() {
    _expandedBoundingRect = Rect.zero;
    for (final hitbox in _hitboxes) {
      if (_expandedBoundingRect == Rect.zero) {
        _expandedBoundingRect = hitbox.toRectSpecial();
        continue;
      }
      _expandedBoundingRect =
          _expandedBoundingRect.expandToInclude(hitbox.toRectSpecial());
    }
  }
}
