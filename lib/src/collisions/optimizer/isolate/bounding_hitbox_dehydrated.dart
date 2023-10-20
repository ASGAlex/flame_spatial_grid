import 'dart:typed_data';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class BoundingHitboxDehydrated {
  BoundingHitboxDehydrated(BoundingHitbox hitbox, this.index) {
    aabb = hitbox.aabb;
    positionStorage = hitbox.position.storage;

    parentPositionStorage =
        (hitbox.parent as PositionComponent?)?.position.storage;
    sizeStorage = hitbox.size.storage;
    skip = hitbox.collisionType == CollisionType.inactive;
  }

  late final Float64List sizeStorage;
  late final Float64List positionStorage;
  late final Float64List? parentPositionStorage;
  late final Aabb2 aabb;
  final int index;
  late final bool skip;

  Rect? _rectCache;
  late Float64List _hydratedRect;

  static final empty = BoundingHitboxDehydrated(emptyBoundingHitbox, 0);

  static final emptyBoundingHitbox = BoundingHitbox();

  Float64List get hydratedRect {
    toRectSpecial();
    return _hydratedRect;
  }

  final Vector2 _aabbCenter = Vector2.zero();
  bool _aabbCenterNotSet = true;

  Vector2 get aabbCenter {
    if (_aabbCenterNotSet) {
      _aabbCenterNotSet = false;
      _aabbCenter.setFrom(aabb.center);
    }
    return _aabbCenter;
  }

  Rect toRectSpecial() {
    final cache = _rectCache;
    if (cache != null) {
      return cache;
    } else {
      if (parentPositionStorage == null) {
        return Rect.zero;
      } else {
        final parentPosition = Vector2.fromFloat64List(parentPositionStorage!);
        final position = Vector2.fromFloat64List(positionStorage);
        final size = Vector2.fromFloat64List(sizeStorage);
        final cache = Rect.fromLTWH(
          parentPosition.x + position.x,
          parentPosition.y + position.y,
          size.x,
          size.y,
        );

        _hydratedRect = Float64List.fromList([
          cache.left,
          cache.top,
          cache.right,
          cache.bottom,
        ]);

        _rectCache = cache;
        return cache;
      }
    }
  }
}
