import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/tiled/world_loader.dart';

import 'collision_optimizer.dart';

mixin HasSpatialGridFramework on FlameGame
    implements HasCollisionDetection<SpatialGridBroadphase<ShapeHitbox>> {
  late SpatialGridCollisionDetection _collisionDetection;
  late final SpatialGrid spatialGrid;
  late Component rootComponent;
  SpatialGridDebugComponent? _spatialGridDebug;
  bool _isSpatialGridDebugEnabled = false;
  TiledMapLoader? defaultMap;
  bool _gameInitializationFinished = false;
  late final LayersManager layersManager;

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

  void gameInitializationDone() {
    _gameInitializationFinished = true;
    if (trackWindowSize) {
      setRadiusByWindowDimensions();
    }
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
      Size? activeRadius,
      Size? unloadRadius,
      bool trackWindowSize = true,
      HasGridSupport? trackedComponent,
      Vector2? initialPosition,
      bool lazyLoad = true,
      double buildCellsPerUpdate = -1,
      double removeCellsPerUpdate = -1,
      Duration suspendedCellLifetime = Duration.zero,
      CellBuilderFunction? cellBuilderNoMap,
      CellBuilderFunction? onAfterCellBuild,
      List<TiledMapLoader>? maps,
      WorldLoader? worldLoader}) async {
    layersManager = LayersManager(this);
    this.rootComponent = rootComponent ?? this;
    this.rootComponent.add(layersManager.layersRootComponent);
    _cellBuilderNoMap = cellBuilderNoMap;
    _onAfterCellBuild = onAfterCellBuild;
    this.suspendedCellLifetime = suspendedCellLifetime;
    this.worldLoader = worldLoader;
    this.trackWindowSize = trackWindowSize;
    if (maps != null) {
      this.maps = maps;
    }
    spatialGrid = SpatialGrid(
        blockSize: Size.square(blockSize),
        trackedComponent: trackedComponent,
        initialPosition: initialPosition,
        activeRadius: activeRadius,
        unloadRadius: unloadRadius,
        lazyLoad: lazyLoad,
        game: this);
    if (trackWindowSize) {
      setRadiusByWindowDimensions();
    }

    _collisionDetection = SpatialGridCollisionDetection(
      spatialGrid: spatialGrid,
      onComponentTypeCheck: onComponentTypeCheck,
    );

    isSpatialGridDebugEnabled = debug ?? false;

    for (final map in this.maps) {
      await map.init(this);
      TiledMapLoader.loadedMaps.add(map);
    }
    if (worldLoader != null) {
      await worldLoader.init(this);
    }
    this.buildCellsPerUpdate = buildCellsPerUpdate;
    this.removeCellsPerUpdate = removeCellsPerUpdate;

    if (lazyLoad) {
      final currentCell = spatialGrid.currentCell;
      if (currentCell != null) {
        spatialGrid.currentCell = currentCell;
      } else {
        throw "Lazy load initialization error!";
      }
    }
  }

  var trackWindowSize = true;
  List<TiledMapLoader> maps = [];
  WorldLoader? worldLoader;
  CellBuilderFunction? _cellBuilderNoMap;
  CellBuilderFunction? _onAfterCellBuild;
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

  Future<void> _cellBuilderMulti(Cell cell, Component rootComponent) async {
    final worldMaps = worldLoader?.maps;
    if (maps.isEmpty && (worldMaps == null || worldMaps.isEmpty)) {
      return _cellBuilderNoMap?.call(cell, rootComponent);
    }

    var cellOnMap = false;
    for (final map in maps) {
      if (map.isCellOutsideOfMap(cell)) continue;
      cellOnMap = true;
      await map.cellBuilder(cell, rootComponent);
    }

    if (worldMaps != null) {
      for (final map in worldMaps) {
        if (map.isCellOutsideOfMap(cell)) continue;
        cellOnMap = true;
        map.cellBuilder(cell, rootComponent);
      }
    }

    if (!cellOnMap) {
      return _cellBuilderNoMap?.call(cell, rootComponent);
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
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    if (_gameInitializationFinished && trackWindowSize) {
      setRadiusByWindowDimensions();
      spatialGrid.updateCellsStateByRadius();
    }
  }

  @override
  void onRemove() {
    isSpatialGridDebugEnabled = false;
    _spatialGridDebug = null;
    spatialGrid.dispose();
    super.onRemove();
  }

  bool onComponentTypeCheck(PositionComponent one, PositionComponent another) {
    var checkParent = false;
    if (one is GenericCollisionCallbacks) {
      if (!(one as GenericCollisionCallbacks).onComponentTypeCheck(another)) {
        return false;
      }
    } else {
      checkParent = true;
    }

    if (another is GenericCollisionCallbacks) {
      if (!(another as GenericCollisionCallbacks).onComponentTypeCheck(one)) {
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
        if (cell.state == CellState.suspended) {
          cell.scheduleToBuild = true;
          continue;
        }
        spatialGrid.cellsScheduledToBuild.remove(cell);
        await _cellBuilderMulti(cell, rootComponent);
        await _onAfterCellBuild?.call(cell, rootComponent);
        cell.isCellBuildFinished = true;
        cell.updateComponentsState();
      }

      _buildCellsNow -= cellsToProcess;
    } else {
      for (final cell in spatialGrid.cellsScheduledToBuild) {
        if (cell.state == CellState.suspended) continue;
        await _cellBuilderMulti(cell, rootComponent);
        await _onAfterCellBuild?.call(cell, rootComponent);
        cell.isCellBuildFinished = true;
        cell.updateComponentsState();
      }
      spatialGrid.cellsScheduledToBuild.clear();
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

  void setRadiusByWindowDimensions() {
    try {
      final camera = children.whereType<CameraComponent>().single;

      final visibleSize = camera.viewport.size / camera.viewfinder.zoom;
      final cellsXRadius =
          (visibleSize.x / spatialGrid.blockSize.width / 2).ceil().toDouble();
      final cellsYRadius =
          (visibleSize.y / spatialGrid.blockSize.height / 2).ceil().toDouble();
      spatialGrid.activeRadius = Size(cellsXRadius, cellsYRadius);
    } catch (e) {}
  }

  void onAfterZoom() {
    setRadiusByWindowDimensions();
    spatialGrid.updateCellsStateByRadius();
  }

  @override
  Future update(double dt) async {
    await _buildNewCells();
    _countSuspendedCellsTimers(dt);
    if (removeCellsPerUpdate > 0) {
      _autoRemoveOldCells(dt);
    }

    SpriteAnimationGlobalController.instance.update(dt);
    super.update(dt);
    collisionDetection.run();
  }
}
