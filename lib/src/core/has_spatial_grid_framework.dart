// ignore_for_file: comment_references
import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/foundation.dart';

enum InitializationStepStage {
  none,
  cells,
  collisions,
  finalPass,
  layers,
  done
}

/// This class is starting point to add Framework's abilities into you game
/// Calling [initializeSpatialGrid] at [onLoad] as absolute necessary!
/// If your game could be zoomed, please call [onAfterZoom] after every zoom
/// event.
mixin HasSpatialGridFramework on FlameGame
    implements HasCollisionDetection<SpatialGridBroadphase<ShapeHitbox>> {
  late SpatialGridCollisionDetection _collisionDetection;

  /// The spatial grid instance for this game, contains at least one cell.
  /// Useful to access specified cell, find a cell bu position on map and so on.
  late final SpatialGrid spatialGrid;

  /// A root component, to which all other components will be added by the
  /// framework.
  late Component rootComponent;

  /// Use this class to manage [CellLayer]s instead of creating them manually.
  /// It manages recourses automatically, according to cell's state.
  late final LayersManager layersManager;

  final tickersManager = TickersManager();

  final tilesetManager = TilesetManager();

  late final TileBuilderContextProvider<HasSpatialGridFramework>
      tileBuilderContextProvider;

  /// Enables or disables automatic [spatialGrid.activeRadius] control according
  /// to viewport size and zoom level.
  bool trackWindowSize = true;

  SpatialGridDebugComponent? _spatialGridDebug;
  bool _isSpatialGridDebugEnabled = false;
  TiledMapLoader? defaultMap;
  bool _gameInitializationFinished = false;

  List<TiledMapLoader> maps = [];
  WorldLoader? worldLoader;
  CellBuilderFunction? _cellBuilderNoMap;
  CellBuilderFunction? _onAfterCellBuild;
  double buildCellsPerUpdate = 1;
  double _buildCellsNow = 0;

  double _suspendedCellLifetime = -1;
  Duration suspendCellPrecision = const Duration(minutes: 1);
  double _precisionDtCounter = 0;
  double cleanupCellsPerUpdate = 1;

  int collisionOptimizerGroupLimit = 25;
  int processCellsLimitToPauseEngine = 250;

  var _initializationStepStage = InitializationStepStage.none;

  /// Initializes the framework. This function *MUST* be called with [await]
  /// keyword to ensure that framework had been initialized correctly and all
  /// resources were loaded before game loop start.
  /// Some of parameters could be changed at runtime, see [spatialGrid] for
  /// details.
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
  /// - [buildCellsPerUpdate]  - double values which
  ///   describes, how many cells should be built at one
  ///   [update] call. Building new cells includes loading map's chunks,
  ///   creating new components. loading sprites, compiling image compositions
  ///   and so on, so it is not cheap operation. Creating 3-5 cells at once
  ///   can be cause of heavy freezes of the game. Removing cell also means
  ///   images disposing, components removal from tree - this is cheaper but
  ///   still not too fast. So specify "0.25", for example, if you want to make
  ///   the Framework to load just 1 cell per 4 update() calls.
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
    Size? preloadRadius,
    Duration suspendedCellLifetime = Duration.zero,
    Duration suspendCellPrecision = const Duration(minutes: 1),
    int maxCells = 0,
    int processCellsLimitToPauseEngine = 5,
    double buildCellsPerUpdate = 1,
    double cleanupCellsPerUpdate = 2,
    bool trackWindowSize = true,
    HasGridSupport? trackedComponent,
    Vector2? initialPosition,
    InitialPositionChecker? initialPositionChecker,
    CellBuilderFunction? cellBuilderNoMap,
    CellBuilderFunction? onAfterCellBuild,
    List<TiledMapLoader>? maps,
    WorldLoader? worldLoader,
    bool lazyLoad = true,
    int collisionOptimizerDefaultGroupLimit = 25,
  }) async {
    showLoadingComponent();
    final progressManager = LoadingProgressManager<String>(
      'spatial grid',
      this,
    );
    progressManager.setProgress(0, 'Init core variables');

    layersManager = LayersManager(this);
    this.rootComponent = rootComponent ?? this;
    this.rootComponent.add(layersManager.layersRootComponent);
    _cellBuilderNoMap = cellBuilderNoMap;
    _onAfterCellBuild = onAfterCellBuild;
    this.maxCells = maxCells;
    this.suspendedCellLifetime = suspendedCellLifetime;
    this.suspendCellPrecision = suspendCellPrecision;
    this.cleanupCellsPerUpdate = cleanupCellsPerUpdate;
    this.worldLoader = worldLoader;
    this.trackWindowSize = trackWindowSize;
    collisionOptimizerGroupLimit = collisionOptimizerDefaultGroupLimit;
    this.processCellsLimitToPauseEngine = processCellsLimitToPauseEngine;
    tileBuilderContextProvider =
        TileBuilderContextProvider<HasSpatialGridFramework>(parent: this);
    if (maps != null) {
      this.maps = maps;
    }

    if (initialPosition == null && initialPositionChecker != null) {
      if (worldLoader != null) {
        final position =
            await worldLoader.searchInitialPosition(initialPositionChecker);
        if (position != null) {
          initialPosition = position;
        }
      }
      if (initialPosition == null) {
        for (final map in this.maps) {
          final position =
              await map.searchInitialPosition(initialPositionChecker);
          if (position != null) {
            initialPosition = position;
            break;
          }
        }
      }
    }

    spatialGrid = SpatialGrid(
      blockSize: Size.square(blockSize),
      trackedComponent: trackedComponent,
      initialPosition: initialPosition,
      activeRadius: activeRadius,
      unloadRadius: unloadRadius,
      preloadRadius: preloadRadius,
      lazyLoad: lazyLoad,
      game: this,
    );

    _collisionDetection = SpatialGridCollisionDetection(
      spatialGrid: spatialGrid,
      onComponentExtendedTypeCheck: onComponentTypeCheck,
      pureTypeCheck: pureTypeCheck,
    );

    if (trackedComponent is SpatialGridCameraWrapper) {
      add(trackedComponent.cameraComponent);
      add(trackedComponent);
    }

    spatialGrid.updateCellsStateByRadius();

    isSpatialGridDebugEnabled = debug ?? false;

    progressManager.setProgress(10, 'Loading worlds and maps');
    LoadingProgressManager.lastProgressMinimum = 10;

    for (final map in this.maps) {
      await map.init(this);
      TiledMapLoader.loadedMaps.add(map);
    }
    if (worldLoader != null) {
      await worldLoader.init(this);
    }
    this.buildCellsPerUpdate = buildCellsPerUpdate;

    if (lazyLoad) {
      final currentCell = spatialGrid.currentCell;
      if (currentCell != null) {
        spatialGrid.currentCell = currentCell;
      } else {
        throw 'Lazy load initialization error!';
      }
    }
  }

  void _clearStaticVariables() {
    LoadingProgressManager.lastProgressMinimum = 0;
    HasGridSupport.cachedCenters.clear();
    HasGridSupport.componentHitboxes.clear();
    HasGridSupport.defaultCollisionType.clear();
    TilesetManager.dispose();
    TiledMapLoader.disposeAll();
  }

  void onInitializationDone() {}

  void onLoadingProgress<M>(LoadingProgressMessage<M> message) {
    if (kDebugMode) {
      if (message.data is String) {
        print('${message.type} | progress: ${message.progress}% '
            '| ${message.data}');
      } else {
        print('${message.type} | progress: ${message.progress}%');
      }
    }
  }

  /// Call this at you application code at every place where zoom is done.
  /// Necessary for adopting [spatialGrid.activeRadius] to current screen's
  /// dimensions, including zoom level.
  void onAfterZoom() {
    setRadiusByWindowDimensions();
    spatialGrid.updateCellsStateByRadius();
  }

  int maxCells = 0;

  set suspendedCellLifetime(Duration value) {
    _suspendedCellLifetime = value.inMicroseconds / 1000000;
  }

  Cell? findCellForComponent(HasGridSupport component) {
    final componentCenter = Vector2.zero();
    if (component.boundingBox.isMounted) {
      componentCenter.setFrom(component.boundingBox.aabbCenter);
    } else {
      componentCenter.setFrom(
        component.anchor.toOtherAnchorPosition(
          component.position,
          Anchor.center,
          component.size,
        ),
      );
    }
    var cell = component.currentCell;
    cell ??= component.currentCell =
        spatialGrid.findExistingCellByPosition(componentCenter);
    cell ??= component.currentCell =
        spatialGrid.createNewCellAtPosition(componentCenter);
    return cell;
  }

  /// How long a cell in [CellState.suspended]
  /// state should being kept in memory. If state will not be changed, the
  /// cell will be queued for unload. All components at this cell will be
  /// removed from game tree, resources will be freed.
  Duration get suspendedCellLifetime =>
      Duration(microseconds: (_suspendedCellLifetime * 1000000).toInt());

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

  Future<bool> _cellBuilderMulti(Cell cell, Component rootComponent) async {
    if (TiledMapLoader.loadedMaps.isEmpty) {
      await _cellBuilderNoMap?.call(cell, rootComponent, true);
      return true;
    }

    final cache = <Rect, int>{};
    var isFullyOutside = false;
    final processedCellsNoMap = HashSet<Cell>();
    for (final map in TiledMapLoader.loadedMaps) {
      var pointsOutside = cache[cell.rect];
      if (pointsOutside == null) {
        cache[cell.rect] = pointsOutside = map.cellPointsOutsideOfMap(cell);
      } else {
        pointsOutside = cache[cell.rect];
      }
      if (pointsOutside == 0) {
        await map.cellBuilder(cell, rootComponent);
      } else if (pointsOutside == 4) {
        isFullyOutside = true;
        if (!processedCellsNoMap.contains(cell)) {
          await _cellBuilderNoMap?.call(cell, rootComponent, true);
          processedCellsNoMap.add(cell);
        }
      } else {
        if (!processedCellsNoMap.contains(cell)) {
          await _cellBuilderNoMap?.call(cell, rootComponent, false);
          processedCellsNoMap.add(cell);
        }
        await map.cellBuilder(cell, rootComponent);
      }
    }
    processedCellsNoMap.clear();

    return isFullyOutside;
  }

  set isSpatialGridDebugEnabled(bool debug) {
    if (_isSpatialGridDebugEnabled == debug) {
      return;
    }

    _isSpatialGridDebugEnabled = debug;
    if (_isSpatialGridDebugEnabled) {
      _spatialGridDebug ??= SpatialGridDebugComponent(spatialGrid)
        ..priority = 9999999;
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
    maps.clear();
    layersManager.layers.clear();
    descendants(reversed: true).forEach((element) {
      element.removeFromParent();
    });
    processLifecycleEvents();
    collisionDetection.dispose();
    _clearStaticVariables();
    super.onRemove();
  }

  bool pureTypeCheck(Type activeItemType, Type potentialItemType) => true;

  /// Because Framework implements it's own collision detection broadphase,
  /// with relatively same functionality as [QuadTreeBroadphase] has, but
  /// [GroupHitbox] are very special type and should me skipped.
  bool onComponentTypeCheck(ShapeHitbox first, ShapeHitbox second) {
    return first.onComponentTypeCheck(second) &&
        second.onComponentTypeCheck(first);
  }

  Future<void> _buildNewCells([
    bool forceAll = false,
  ]) async {
    if (spatialGrid.cellsScheduledToBuild.isEmpty) {
      return;
    }

    final futures = <Future<void>>[];
    if (!forceAll && buildCellsPerUpdate > 0) {
      _buildCellsNow += buildCellsPerUpdate;
      var cellsToProcess = _buildCellsNow.floor();
      for (var i = 0; i < cellsToProcess; i++) {
        if (spatialGrid.cellsScheduledToBuild.isNotEmpty) {
          final cell = spatialGrid.cellsScheduledToBuild.removeFirst();
          futures.add(_buildOneCell(cell));
        } else {
          cellsToProcess = i;
          break;
        }
      }

      _buildCellsNow -= cellsToProcess;
    } else {
      for (final cell in spatialGrid.cellsScheduledToBuild) {
        futures.add(_buildOneCell(cell));
      }
      spatialGrid.cellsScheduledToBuild.clear();
    }

    await Future.wait<void>(futures);
    return;
  }

  Future<void> _buildOneCell(Cell cell) async {
    final isFullyOutside = await _cellBuilderMulti(cell, rootComponent);
    await _onAfterCellBuild?.call(cell, rootComponent, isFullyOutside);
    cell.isCellBuildFinished = true;
    cell.updateComponentsState();
  }

  /// Manually remove outdated cells: cells in [spatialGrid.unloadRadius] and
  /// with [suspendedCellLifetime] is over.
  int removeUnusedCells({bool forceCleanup = false, List<Cell>? unusedCells}) {
    final cellsToRemove = unusedCells ?? _catchCellsForRemoval(forceCleanup);
    print('removing unused cells: ${cellsToRemove.length}');
    for (final cell in cellsToRemove) {
      cell.remove();
    }

    // var i = 0;
    // for (final wr in BoundingHitbox.weakRef.toList(growable: false)) {
    //   final hb = wr.target;
    //   if (hb != null) {
    //     i++;
    //   }
    // }
    // print('total: ${BoundingHitbox.weakRef.length}; Not null: $i');

    print('removing unused cells DONE');
    return cellsToRemove.length;
  }

  List<Cell> _catchCellsForRemoval([bool forceCleanup = false]) {
    final cellsToRemove = <Cell>[];

    if (maxCells > 0 && spatialGrid.cells.length >= maxCells) {
      final cellsToCatch = spatialGrid.cells.length - maxCells;
      final unloadLessPriority = <Cell>[];
      for (final cell in spatialGrid.cells.values) {
        if (cellsToRemove.length >= cellsToCatch) {
          break;
        }

        if (cell.state != CellState.suspended) {
          continue;
        }

        if (cell.beingSuspendedTimeMicroseconds > _suspendedCellLifetime) {
          cellsToRemove.add(cell);
        } else {
          unloadLessPriority.add(cell);
        }
      }

      if (cellsToRemove.length < cellsToCatch) {
        cellsToRemove.addAll(
          unloadLessPriority.take(cellsToCatch - cellsToRemove.length),
        );
      }
      return cellsToRemove;
    }
    if (forceCleanup || cleanupCellsPerUpdate < 0) {
      cellsToRemove.addAll(
        spatialGrid.cells.values
            .where((element) => element.state == CellState.suspended),
      );
    } else {
      for (final cell in spatialGrid.cells.values) {
        if (cellsToRemove.length >= cleanupCellsPerUpdate) {
          break;
        }
        if (cell.state != CellState.suspended) {
          continue;
        }
        if (cell.beingSuspendedTimeMicroseconds > _suspendedCellLifetime) {
          cellsToRemove.add(cell);
        }
      }
    }

    return cellsToRemove;
  }

  void _countSuspendedCellsTimers(double dt) {
    if (_suspendedCellLifetime > 0) {
      for (final cell in spatialGrid.cells.values) {
        if (cell.state == CellState.suspended) {
          cell.beingSuspendedTimeMicroseconds += dt;
        }
      }
    }
  }

  @protected
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

  final _cellsToBeRemoved = <Cell>[];

  /// Handles creating new cells and removing outdated.
  /// Also runs [SpriteAnimationGlobalController] to allow
  /// [CellStaticAnimationLayer] to work.
  ///
  /// The rest of operations are made inside of [SpatialGridCollisionDetection]
  @override
  Future<void> update(double dt) async {
    if (_gameInitializationFinished) {
      _precisionDtCounter += dt;
      if (_precisionDtCounter * 1000000 >=
          suspendCellPrecision.inMicroseconds) {
        _countSuspendedCellsTimers(_precisionDtCounter);
        _precisionDtCounter = 0;
      }
      final toBeRemoved = _catchCellsForRemoval();

      if (spatialGrid.cellsScheduledToBuild.length >
              processCellsLimitToPauseEngine &&
          !paused) {
        showLoadingComponent();
        pauseEngine();
        if (toBeRemoved.isNotEmpty) {
          removeUnusedCells(unusedCells: toBeRemoved);
        }
        _gameInitializationFinished = false;
        _initializationStepStage = InitializationStepStage.none;

        resumeEngine();
      } else {
        if (toBeRemoved.isNotEmpty) {
          removeUnusedCells(unusedCells: toBeRemoved);
        }
        _buildNewCells();

        tickersManager.update(dt);
        collisionDetection.dt = dt;
        collisionDetection.run();
        super.update(dt);
      }
    } else {
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsedMilliseconds <= 500 &&
          !_gameInitializationFinished) {
        final doInterfaceUpdate = await _doInitializationStep();
        if (doInterfaceUpdate) {
          break;
        }
      }
      stopwatch.stop();
    }
  }

  int _totalCellsToBuild = -1;

  Future<bool> _doInitializationStep() async {
    switch (_initializationStepStage) {
      case InitializationStepStage.none:
        return _stepPrepareVariables();
      case InitializationStepStage.cells:
        return _stepBuildCells();
      case InitializationStepStage.collisions:
        return _stepPrepareCollisions();
      case InitializationStepStage.finalPass:
        return _stepRepeatCellsBuild();
      case InitializationStepStage.layers:
        return _stepOptimizeLayers();
      case InitializationStepStage.done:
        return _stepDone();
    }
  }

  Future<bool> _stepPrepareVariables() async {
    LoadingProgressManager.lastProgressMinimum = 10;
    _totalCellsToBuild = spatialGrid.cellsScheduledToBuild.length;
    _prepareCollisionsStage = 0;
    _initializationStepStage = InitializationStepStage.cells;
    return true;
  }

  final _cellsBuildingFutures = <Future>[];

  Future<bool> _stepBuildCells() async {
    final progressManager = LoadingProgressManager<String>(
      'Build cells',
      this,
      max: 60,
    );
    if (spatialGrid.cellsScheduledToBuild.isEmpty) {
      _initializationStepStage = InitializationStepStage.collisions;
      LoadingProgressManager.lastProgressMinimum = 60;
      await Future.wait<void>(_cellsBuildingFutures);
      progressManager.setProgress(100, 'All cells loaded');
      _cellsBuildingFutures.clear();
      return true;
    }
    if (_totalCellsToBuild == 0) {
      _totalCellsToBuild = spatialGrid.cellsScheduledToBuild.length;
    }
    final processed =
        _totalCellsToBuild - spatialGrid.cellsScheduledToBuild.length;

    final cell = spatialGrid.cellsScheduledToBuild.removeFirst();
    _cellsBuildingFutures.add(_buildOneCell(cell));
    progressManager.setProgress(
      processed * 100 ~/ _totalCellsToBuild,
      '$processed cells of $_totalCellsToBuild built',
    );
    return false;
  }

  int _prepareCollisionsStage = 0;

  Future<bool> _stepPrepareCollisions() async {
    final progressManager = LoadingProgressManager<String>(
      'Prepare collisions',
      this,
      max: 70,
    );
    if (_prepareCollisionsStage == 0) {
      _prepareCollisionsStage = 1;
      progressManager.setProgress(10);
      return false;
    }

    if (_prepareCollisionsStage == 1) {
      final toBeRemoved = _catchCellsForRemoval();
      removeUnusedCells(unusedCells: toBeRemoved);
      collisionDetection.broadphase.update();
      processLifecycleEvents();
      progressManager.setProgress(40);
      _prepareCollisionsStage++;
      return true;
    } else {
      pauseEngine();
      await layersManager.waitForComponents();
      collisionDetection.broadphase.update();
      processLifecycleEvents();
      progressManager.setProgress(90);
      resumeEngine();

      _initializationStepStage = InitializationStepStage.finalPass;
      _totalCellsToBuild = spatialGrid.cellsScheduledToBuild.length;
      LoadingProgressManager.lastProgressMinimum = 70;
      return true;
    }
  }

  final _layersToUpdate = <CellLayer>[];
  var _totalLayersToBuild = 0;

  Future<bool> _stepRepeatCellsBuild() async {
    if (spatialGrid.cellsScheduledToBuild.isEmpty) {
      _initializationStepStage = InitializationStepStage.layers;
      _layersToUpdate.clear();
      for (final map in layersManager.layers.values) {
        _layersToUpdate.addAll(
          map.values.where((element) => element.collisionOptimizer.isEmpty),
        );
      }
      _totalLayersToBuild = _layersToUpdate.length;
      LoadingProgressManager.lastProgressMinimum = 75;
      Future.wait<void>(_cellsBuildingFutures);
      _cellsBuildingFutures.clear();
      return true;
    }

    final progressManager = LoadingProgressManager<String>(
      'Build additional cells',
      this,
      max: 75,
    );

    if (_totalCellsToBuild == 0) {
      _totalCellsToBuild = spatialGrid.cellsScheduledToBuild.length;
    }

    final processed =
        _totalCellsToBuild - spatialGrid.cellsScheduledToBuild.length;
    final cell = spatialGrid.cellsScheduledToBuild.removeFirst();
    _cellsBuildingFutures.add(_buildOneCell(cell));
    progressManager.setProgress(
      processed * 100 ~/ _totalCellsToBuild,
      '$processed cells of $_totalCellsToBuild built',
    );
    return false;
  }

  Future<bool> _stepOptimizeLayers() async {
    if (_layersToUpdate.isEmpty) {
      await Future.wait<void>(_cellsBuildingFutures);
      _cellsBuildingFutures.clear();
      _initializationStepStage = InitializationStepStage.done;
      _layersToUpdate.clear();
      return true;
    }

    final progressManager = LoadingProgressManager<String>(
      'Build layers',
      this,
    );

    if (_totalLayersToBuild == 0) {
      _totalLayersToBuild = _layersToUpdate.length;
    }

    final processed = _totalLayersToBuild - _layersToUpdate.length;
    final layer = _layersToUpdate.removeLast();
    _cellsBuildingFutures.add(layer.updateLayer());

    progressManager.setProgress(
      processed * 100 ~/ _totalLayersToBuild,
      '$processed layers of $_totalLayersToBuild built',
    );
    return false;
  }

  Future<bool> _stepDone() async {
    final progressManager = LoadingProgressManager<String>(
      'Done',
      this,
    );
    progressManager.setProgress(100);

    _gameInitializationFinished = true;
    onInitializationDone();
    return true;
  }

  @protected
  Future<void> showLoadingComponent() async {}

  Future<void> hideLoadingComponent() async {}
}
