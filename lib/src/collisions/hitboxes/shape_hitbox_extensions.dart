part of 'bounding_hitbox.dart';

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

  bool get doExtendedTypeCheck => true;

  @internal
  set broadphaseActiveIndex(int value) {
    if (this is BoundingHitbox) {
      (this as BoundingHitbox).broadphaseActiveIndex = value;
    } else {
      if (value == -1) {
        HasGridSupport.shapeHitboxIndex.remove(this);
      } else {
        HasGridSupport.shapeHitboxIndex[this] = value;
      }
    }
  }

  @internal
  int get broadphaseActiveIndex {
    if (this is BoundingHitbox) {
      return (this as BoundingHitbox).broadphaseActiveIndex;
    } else {
      return HasGridSupport.shapeHitboxIndex[this] ?? -1;
    }
  }

  void storeBroadphaseCheckCache(ShapeHitbox item, bool canCollide) {
    var cache = SpatialGridBroadphase.broadphaseCheckCache[this];
    cache ??= SpatialGridBroadphase.broadphaseCheckCache[this] =
        HashMap<ShapeHitbox, bool>();
    cache[item] = canCollide;
  }

  bool? getBroadphaseCheckCache(ShapeHitbox item) =>
      SpatialGridBroadphase.broadphaseCheckCache[this]?[item];

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

  bool get canBeActive {
    if (this is BoundingHitbox) {
      return (this as BoundingHitbox).canBeActive;
    }
    return collisionType == CollisionType.active;
  }
}
