import 'dart:collection';
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
      double buildCellsPerUpdate = -1,
      double removeCellsPerUpdate = -1,
      Duration suspendedCellLifetime = Duration.zero,
      CellBuilderFunction? cellBuilder,
      List<TiledMapLoader>? maps}) async {
    this.rootComponent = rootComponent ?? this;
    _cellBuilder = cellBuilder;
    this.suspendedCellLifetime = suspendedCellLifetime;
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
    this.buildCellsPerUpdate = buildCellsPerUpdate;
    this.removeCellsPerUpdate = removeCellsPerUpdate;
  }

  List<TiledMapLoader> maps = [];
  CellBuilderFunction? _cellBuilder;
  double buildCellsPerUpdate = -1;
  double _buildCellsNow = 0;
  double removeCellsPerUpdate = -1;
  double _removeCellsNow = 0;

  double _suspendedCellLifetime = -1;

  set suspendedCellLifetime(Duration value) {
    _suspendedCellLifetime = value.inMicroseconds / 1000000;
  }

  Duration get suspendedCellLifetime =>
      Duration(microseconds: (_suspendedCellLifetime * 1000000).toInt());
  final _cellsForStateUpdate = <Cell>[];

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

  Future _buildNewCells() async {
    if (spatialGrid.cellsScheduledToBuild.isEmpty) return;

    if (buildCellsPerUpdate > 0) {
      _buildCellsNow += buildCellsPerUpdate;
      final cellsToProcess = _buildCellsNow.floor().toInt();
      for (var i = 0; i < cellsToProcess; i++) {
        final cell = spatialGrid.cellsScheduledToBuild.first;
        spatialGrid.cellsScheduledToBuild.remove(cell);
        await _cellBuilderMulti(cell, rootComponent);
        _cellsForStateUpdate.add(cell);
      }

      _buildCellsNow -= cellsToProcess;
    } else {
      for (final cell in spatialGrid.cellsScheduledToBuild) {
        await _cellBuilderMulti(cell, rootComponent);
        _cellsForStateUpdate.add(cell);
      }
    }
  }

  void removeUnusedCells() {
    final cellsToRemove = _catchCellsForRemoval();
    for (final cell in cellsToRemove) {
      cell.remove();
    }
    cellsToRemove.clear();
  }

  HashSet<Cell> _catchCellsForRemoval() {
    final cellsToRemove = HashSet<Cell>();
    for (final cell in spatialGrid.cells.values) {
      if (cell.state != CellState.suspended) continue;
      if (cell.beingSuspendedTimeMicroseconds > _suspendedCellLifetime) {
        cellsToRemove.add(cell);
      }
    }
    return cellsToRemove;
  }

  void _countSuspendedCellsTimers(double dt) {
    if (_suspendedCellLifetime > 0) {
      for (final cell in spatialGrid.cells.values) {
        if (cell.state != CellState.suspended) continue;
        cell.beingSuspendedTimeMicroseconds += dt;
      }
    }
  }

  _autoRemoveOldCells(double dt) {
    final cellsToRemove = _catchCellsForRemoval();
    if (cellsToRemove.isEmpty) return;

    if (removeCellsPerUpdate > 0) {
      _removeCellsNow += removeCellsPerUpdate;
      final cellsToProcess = _removeCellsNow.floor().toInt();
      for (var i = 0; i < cellsToProcess; i++) {
        final cell = cellsToRemove.first;
        cellsToRemove.remove(cell);
        cell.remove();
      }

      _removeCellsNow -= cellsToProcess;
    } else {
      for (final cell in cellsToRemove) {
        cell.remove();
      }
      cellsToRemove.clear();
    }
  }

  @override
  Future update(double dt) async {
    await _buildNewCells();
    if (_cellsForStateUpdate.isNotEmpty) {
      for (final cell in _cellsForStateUpdate) {
        cell.updateComponentsState();
      }
      _cellsForStateUpdate.clear();
    }
    _countSuspendedCellsTimers(dt);
    if (removeCellsPerUpdate > 0) {
      _autoRemoveOldCells(dt);
    }
    super.update(dt);
    collisionDetection.run();
  }
}
