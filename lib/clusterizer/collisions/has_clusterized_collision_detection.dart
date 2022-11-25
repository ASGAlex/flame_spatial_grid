import 'package:cluisterizer_test/clusterizer/cell_builder.dart';
import 'package:cluisterizer_test/clusterizer/clusterized_component.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';

import '../clusterizer.dart';
import '../debug_component.dart';
import 'clusterized_broadphase.dart';
import 'clusterized_collision_detection.dart';

mixin HasClusterizedCollisionDetection on FlameGame
    implements HasCollisionDetection<ClusterizedBroadphase<ShapeHitbox>> {
  late ClusterizedCollisionDetection _collisionDetection;
  late final Clusterizer _clusterizer;
  late Component parentComponent;
  ClusterizerDebugComponent? _clusterizerDebug;
  bool _isClusterizerDebugEnabled = false;

  @override
  ClusterizedCollisionDetection get collisionDetection => _collisionDetection;

  @override
  set collisionDetection(
    CollisionDetection<ShapeHitbox, ClusterizedBroadphase<ShapeHitbox>> cd,
  ) {
    if (cd is! ClusterizedCollisionDetection) {
      throw 'Must be QuadTreeCollisionDetection!';
    }
    _collisionDetection = cd;
  }

  /// Initialise .
  ///
  /// - [minimumDistance] (optional) - specify minimum distance between objects
  ///   to consider them as possibly colliding. You can also implement the
  ///   [minimumDistanceCheck] if you need some custom behavior.
  ///
  /// The [onComponentTypeCheck] checks if objects of different types should
  /// collide.
  /// The result of the calculation is cached so you should not check any
  /// dynamical parameters here, the function is intended to be used as pure
  /// type checker.
  /// It should usually not be overridden, see
  /// [CollisionCallbacks.onComponentTypeCheck] instead
  void initializeCollisionDetection(
      {double? minimumDistance,
      bool? debug,
      Component? parentComponent,
      required double blockSize,
      required int activeRadius,
      required ClusterizedComponent trackedComponent,
      required CellBuilder cellBuilder}) {
    this.parentComponent = parentComponent ?? this;
    _clusterizer = Clusterizer(
        blockSize: Size.square(blockSize),
        trackedComponent: trackedComponent,
        cellBuilder: cellBuilder,
        activeRadius: activeRadius);
    _collisionDetection = ClusterizedCollisionDetection(
      onComponentTypeCheck: onComponentTypeCheck,
      minimumDistanceCheck: minimumDistanceCheck,
    );
    this.minimumDistance = minimumDistance;
    isClusterizerDebugEnabled = debug ?? false;
  }

  set isClusterizerDebugEnabled(bool debug) {
    if (_isClusterizerDebugEnabled == debug) return;

    _isClusterizerDebugEnabled = debug;
    if (_isClusterizerDebugEnabled) {
      _clusterizerDebug ??= ClusterizerDebugComponent(_clusterizer);
      parentComponent.add(_clusterizerDebug!);
    } else {
      _clusterizerDebug?.removeFromParent();
    }
  }

  @override
  void onRemove() {
    isClusterizerDebugEnabled = false;
    _clusterizerDebug = null;
    _clusterizer.dispose();
    super.onRemove();
  }

  double? minimumDistance;

  bool minimumDistanceCheck(Vector2 activeItemCenter, Vector2 potentialCenter) {
    return minimumDistance == null ||
        !((activeItemCenter.x - potentialCenter.x).abs() > minimumDistance! ||
            (activeItemCenter.y - potentialCenter.y).abs() > minimumDistance!);
  }

  bool onComponentTypeCheck(PositionComponent one, PositionComponent another) {
    var checkParent = false;
    if (one is CollisionCallbacks) {
      if (!(one as CollisionCallbacks).onComponentTypeCheck(another)) {
        return false;
      }
    } else {
      checkParent = true;
    }

    if (another is CollisionCallbacks) {
      if (!(another as CollisionCallbacks).onComponentTypeCheck(one)) {
        return false;
      }
    } else {
      checkParent = true;
    }

    if (checkParent && one is ShapeHitbox && another is ShapeHitbox) {
      return onComponentTypeCheck(one.hitboxParent, another.hitboxParent);
    }
    return true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    collisionDetection.run();
  }
}
