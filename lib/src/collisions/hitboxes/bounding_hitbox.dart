import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/hitboxes/rectangle_hitbox_optimized.dart';
import 'package:flame_spatial_grid/src/components/macro_object.dart';
import 'package:flame_spatial_grid/src/components/utility/pure_type_check_interface.dart';
import 'package:meta/meta.dart';

part 'rectangle_hitbox_extensions.dart';
part 'shape_hitbox_extensions.dart';

typedef BoundingHitboxFactory = BoundingHitbox Function();

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
class BoundingHitbox extends RectangleHitboxOptimized
    with HasGameReference<HasSpatialGridFramework>
    implements MacroObjectInterface, PureTypeCheckInterface {
  BoundingHitbox({
    super.position,
    super.size,
    super.collisionType = CollisionType.inactive,
    HasGridSupport? parentWithGridSupport,
  }) {
    _parentWithGridSupport = parentWithGridSupport;
  }

  bool fastCollisionForRects = false;
  bool _aabbCenterNotSet = true;
  final Vector2 _aabbCenter = Vector2.zero();
  var _aabbCenterStorage = Float64x2.zero();

  bool doExtendedTypeCheck = true;
  final _broadphaseCheckCacheTrue = HashSet<int>();
  final _broadphaseCheckCacheFalse = HashSet<int>();

  bool _positionCached = false;
  final _absolutePositionOfCache = Vector2.zero();

  bool? _canBeActive;

  set canBeActive(bool value) {
    _canBeActive = value;
  }

  bool get canBeActive {
    if (_canBeActive != null) {
      return _canBeActive!;
    }

    return collisionType == CollisionType.active;
  }

  @internal
  final broadphaseMinimumDistanceSkip = HashMap<ShapeHitbox, int>();

  @internal
  int broadphaseActiveIndex = -1;

  /// [aabb] calculates center at each call. This method provides
  /// caching.
  Vector2 get aabbCenter {
    if (_aabbCenterNotSet) {
      _aabbCenterNotSet = false;
      aabbCenter = aabb.center;
    }
    return _aabbCenter;
  }

  Float64x2 get aabbCenterStorage {
    if (_aabbCenterNotSet) {
      _aabbCenterNotSet = false;
      aabbCenter = aabb.center;
    }
    return _aabbCenterStorage;
  }

  double collisionCheckFrequency = -1;

  @internal
  double collisionCheckCounter = 0;

  set minCollisionDistance(Vector2 distance) {
    _minCollisionDistance = Float64x2(distance.x, distance.y);
  }

  var _minCollisionDistance = Float64x2.zero();

  Float64x2 get minCollisionDistanceStorage => _minCollisionDistance;

  @internal
  bool isFastDistanceCheckAvailable = false;

  bool isDistanceCallbackEnabled = false;

  bool get optimized => _optimized;

  var _optimized = false;

  @override
  Vector2 get macroSize {
    final group = this.group;
    if (group == null) {
      return size;
    }
    return group.size;
  }

  @override
  Vector2 get macroPosition {
    final group = this.group;
    if (group == null) {
      return position;
    }

    return group.position;
  }

  GroupHitbox? _group;

  GroupHitbox? get group {
    if (optimized && _group != null) {
      return _group;
    }
    return null;
  }

  @internal
  set group(GroupHitbox? value) {
    _group = value;
    _optimized = (value != null);
  }

  final groupCollisionsTags = <String>[];

  double Function()? parentSpeedGetter;

  void onParentSpeedChange() {
    broadphaseMinimumDistanceSkip.clear();
  }

  @override
  Vector2 absolutePositionOf(Vector2 point) {
    if (_positionCached) {
      return _absolutePositionOfCache;
    } else {
      var parentPoint = positionOf(point);
      var ancestor = parent;
      while (ancestor != null) {
        if (ancestor is PositionComponent) {
          parentPoint = ancestor.positionOf(parentPoint);
        }
        ancestor = ancestor.parent;
      }
      _absolutePositionOfCache.setFrom(parentPoint);
      return _absolutePositionOfCache;
    }
  }

  set aabbCenter(Vector2? value) {
    assert(value != null);
    _aabbCenter.setFrom(value!);
    _aabbCenterStorage = Float64x2(value.x, value.y);
  }

  void _precalculateCollisionVariables() {
    minCollisionDistance = size / 2;
    final broadphase = game.collisionDetection.broadphase;
    if (size.x >= broadphase.fastDistanceCheckMinX ||
        size.y >= broadphase.fastDistanceCheckMinY) {
      isFastDistanceCheckAvailable = false;
    } else {
      isFastDistanceCheckAvailable = true;
    }
    _onPositionChanged();
  }

  void storeBroadphaseCheckCache(ShapeHitbox item, bool canCollide) {
    final key = hashCode & item.hashCode;
    if (canCollide) {
      _broadphaseCheckCacheTrue.add(key);
    } else {
      _broadphaseCheckCacheFalse.add(key);
    }
    // _broadphaseCheckCache[item] = canCollide;
    if (item is BoundingHitbox) {
      if (canCollide) {
        item._broadphaseCheckCacheTrue.add(key);
      } else {
        item._broadphaseCheckCacheFalse.add(key);
      }
      // item._broadphaseCheckCache[this] = canCollide;
    } else {
      item.storeBroadphaseCheckCache(this, canCollide);
    }
  }

  bool? getBroadphaseCheckCache(ShapeHitbox item) {
    final key = hashCode & item.hashCode;

    final isTrue = _broadphaseCheckCacheTrue.contains(key);
    if (isTrue) {
      return true;
    } else {
      final isFalse = _broadphaseCheckCacheFalse.contains(key);
      if (isFalse) {
        return isFalse;
      }
    }
    return null;
  }

  void removeBroadphaseCheckItem(ShapeHitbox item) {
    final key = hashCode & item.hashCode;
    _broadphaseCheckCacheTrue.remove(key);
    _broadphaseCheckCacheFalse.remove(key);
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

  @override
  void onMount() {
    _precalculateCollisionVariables();
    size.addListener(_precalculateCollisionVariables);
    position.addListener(_onPositionChanged);
    super.onMount();
  }

  void _onPositionChanged() {
    _positionCached = false;
  }

  static final _removedKeys = <int>[];

  @override
  void onRemove() {
    _removedKeys.addAll(_broadphaseCheckCacheTrue);
    _removedKeys.addAll(_broadphaseCheckCacheFalse);

    if (_removedKeys.length >= 1000) {
      cleanOldKeys();
    }

    _group = null;

    position.removeListener(_onPositionChanged);
    size.removeListener(_precalculateCollisionVariables);
    super.onRemove();
    _parentWithGridSupport = null;
  }

  void cleanOldKeys() {
    final totalKeys = _removedKeys.length;
    for (var i = 0; i < totalKeys; i++) {
      final key = _removedKeys[i];
      _broadphaseCheckCacheTrue.remove(key);
      _broadphaseCheckCacheFalse.remove(key);
      // FIXME: support of vanilla hitboxes is broken!!!
      // for (final item in _broadphaseCheckCache.keys) {
      //   if (item is BoundingHitbox) {
      //     item._broadphaseCheckCache.remove(this);
      //   } else {
      //     SpatialGridBroadphase.broadphaseCheckCache[item]?.remove(this);
      //   }
      // }
      // _broadphaseCheckCache.clear();
    }
  }

  @override
  void onParentResize(Vector2 maxSize) {
    // resizeToIncludeChildren();  //TODO: static layers bbox expands... why?
    absoluteScaledSizeCacheReset();
    super.onParentResize(maxSize);
  }

  @internal
  void resizeToIncludeChildren([ShapeHitbox? component]) {
    if (parent == null) {
      return;
    }
    if (component != null) {
      _expandBoundingBox(component);
    } else {
      size.setFrom((parent! as HasGridSupport).size);
      for (final child in parent!.children.query<ShapeHitbox>()) {
        if (component == this) {
          continue;
        }
        _expandBoundingBox(child);
      }
    }
  }

  void _expandBoundingBox(ShapeHitbox component) {
    final currentRect = shouldFillParent
        ? Rect.fromLTWH(
            0,
            0,
            parentWithGridSupport!.size.x,
            parentWithGridSupport!.size.y,
          )
        : toRect();
    final addRect = component.toRect();
    final newRect = currentRect.expandToInclude(addRect);
    position.setFrom(newRect.topLeft.toVector2());
    size.setFrom(newRect.size.toVector2());
  }

  @override
  bool pureTypeCheck(Type other) => true;

  @override
  void renderDebugMode(Canvas canvas) {
    if (group == null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()
          ..color = const Color.fromRGBO(119, 0, 255, 1.0)
          ..style = PaintingStyle.stroke,
      );
    }
  }

  /// Where this [ShapeComponent] has intersection points with another shape
  @override
  Set<Vector2> intersections(Hitbox other) {
    if (other is BoundingHitbox &&
        fastCollisionForRects &&
        other.fastCollisionForRects) {
      final boundingRect = aabb.toRect();
      final boundingRectOther = other.aabb.toRect();
      final result = boundingRect.intersect(boundingRectOther);
      return <Vector2>{
        result.topLeft.toVector2(),
        result.topRight.toVector2(),
        result.bottomLeft.toVector2(),
        result.bottomRight.toVector2(),
      };
    }
    return super.intersections(other);
  }

  @override
  List<Vector2> globalVertices() => [
        aabb.min,
        Vector2(aabb.max.x, aabb.min.y),
        aabb.max,
        Vector2(aabb.min.x, aabb.max.y),
      ];

  @override
  bool containsPoint(Vector2 point) => aabb.containsVector2(point);

  @override
  @mustCallSuper
  void onCollisionStart(Set<Vector2> intersectionPoints, ShapeHitbox other) {
    group?.onCollisionStart(intersectionPoints, other);
    super.onCollisionStart(intersectionPoints, other);
  }

  @override
  @mustCallSuper
  void onCollisionEnd(ShapeHitbox other) {
    group?.onCollisionEnd(other);
    super.onCollisionEnd(other);
  }
}
