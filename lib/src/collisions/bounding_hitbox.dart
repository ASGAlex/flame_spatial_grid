import 'package:flame/collisions.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

class BoundingHitbox extends RectangleHitbox {
  BoundingHitbox(
      {super.position, super.size, HasGridSupport? parentWithGridSupport}) {
    _parentWithGridSupport = parentWithGridSupport;
    minDistanceX = size.x;
    minDistanceY = size.y;
    size.addListener(() {
      minDistanceX = size.x;
      minDistanceY = size.y;
    });
  }

  Vector2? _aabbCenter;

  Vector2 get aabbCenter => _aabbCenter ??= aabb.center;

  var minDistanceX = 0.0;
  var minDistanceY = 0.0;

  set aabbCenter(Vector2? value) {
    assert(value != null);
    _aabbCenter = value!;
  }

  HasGridSupport? _parentWithGridSupport;

  HasGridSupport? get parentWithGridSupport {
    var component = _parentWithGridSupport;
    if (component == null) {
      try {
        component = ancestors().firstWhere(
              (c) => c is HasGridSupport,
        ) as HasGridSupport;
        _parentWithGridSupport = component;
      } catch (e) {
        return null;
      }
    }
    return component;
  }

  CollisionType? _defaultCollisionType;

  set defaultCollisionType(CollisionType? value) {
    assert(value != null);
    _defaultCollisionType = value;
  }

  CollisionType get defaultCollisionType {
    _defaultCollisionType ??= collisionType;
    return _defaultCollisionType!;
  }

  bool isFullyInsideRect(Rect rect) {
    final boundingRect = aabb.toRect();
    return rect.topLeft < boundingRect.topLeft &&
        rect.bottomRight > boundingRect.bottomRight;
  }
}

extension SpatialGridRectangleHitbox on RectangleHitbox {
  Vector2 get aabbCenter {
    final hitbox = this;
    if (hitbox is BoundingHitbox) {
      return hitbox.aabbCenter;
    }

    var cache = HasGridSupport.cachedCenters[this];
    if (cache == null) {
      HasGridSupport.cachedCenters[this] = aabb.center;
      cache = HasGridSupport.cachedCenters[this];
    }
    return cache!;
  }

  bool isFullyInsideRect(Rect rect) {
    final boundingRect = aabb.toRect();
    return rect.topLeft < boundingRect.topLeft &&
        rect.bottomRight > boundingRect.bottomRight;
  }
}

extension SpatialGridShapeHitbox on ShapeHitbox {
  Vector2 get aabbCenter {
    final hitbox = this;
    if (hitbox is BoundingHitbox) {
      return hitbox.aabbCenter;
    }
    var cache = HasGridSupport.cachedCenters[this];
    if (cache == null) {
      HasGridSupport.cachedCenters[this] = aabb.center;
      cache = HasGridSupport.cachedCenters[this];
    }
    return cache!;
  }

  HasGridSupport? get parentWithGridSupport {
    final hitbox = this;
    if (hitbox is BoundingHitbox) {
      return hitbox.parentWithGridSupport;
    }

    var component = HasGridSupport.componentHitboxes[this];
    if (component == null) {
      try {
        component = ancestors().firstWhere(
              (c) => c is HasGridSupport,
        ) as HasGridSupport;
        HasGridSupport.componentHitboxes[this] = component;
        return component;
      } catch (e) {
        return null;
      }
    }
    return component;
  }

  @internal
  void clearGridComponentCaches() {
    HasGridSupport.componentHitboxes.remove(this);
    HasGridSupport.defaultCollisionType.remove(this);
    HasGridSupport.cachedCenters.remove(this);
  }

  set defaultCollisionType(CollisionType defaultCollisionType) {
    final hitbox = this;
    if (hitbox is BoundingHitbox) {
      hitbox.defaultCollisionType = defaultCollisionType;
    } else {
      HasGridSupport.defaultCollisionType[this] = defaultCollisionType;
    }
  }

  CollisionType get defaultCollisionType {
    final hitbox = this;
    if (hitbox is BoundingHitbox) {
      return hitbox.defaultCollisionType;
    }

    var cache = HasGridSupport.defaultCollisionType[this];
    if (cache == null) {
      HasGridSupport.defaultCollisionType[this] = collisionType;
      cache = HasGridSupport.defaultCollisionType[this];
    }
    return cache!;
  }
}
