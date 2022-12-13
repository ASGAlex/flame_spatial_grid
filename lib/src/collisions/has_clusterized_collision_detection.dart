import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';

import 'collision_optimizer.dart';

mixin HasClusterizedCollisionDetection on FlameGame
    implements HasCollisionDetection<ClusterizedBroadphase<ShapeHitbox>> {
  late ClusterizedCollisionDetection _collisionDetection;
  late final Clusterizer clusterizer;
  late Component rootComponent;
  ClusterizerDebugComponent? _clusterizerDebug;
  bool _isClusterizerDebugEnabled = false;

  @override
  ClusterizedCollisionDetection get collisionDetection => _collisionDetection;

  @override
  set collisionDetection(
    CollisionDetection<ShapeHitbox, ClusterizedBroadphase<ShapeHitbox>> cd,
  ) {
    if (cd is! ClusterizedCollisionDetection) {
      throw 'Must be ClusterizedCollisionDetection!';
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
  Future<void> initializeClusterizer(
      {bool? debug,
      Component? rootComponent,
      required double blockSize,
      required int activeRadius,
      required int unloadRadius,
      required ClusterizedComponent trackedComponent,
      CellBuilderFunction? cellBuilder,
      List<TiledMapLoader>? maps}) async {
    this.rootComponent = rootComponent ?? this;
    _cellBuilder = cellBuilder;
    if (maps != null) {
      this.maps = maps;
    }
    clusterizer = Clusterizer(
        blockSize: Size.square(blockSize),
        trackedComponent: trackedComponent,
        activeRadius: activeRadius,
        unloadRadius: unloadRadius);

    _collisionDetection = ClusterizedCollisionDetection(
      clusterizer: clusterizer,
      onComponentTypeCheck: onComponentTypeCheck,
      minimumDistanceCheck: minimumDistanceCheck,
    );

    isClusterizerDebugEnabled = debug ?? false;

    for (final map in this.maps) {
      await map.init(this);
      TiledMapLoader.loadedMaps.add(map);
    }
  }

  List<TiledMapLoader> maps = [];
  CellBuilderFunction? _cellBuilder;

  Future<void> _cellBuilderMulti(Cell cell, Component rootComponent) async {
    if (maps.isEmpty) {
      return _cellBuilder?.call(cell, rootComponent);
    }

    for (final map in maps) {
      await map.cellBuilder(cell, rootComponent);
    }
  }

  set isClusterizerDebugEnabled(bool debug) {
    if (_isClusterizerDebugEnabled == debug) return;

    _isClusterizerDebugEnabled = debug;
    if (_isClusterizerDebugEnabled) {
      _clusterizerDebug ??= ClusterizerDebugComponent(clusterizer);
      rootComponent.add(_clusterizerDebug!);
    } else {
      _clusterizerDebug?.removeFromParent();
    }
  }

  bool get isClusterizerDebugEnabled => _isClusterizerDebugEnabled;

  @override
  void onRemove() {
    isClusterizerDebugEnabled = false;
    _clusterizerDebug = null;
    clusterizer.dispose();
    super.onRemove();
  }

  bool minimumDistanceCheck(
      ClusterizedComponent activeItem, ClusterizedComponent potential) {
    final minimumDistance =
        max(activeItem.minDistanceQuad, potential.minDistanceQuad);
    final activeItemCenter = activeItem.boundingBox.aabbCenter;
    final potentialCenter = activeItem.boundingBox.aabbCenter;
    return !(pow((activeItemCenter.x - potentialCenter.x).abs(), 2) >
            minimumDistance ||
        pow((activeItemCenter.y - potentialCenter.y).abs(), 2) >
            minimumDistance);
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

    if (checkParent &&
        one is ShapeHitbox &&
        another is ShapeHitbox &&
        one is! GroupHitbox &&
        another is! GroupHitbox) {
      return onComponentTypeCheck(one.hitboxParent, another.hitboxParent);
    }
    return true;
  }

  @override
  void update(double dt) async {
    if (clusterizer.cellsScheduledToBuild.isNotEmpty) {
      for (var cell in clusterizer.cellsScheduledToBuild) {
        await _cellBuilderMulti(cell, rootComponent);
      }
      clusterizer.cellsScheduledToBuild.clear();
    }
    super.update(dt);
    collisionDetection.run();
  }
}
