import 'dart:ui';

import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/bounding_hitbox_dehydrated.dart';

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
