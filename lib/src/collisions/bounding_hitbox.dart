import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

/// A special hitbox type which saves additional information:
/// - [parentWithGridSupport] - parent component which should be with
///   [HasGridSupport] mixin
/// - [defaultCollisionType] - every hitbox changes it's [collisionType] during
///   [Cell]'s lifetime. It can conditionally become [CollisionType.inactive],
///   for example. [defaultCollisionType] is used to restore right state after
///   inactivation.
/// - [aabbCenter] - [aabb] calculates center at each call. This method provides
///   caching.
/// Using this hitbox for game with spatial grid framework is cheaper then
/// working with pure [RectangleHitbox] because for rest of hitboxes all
/// necessary information is stored into [HashMap], so adding, getting and
/// updating this info is more expensive (in theory).
///
/// [SpatialGridRectangleHitbox] and [SpatialGridShapeHitbox] extensions
/// provides same functionality for pure Flame hitboxes
class BoundingHitbox extends RectangleHitbox {
  BoundingHitbox({
    super.position,
    super.size,
    HasGridSupport? parentWithGridSupport,
  }) {
    _parentWithGridSupport = parentWithGridSupport;
    minDistanceX = size.x/2;
    minDistanceY = size.y/2;
    size.addListener(() {
      minDistanceX = size.x/2;
      minDistanceY = size.y/2;
    });
  }

  Vector2? _aabbCenter;

  /// [aabb] calculates center at each call. This method provides
  /// caching.
  Vector2 get aabbCenter => _aabbCenter ??= aabb.center;

  double minDistanceX = 0.0;
  double minDistanceY = 0.0;

  final groupCollisionsTags = <String>[];

  set aabbCenter(Vector2? value) {
    assert(value != null);
    _aabbCenter = value;
  }

  HasGridSupport? _parentWithGridSupport;

  /// Parent component which should be with [HasGridSupport] mixin
  HasGridSupport? get parentWithGridSupport {
    var component = _parentWithGridSupport;
    if (component == null) {
      try {
        component = ancestors().firstWhere(
          (c) => c is HasGridSupport,
        ) as HasGridSupport;
        _parentWithGridSupport = component;
        // ignore: avoid_catches_without_on_clauses
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

  /// Every hitbox changes it's [collisionType] during
  /// [Cell]'s lifetime. It can conditionally become [CollisionType.inactive],
  /// for example. [defaultCollisionType] is used to restore right state after
  /// inactivation.
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
        // ignore: avoid_catches_without_on_clauses
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
