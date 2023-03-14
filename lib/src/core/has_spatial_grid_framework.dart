// ignore_for_file: comment_references

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/foundation.dart';

enum InitializationStepStage { none, cells, collisions, finalPass, done }

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

  final tilesetManager = TilesetManager();

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
  double buildCellsPerUpdate = -1;
  double _buildCellsNow = 0;

  double _suspendedCellLifetime = -1;
  Duration suspendCellPrecision = const Duration(minutes: 1);
  double _precisionDtCounter = 0;
  int cellsLimitToCleanup = 50;

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
    int processCellsLimitToPauseEngine = 250,
    double buildCellsPerUpdate = -1,
    int cellsLimitToCleanup = 50,
    bool trackWindowSize = true,
    HasGridSupport? trackedComponent,
    Vector2? initialPosition,
    CellBuilderFunction? cellBuilderNoMap,
    CellBuilderFunction? onAfterCellBuild,
    List<TiledMapLoader>? maps,
    WorldLoader? worldLoader,
    bool lazyLoad = true,
    int collisionOptimizerDefaultGroupLimit = 25,
  }) async {
    LoadingProgressManager.lastProgressMinimum = 0;
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
    this.suspendedCellLifetime = suspendedCellLifetime;
    this.suspendCellPrecision = suspendCellPrecision;
    this.cellsLimitToCleanup = cellsLimitToCleanup;
    this.worldLoader = worldLoader;
    this.trackWindowSize = trackWindowSize;
    collisionOptimizerGroupLimit = collisionOptimizerDefaultGroupLimit;
    this.processCellsLimitToPauseEngine = processCellsLimitToPauseEngine;
    if (maps != null) {
      this.maps = maps;
    }
    if (trackedComponent is SpatialGridCameraWrapper) {
      add(trackedComponent.cameraComponent);
      add(trackedComponent);
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
    if (trackWindowSize) {
      setRadiusByWindowDimensions();
    }

    _collisionDetection = SpatialGridCollisionDetection(
      spatialGrid: spatialGrid,
      onComponentTypeCheck: onComponentTypeCheck,
    );

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

  set suspendedCellLifetime(Duration value) {
    _suspendedCellLifetime = value.inMicroseconds / 1000000;
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
        await map.cellBuilder(cell, rootComponent);
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
    SpriteAnimationGlobalController.dispose();
    super.onRemove();
  }

  /// Because Framework implements it's own collision detection broadphase,
  /// with relatively same functionality as [QuadTreeBroadphase] has, but
  /// [GroupHitbox] are very special type and should me skipped.
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

  Future<void> _buildNewCells([
    bool forceAll = false,
    int progressMax = 80,
  ]) async {
    if (spatialGrid.cellsScheduledToBuild.isEmpty) {
      return;
    }

    if (!forceAll && buildCellsPerUpdate > 0) {
      _buildCellsNow += buildCellsPerUpdate;
      var cellsToProcess = _buildCellsNow.floor();
      for (var i = 0; i < cellsToProcess; i++) {
        if (spatialGrid.cellsScheduledToBuild.isNotEmpty) {
          final cell = spatialGrid.cellsScheduledToBuild.removeFirst();
          await _buildOneCell(cell);
        } else {
          cellsToProcess = i;
          break;
        }
      }

      _buildCellsNow -= cellsToProcess;
    } else {
      final total = spatialGrid.cellsScheduledToBuild.length;
      var processed = 0;
      final progressManager = LoadingProgressManager<String>(
        'Build cells',
        this,
        max: progressMax,
      );
      for (final cell in spatialGrid.cellsScheduledToBuild) {
        await _buildOneCell(cell);
        processed++;
        progressManager.setProgress(
          processed * 100 ~/ total,
          '$processed cells of $total built',
        );
      }
      spatialGrid.cellsScheduledToBuild.clear();
    }
  }

  Future<void> _buildOneCell(Cell cell) async {
    await _cellBuilderMulti(cell, rootComponent);
    await _onAfterCellBuild?.call(cell, rootComponent);
    cell.isCellBuildFinished = true;
    cell.updateComponentsState();
  }

  /// Manually remove outdated cells: cells in [spatialGrid.unloadRadius] and
  /// with [suspendedCellLifetime] is over.
  int removeUnusedCells([List<Cell>? unusedCells]) {
    print('==================');
    final broadphase = collisionDetection.broadphase;
    var l0 = spatialGrid.cells.length;
    var l1 = broadphase.optimizedCollisionsByGroupBox.length;
    var l2 = broadphase.activeCollisionsByCell.length;
    var l3 = broadphase.passiveCollisionsByCell.length;
    print('$l0 | $l1 | $l2 | $l3 ');

    final cellsToRemove = unusedCells ?? _catchCellsForRemoval();
    for (final cell in cellsToRemove) {
      cell.remove();
    }

    for (final entry in broadphase.optimizedCollisionsByGroupBox.entries
        .toList(growable: false)) {
      if (entry.value.isEmpty ||
          entry.key.isRemoving ||
          !spatialGrid.cells.containsKey(entry.key.rect)) {
        broadphase.optimizedCollisionsByGroupBox.remove(entry.key);
      }
    }
    for (final entry
        in broadphase.activeCollisionsByCell.entries.toList(growable: false)) {
      if (entry.value.isEmpty || entry.key.isRemoving) {
        broadphase.activeCollisionsByCell.remove(entry.key);
      }
    }
    for (final entry
        in broadphase.passiveCollisionsByCell.entries.toList(growable: false)) {
      if (entry.value.isEmpty || entry.key.isRemoving) {
        broadphase.passiveCollisionsByCell.remove(entry.key);
      }
    }

    // FIXME: memory leak here, this is dirty fix!
    // suspendedCellsCache empty, but suspended cells exists!
    for (final entry in spatialGrid.cells.entries.toList(growable: false)) {
      if (entry.value.state == CellState.suspended &&
          !spatialGrid.suspendedCellsCache.contains(entry.value)) {
        entry.value.remove();
      }
    }

    l0 = spatialGrid.cells.length;
    l1 = broadphase.optimizedCollisionsByGroupBox.length;
    l2 = broadphase.activeCollisionsByCell.length;
    l3 = broadphase.passiveCollisionsByCell.length;
    print('$l0 | $l1 | $l2 | $l3 ');

    return cellsToRemove.length;
  }

  List<Cell> _catchCellsForRemoval([bool forceCleanup = false]) {
    final cellsToRemove = <Cell>[];
    if (forceCleanup) {
      return spatialGrid.suspendedCellsCache
          .take(spatialGrid.cells.length - cellsLimitToCleanup)
          .toList(growable: false);
    } else {
      for (final cell in spatialGrid.suspendedCellsCache) {
        if (cell.beingSuspendedTimeMicroseconds > _suspendedCellLifetime) {
          cellsToRemove.add(cell);
        }
      }
    }
    return cellsToRemove;
  }

  void _countSuspendedCellsTimers(double dt) {
    if (_suspendedCellLifetime > 0) {
      for (final cell in spatialGrid.suspendedCellsCache) {
        cell.beingSuspendedTimeMicroseconds += dt;
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

  /// Handles creating new cells and removing outdated.
  /// Also runs [SpriteAnimationGlobalController] to allow
  /// [CellStaticAnimationLayer] to work.
  ///
  /// The rest of operations are made inside of [SpatialGridCollisionDetection]
  @override
  void update(double dt) {
    if (_gameInitializationFinished) {
      _precisionDtCounter += dt;
      List<Cell>? toBeRemoved;
      final forceCleanup = spatialGrid.cells.length > cellsLimitToCleanup;
      if (_precisionDtCounter * 1000000 >=
              suspendCellPrecision.inMicroseconds ||
          forceCleanup) {
        _countSuspendedCellsTimers(_precisionDtCounter);
        toBeRemoved = _catchCellsForRemoval(forceCleanup);
        _precisionDtCounter = 0;
      }

      final totalCellsToProcess =
          spatialGrid.cellsScheduledToBuild.length + (toBeRemoved?.length ?? 0);

      if (totalCellsToProcess > processCellsLimitToPauseEngine && !paused) {
        showLoadingComponent();
        pauseEngine();
        removeUnusedCells(toBeRemoved);
        _gameInitializationFinished = false;
        _initializationStepStage = InitializationStepStage.none;

        resumeEngine();
      } else {
        _buildNewCells();

        SpriteAnimationGlobalController.instance().update(dt);
        super.update(dt);
        collisionDetection.run();
      }
    } else {
      _doInitializationStep();
    }
  }

  int _totalCellsToBuild = -1;

  Future<void> _doInitializationStep() async {
    switch (_initializationStepStage) {
      case InitializationStepStage.none:
        _stepPrepareVariables();
        break;
      case InitializationStepStage.cells:
        _stepBuildCells();
        break;
      case InitializationStepStage.collisions:
        _stepPrepareCollisions();
        break;
      case InitializationStepStage.finalPass:
        _stepRepeatCellsBuild();
        break;
      case InitializationStepStage.done:
        _stepDone();
        break;
    }
  }

  Future<void> _stepPrepareVariables() async {
    _totalCellsToBuild = spatialGrid.cellsScheduledToBuild.length;
    _prepareCollisionsStage = 0;
    _initializationStepStage = InitializationStepStage.cells;
  }

  Future<void> _stepBuildCells() async {
    if (spatialGrid.cellsScheduledToBuild.isEmpty) {
      _initializationStepStage = InitializationStepStage.collisions;
      LoadingProgressManager.lastProgressMinimum = 90;
      return;
    }
    final processed =
        _totalCellsToBuild - spatialGrid.cellsScheduledToBuild.length;
    final progressManager = LoadingProgressManager<String>(
      'Build cells',
      this,
      max: 90,
    );
    final cell = spatialGrid.cellsScheduledToBuild.removeFirst();
    await _buildOneCell(cell);
    progressManager.setProgress(
      processed * 100 ~/ _totalCellsToBuild,
      '$processed cells of $_totalCellsToBuild built',
    );
  }

  int _prepareCollisionsStage = 0;

  Future<void> _stepPrepareCollisions() async {
    final progressManager = LoadingProgressManager<String>(
      'Optimize collisions',
      this,
      max: 95,
    );
    if (_prepareCollisionsStage == 0) {
      _prepareCollisionsStage = 1;
      progressManager.setProgress(10);
      return;
    }

    if (_prepareCollisionsStage == 1) {
      collisionDetection.run();
      super.update(0.001);
      progressManager.setProgress(40);
      _prepareCollisionsStage++;
      return;
    } else {
      pauseEngine();
      await layersManager.waitForComponents();
      collisionDetection.run();
      super.update(0.001);
      progressManager.setProgress(90);
      resumeEngine();

      _initializationStepStage = InitializationStepStage.finalPass;
      _totalCellsToBuild = spatialGrid.cellsScheduledToBuild.length;
      LoadingProgressManager.lastProgressMinimum = 95;
    }
  }

  Future<void> _stepRepeatCellsBuild() async {
    if (spatialGrid.cellsScheduledToBuild.isEmpty) {
      _initializationStepStage = InitializationStepStage.done;
      return;
    }

    final progressManager = LoadingProgressManager<String>(
      'Build additional cells',
      this,
      max: 99,
    );

    final processed =
        _totalCellsToBuild - spatialGrid.cellsScheduledToBuild.length;
    final cell = spatialGrid.cellsScheduledToBuild.removeFirst();
    await _buildOneCell(cell);
    progressManager.setProgress(
      processed * 100 ~/ _totalCellsToBuild,
      '$processed cells of $_totalCellsToBuild built',
    );
  }

  Future<void> _stepDone() async {
    final progressManager = LoadingProgressManager<String>(
      'Done',
      this,
    );
    progressManager.setProgress(100);

    _gameInitializationFinished = true;
    onInitializationDone();
  }

  @protected
  Future<void> showLoadingComponent() async {}

  Future<void> hideLoadingComponent() async {}
}
