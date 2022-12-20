import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

import 'collision_optimizer.dart';

mixin HasSpatialGridFramework on FlameGame
    implements HasCollisionDetection<SpatialGridBroadphase<ShapeHitbox>> {
  late SpatialGridCollisionDetection _collisionDetection;
  late final SpatialGrid spatialGrid;
  late Component rootComponent;
  SpatialGridDebugComponent? _spatialGridDebug;
  bool _isSpatialGridDebugEnabled = false;

  @override
  SpatialGridCollisionDetection get collisionDetection => _collisionDetection;

  @override
  set collisionDetection(
    CollisionDetection<ShapeHitbox, SpatialGridBroadphase<ShapeHitbox>> cd,
  ) {
    if (cd is! SpatialGridCollisionDetection) {
      throw 'Must be SpatialGridCollisionDetection!';
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
  Future<void> initializeSpatialGrid(
      {bool? debug,
      Component? rootComponent,
      required double blockSize,
      required int activeRadius,
      required int unloadRadius,
      required HasGridSupport trackedComponent,
      required HasSpatialGridFramework game,
      int buildCellsPerUpdate = -1,
      CellBuilderFunction? cellBuilder,
      List<TiledMapLoader>? maps}) async {
    this.rootComponent = rootComponent ?? this;
    _cellBuilder = cellBuilder;
    this.buildCellsPerUpdate = buildCellsPerUpdate;
    if (maps != null) {
      this.maps = maps;
    }
    spatialGrid = SpatialGrid(
        blockSize: Size.square(blockSize),
        trackedComponent: trackedComponent,
        activeRadius: activeRadius,
        unloadRadius: unloadRadius,
        game: game);

    _collisionDetection = SpatialGridCollisionDetection(
      spatialGrid: spatialGrid,
      onComponentTypeCheck: onComponentTypeCheck,
      minimumDistanceCheck: minimumDistanceCheck,
    );

    isSpatialGridDebugEnabled = debug ?? false;

    for (final map in this.maps) {
      await map.init(this);
      TiledMapLoader.loadedMaps.add(map);
    }
  }

  List<TiledMapLoader> maps = [];
  CellBuilderFunction? _cellBuilder;
  int buildCellsPerUpdate = -1;

  Future<void> _cellBuilderMulti(Cell cell, Component rootComponent) async {
    if (maps.isEmpty) {
      return _cellBuilder?.call(cell, rootComponent);
    }

    for (final map in maps) {
      await map.cellBuilder(cell, rootComponent);
    }
  }

  set isSpatialGridDebugEnabled(bool debug) {
    if (_isSpatialGridDebugEnabled == debug) return;

    _isSpatialGridDebugEnabled = debug;
    if (_isSpatialGridDebugEnabled) {
      _spatialGridDebug ??= SpatialGridDebugComponent(spatialGrid);
      rootComponent.add(_spatialGridDebug!);
    } else {
      _spatialGridDebug?.removeFromParent();
    }
  }

  bool get isSpatialGridDebugEnabled => _isSpatialGridDebugEnabled;

  @override
  void onRemove() {
    isSpatialGridDebugEnabled = false;
    _spatialGridDebug = null;
    spatialGrid.dispose();
    super.onRemove();
  }

  bool minimumDistanceCheck(
      HasGridSupport activeItem, HasGridSupport potential) {
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
    if (spatialGrid.cellsScheduledToBuild.isNotEmpty) {
      final cellsToProcess = (buildCellsPerUpdate > 0
          ? buildCellsPerUpdate
          : spatialGrid.cellsScheduledToBuild.length);
      for (var i = 0; i < cellsToProcess; i++) {
        final cell = spatialGrid.cellsScheduledToBuild.first;
        spatialGrid.cellsScheduledToBuild.remove(cell);
        await _cellBuilderMulti(cell, rootComponent);
      }
    }
    super.update(dt);
    collisionDetection.run();
  }
}
