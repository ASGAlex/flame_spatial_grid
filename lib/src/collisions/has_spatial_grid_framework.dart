import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

import 'package:flame_spatial_grid/src/collisions/collision_optimizer.dart';

/// This class is starting point to add Framework's abilities into you game
/// Calling [initializeSpatialGrid] at [onLoad] as absolute necessary! Also call
/// [gameInitializationDone] when all game objects are loaded and added.
/// If your game could be zoomed, please call [onAfterZoom] after every zoom event.
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

  /// Initializes the framework. This function *MUST* be called with [await]
  /// keyword to ensure that framework had been initialized correctly and all
  /// resources were loaded before game loop start.
  /// Call [gameInitializationDone] after this function and place game
  /// components initialization between.
  ///
  /// - [debug] (optional) - if you want to see how spatial grid is spread along
  ///   the game's space
  /// - [rootComponent] - a component at root of components tree. At this
  ///   component Framework will add all new components by default.
  /// - [blockSize] - size of grid's cells. Take care about this parameter!
  ///   Cells should be:
  ///   1. Bigger then every possible game component. This requirement is
  ///      strict.
  ///   2. But stay relatively small: then smaller cell is then faster the
  ///      collision detection system works. See [SpatialGridCollisionDetection]
  ///      for details.
  ///   3. But a big count of cells on the screen is not optimal for
  ///      rendering [CellLayer].
  ///   *Conclusion:* you should keep cells that size, when every cell contains
  ///   at least 50 static (non-moving) components, and normally no more than
  ///   20-30 cells would be displayed on the screen simultaneously.
  ///   So the "golden mean" should be found for every game individually. Try
  ///   to balance between described parameters.
  ///
  /// - [activeRadius] - count of active cells ([CellState.active]) around
  ///   tracked (player's) cell by X and Y dimensions.
  /// - [unloadRadius] - count of cells after last active cell (by X and Y
  ///   dimensions). These cells will work as usual but all components on it
  ///   will be hidden. Such cells are in [CellState.inactive] state.
  ///   The rest of grid cells will be moved into [CellState.suspended] state,
  ///   when no [updateTree] performed and all cell's components could be
  ///   unloaded from memory after some time.
  ///   So, unloadRadius specifies count of cells to preserve in
  ///   [CellState.inactive] state.
  /// - [suspendedCellLifetime] - how long a cell in [CellState.suspended]
  ///   state should being kept in memory. If state will not be changed, the
  ///   cell will be queued for unload. All components at this cell will be
  ///   removed from game tree, resources will be freed.
  /// - [buildCellsPerUpdate] and [removeCellsPerUpdate] - double values which
  ///   describes, how many cells should be built or to be removes at one
  ///   [update] call. Building new cells includes loading map's chunks,
  ///   creating new components. loading sprites, compiling image compositions
  ///   and so on, so it is not cheap operation. Creating 3-5 cells at once
  ///   can be cause of heavy freezes of the game. Removing cell also means
  ///   images disposing, components removal from tree - this is cheaper but
  ///   still not too fast. So specify "0.25", for example, if you want to make
  ///   the Framework to load (or unload) just 1 cell per 4 update() calls.
  /// - [trackWindowSize] - enable calculation of necessary [activeRadius] to
  ///   keep viewport filled by active cells only.
  /// - [trackedComponent] - a game component which will be the center of
  ///   active grid. Usually it is the player or a point where player will
  ///   spawn. Can be omitted, but [initialPosition] must be specified then!
  /// - [initialPosition] - initial position of spatial grid framework. If you
  ///   can not specify player's component at [onLoad] stage, omit
  ///   [trackedComponent] parameter and set [initialPosition] instead. Then
  ///   use [spatialGrid.trackedComponent] to specify your player's component at
  ///   game runtime, when it become accessible.
  /// - [cellBuilderNoMap] - cell builder function if cell does not belong to
  ///   any map, specified at [maps] or in [worldLoader].
  /// - [onAfterCellBuild] - function to be called when cell build was finished
  /// - [maps] - list of manually specified [TiledMapLoader] maps. Every map
  ///   will be loaded into game. May be not used if not needed.
  /// - [worldLoader] - if you use Tiled *.world files, this allows to load
  ///   whole world into game.
  /// - [lazyLoad] - do not load whole map / world into game. Initially just
  ///   loads map in [activeRadius] and then load map by chunks while player
  ///   discovers the map.
  ///
  Future<void> initializeSpatialGrid({
    bool? debug,
    Component? rootComponent,
    required double blockSize,
    Size? activeRadius,
    Size? unloadRadius,
    Duration suspendedCellLifetime = Duration.zero,
    double buildCellsPerUpdate = -1,
    double removeCellsPerUpdate = -1,
    bool trackWindowSize = true,
    HasGridSupport? trackedComponent,
    Vector2? initialPosition,
    CellBuilderFunction? cellBuilderNoMap,
    CellBuilderFunction? onAfterCellBuild,
    List<TiledMapLoader>? maps,
    WorldLoader? worldLoader,
    bool lazyLoad = true,
  }) async {
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
      game: this,
    );
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
        throw 'Lazy load initialization error!';
      }
    }
  }

  /// Should be called when Framework is initialized and all components are
  /// added into game.
  /// This functions enables windows dimensions tracking and calculating grid
  /// cells visible in viewport. It allows automatically enable or disable cells
  /// after window resizing or zoom changes
  void gameInitializationDone() {
    _gameInitializationFinished = true;
    if (trackWindowSize) {
      setRadiusByWindowDimensions();
    }
  }

  bool trackWindowSize = true;
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
      if (map.isCellOutsideOfMap(cell)) {
        continue;
      }
      cellOnMap = true;
      await map.cellBuilder(cell, rootComponent);
    }

    if (worldMaps != null) {
      for (final map in worldMaps) {
        if (map.isCellOutsideOfMap(cell)) {
          continue;
        }
        cellOnMap = true;
        map.cellBuilder(cell, rootComponent);
      }
    }

    if (!cellOnMap) {
      return _cellBuilderNoMap?.call(cell, rootComponent);
    }
  }

  set isSpatialGridDebugEnabled(bool debug) {
    if (_isSpatialGridDebugEnabled == debug) {
      return;
    }

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
    if (spatialGrid.cellsScheduledToBuild.isEmpty) {
      return;
    }

    if (buildCellsPerUpdate > 0) {
      _buildCellsNow += buildCellsPerUpdate;
      final cellsToProcess = _buildCellsNow.floor();
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
        if (cell.state == CellState.suspended) {
          continue;
        }
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
      if (cell.state != CellState.suspended) {
        continue;
      }
      if (cell.beingSuspendedTimeMicroseconds > _suspendedCellLifetime) {
        cellsToRemove.add(cell);
      }
    }
    return cellsToRemove;
  }

  void _countSuspendedCellsTimers(double dt) {
    if (_suspendedCellLifetime > 0) {
      for (final cell in spatialGrid.cells.values) {
        if (cell.state != CellState.suspended) {
          continue;
        }
        cell.beingSuspendedTimeMicroseconds += dt;
      }
    }
  }

  void _autoRemoveOldCells(double dt) {
    final cellsToRemove = _catchCellsForRemoval();
    if (cellsToRemove.isEmpty) {
      return;
    }

    if (removeCellsPerUpdate > 0) {
      _removeCellsNow += removeCellsPerUpdate;
      final cellsToProcess = _removeCellsNow.floor();
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
      // ignore: avoid_catches_without_on_clauses, empty_catches
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
