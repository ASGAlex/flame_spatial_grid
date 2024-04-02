import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame_fast_touch/flame_fast_touch.dart';
import 'package:flame_message_stream/flame_message_stream.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image, Draggable;
import 'package:flutter/services.dart';

//#region World

const tileSize = 8.0;
const blockSize = 128.0;

class SpatialGridExample extends FlameGame<MyWorld>
    with
        HasSpatialGridFramework,
        KeyboardEvents,
        ScrollDetector,
        ScaleDetector,
        TapCallbacks,
        FastTouch<MyWorld>,
        HasMessageProviders {
  SpatialGridExample() : super(world: MyWorld()) {
    loadingStream = messageProvidersManager
        .getMessageProvider<LoadingProgressMessage<String>>('loading_progress')
        .messagingStream;
  }

  static const description = '''
In this example the "Clusterizer" algorithm work. 
Algorithm takes control over collision detection, components rendering and
components lifecycle and frequency of updates. This allows to gain application
performance by saving additional resources. Also a special 'Layer-components'
are used to compile statical components to single layer but keeping ability to
update layer's image as soon as components parameters are changed.

Use WASD to move the player and use the mouse scroll to change zoom.
Hold direction button and press space to fire a bullet. 
Notice that bullet will fly above water but collides with bricks.

Press LShift button to toggle firing bullets which also destroys water.

Press T button to toggle player to collide with other objects.

Press at any screen point to teleport Player instantly to the click position.

Press M button to show clusters debugging info. Green clusters are active 
clusters, where components are viewed as usual, update() and collision detection
works its ordinary way.
Grey clusters are inactive clusters. Such clusters intend to be 
"out-of-the-screen", components are not rendering inside such clusters.
Dark clusters shown if you moved too far for your's starting position. Such
clusters are suspended: components are not rendering, update() not work and 
all collisions are disabled.
  ''';

  late final Stream<LoadingProgressMessage<String>> loadingStream;

  @override
  Future<void> onLoad() async {
    pureTypeCheckWarmUpComponents = [
      Player(position: Vector2.zero(), size: Vector2.zero(), priority: 0),
      Npc(position: Vector2.zero(), size: Vector2.zero(), priority: 0),
      Brick(position: Vector2.zero(), sprite: null),
      Water(position: Vector2.zero(), animation: null),
      Bullet(position: Vector2.zero(), displacement: Vector2.zero()),
      BoundingBoxGridGame(),
    ];
    super.onLoad();
    player = world.player;
    camera.viewfinder.zoom = 5;
    camera.priority = 999;
    camera.follow(player, maxSpeed: 200, snap: true);
    final touchEventsHandler = TouchEventsHandler();
    world.add(touchEventsHandler);
    componentsAtPointRoot = touchEventsHandler;

    // check that manual loading works correctly (not necessary line)
    await tilesetManager.loadTileset('tileset.tsx');

    Size preloadRadius;
    Size unloadRadius;
    double buildCellsPerUpdate;
    double cleanupCellsPerUpdate;
    int processCellsLimitToPauseEngine;
    if (kIsWeb) {
      preloadRadius = const Size(1, 1);
      unloadRadius = const Size(1, 1);
      processCellsLimitToPauseEngine = 20;
      buildCellsPerUpdate = 1;
      cleanupCellsPerUpdate = 1;
    } else {
      preloadRadius = const Size(5, 5);
      unloadRadius = const Size(3, 3);
      processCellsLimitToPauseEngine = 50;
      buildCellsPerUpdate = 2;
      cleanupCellsPerUpdate = 2;
    }
    await initializeSpatialGrid(
      debug: false,
      unloadRadius: unloadRadius,
      preloadRadius: preloadRadius,
      processCellsLimitToPauseEngine: processCellsLimitToPauseEngine,
      collisionOptimizerDefaultGroupLimit: 50,
      cellSize: blockSize,
      trackedComponent: SpatialGridDebugCameraWrapper(camera),
      initialPositionChecker: (layer, object, mapOffset, worldName) {
        if (worldName == null) {
          return null;
        }
        if (object.name == 'spawn_player') {
          camera.viewfinder.position =
              player.position = mapOffset + Vector2(object.x, object.y);

          return player.position;
        }
        return null;
      },
      buildCellsPerUpdate: buildCellsPerUpdate,
      cleanupCellsPerUpdate: cleanupCellsPerUpdate,
      suspendedCellLifetime: const Duration(minutes: 10),
      scheduledLayerOperationLimit: 1,
      cellBuilderNoMap: noMapCellBuilder,
      maps: [
        DemoMapLoader(Vector2(600, 0)),
      ],
      worldLoader: WorldLoader(
        fileName: 'example.world',
        loadWholeMap: false,
        mapLoader: {
          'example': DemoMapLoader.new,
          'another_map': DemoMapLoader.new,
        },
      ),
    );
    // await demoMapLoader.init(this);

    world.add(player);
    add(FpsTextComponent());
  }

  final elapsedMicroseconds = <double>[];

  late Player player;
  var _fireBullet = false;
  var _killWater = false;

  bool teleportMode = true;
  bool trailsEnabled = true;
  bool isAIEnabled = true;
  bool _drawOutOfBoundsCounter = false;

  final fadeOutConfig = FadeOutConfig(
    fadeOutTimeout: const Duration(seconds: 5),
    transparencyPerStep: 0.2,
  );

  bool overlayVisible = false;

  @override
  Future<void> showLoadingComponent() async {
    if (!overlays.isActive('loading')) {
      overlays.add('loading');
      return Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Future<void> hideLoadingComponent() async {
    if (overlays.isActive('loading')) {
      overlays.remove('loading');
      return Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  void onLoadingProgress<M>(LoadingProgressMessage<M> message) {
    messageProvidersManager
        .getMessageProvider<LoadingProgressMessage<M>>('loading_progress')
        .sendMessage(message);
    super.onLoadingProgress(message);
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final playerDisplacement = Vector2.zero();
    for (final key in keysPressed) {
      if (key == LogicalKeyboardKey.keyW) {
        playerDisplacement.setValues(0, -Player.stepSize);
      }
      if (key == LogicalKeyboardKey.keyA) {
        playerDisplacement.setValues(-Player.stepSize, 0);
      }
      if (key == LogicalKeyboardKey.keyS) {
        playerDisplacement.setValues(0, Player.stepSize);
      }
      if (key == LogicalKeyboardKey.keyD) {
        playerDisplacement.setValues(Player.stepSize, 0);
      }
      if (key == LogicalKeyboardKey.shiftLeft) {
        _killWater = !_killWater;
      }
      if (key == LogicalKeyboardKey.space) {
        _fireBullet = true;
      }
      if (key == LogicalKeyboardKey.keyG) {
        final collisionType = player.boundingBox.collisionType;
        if (collisionType == CollisionType.active) {
          player.boundingBox.collisionType = CollisionType.inactive;
        } else if (collisionType == CollisionType.inactive) {
          player.boundingBox.collisionType = CollisionType.active;
        }
      }

      if (key == LogicalKeyboardKey.keyM) {
        isSpatialGridDebugEnabled = !isSpatialGridDebugEnabled;
      }
      if (key == LogicalKeyboardKey.keyL) {
        trailsEnabled = !trailsEnabled;
      }
      if (key == LogicalKeyboardKey.keyR) {
        final raycast = world.children.query<PlayerRaycast>();
        if (raycast.isEmpty) {
          final raycastComponent = PlayerRaycast(player);
          world.add(raycastComponent);
        } else {
          raycast.first.removeFromParent();
        }
      }
      if (key == LogicalKeyboardKey.keyB) {
        _drawOutOfBoundsCounter = !_drawOutOfBoundsCounter;
        if (isSpatialGridDebugEnabled) {
          final debugComponent = rootComponent.children
              .query<SpatialGridDebugComponent>()
              .firstOrNull;
          debugComponent?.drawOutOfBoundsCounter = _drawOutOfBoundsCounter;
        }
      }
      if (key == LogicalKeyboardKey.keyT) {
        teleportMode = !teleportMode;
      }
      if (key == LogicalKeyboardKey.keyK) {
        for (final npc in world.npcList) {
          npc.removeFromParent();
        }
        world.npcList.clear();
      }
      if (key == LogicalKeyboardKey.keyC) {
        world.spawnNpcTeam(true, player.position.toOffset());
      }
      if (key == LogicalKeyboardKey.keyI) {
        isAIEnabled = !isAIEnabled;
        final npcList = world.children.whereType<Npc>();
        for (final npc in npcList) {
          npc.vector.setZero();
        }
      }
    }
    if (!playerDisplacement.isZero()) {
      player.move(playerDisplacement);
      if (_fireBullet) {
        final bullet = Bullet(
          position: player.position,
          displacement: playerDisplacement * 30,
          killWater: _killWater,
        );
        bullet.currentCell = player.currentCell;
        world.bullets.add(bullet);
        _fireBullet = false;
      }
    }

    return KeyEventResult.handled;
  }

  @override
  void onScroll(PointerScrollInfo info) {
    var zoom = camera.viewfinder.zoom;
    zoom += info.scrollDelta.global.y.sign * 0.08;
    camera.viewfinder.zoom = zoom.clamp(0.5, 8.0);
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    var zoom = camera.viewfinder.zoom;
    zoom += info.delta.global.y.sign * 0.08;
    camera.viewfinder.zoom = zoom.clamp(0.5, 8.0);
  }

  @override
  Future update(double dt) async {
    if (!kIsWeb && isRenderingSlow) {
      if (kDebugMode) {
        print('Rendering slow: $medianDt');
      }
    }
    // final sw = Stopwatch()..start();
    super.update(dt);
    // sw.stop();
    // print(sw.elapsedMicroseconds);
  }

  @override
  void onInitializationDone() {
    for (final npc in world.npcList) {
      npc.isAIEnabled = true;
    }
    // world.npcList.clear();
    hideLoadingComponent();
  }

  bool nomapFinished = false;

  Future<void> noMapCellBuilder(
    Cell cell,
    Component rootComponent,
    Iterable<Rect> mapRects,
  ) async {
    // return;

    if (mapRects.isNotEmpty || nomapFinished) {
      return;
    }
    // if (!nomapFinished) {
    //   nomapFinished = true;
    // }

    final brickTile = tilesetManager.getTile('tileset', 'Brick');
    final waterTile = tilesetManager.getTile('tileset', 'Water');
    if (brickTile == null || waterTile == null) {
      return;
    }
    final spriteBrick = brickTile.sprite;
    final waterAnimation = waterTile.spriteAnimation;

    final contextList = tileBuilderContextProvider.getContextListForCell(cell);
    if (contextList != null) {
      for (final context in contextList) {
        switch (context.tileDataProvider?.tile.type) {
          case 'Water':
            final water = Water(
              position: context.absolutePosition,
              animation: waterAnimation,
              ctx: context,
            );
            water.currentCell = context.cell;
            layersManager.addComponent(
              component: water,
              layerType: MapLayerType.animated,
              layerName: 'Water',
            );
            break;
          case 'Brick':
            final brick = Brick(
              position: context.absolutePosition,
              sprite: spriteBrick,
              ctx: context,
            );
            brick.currentCell = context.cell;
            layersManager.addComponent(
              component: brick,
              layerType: MapLayerType.static,
              layerName: 'Brick',
              renderMode: LayerRenderMode.component,
            );
            break;
          default:
            break;
        }
      }
    } else {
      for (var i = 0; i < 200; i++) {
        final random = Random();
        final diffX = random.nextInt((blockSize / 2 - 25).ceil()).toDouble() *
            (random.nextBool() ? -1 : 1);
        final diffY = random.nextInt((blockSize / 2 - 25).ceil()).toDouble() *
            (random.nextBool() ? -1 : 1);
        final position = (cell.rect.size / 2).toVector2()
          ..add(Vector2(diffX, diffY));
        final brick = Brick(position: position, sprite: spriteBrick);
        brick.currentCell = cell;
        brick.tileCache = brickTile;

        layersManager.addComponent(
          component: brick,
          layerType: MapLayerType.static,
          layerName: 'Brick',
          absolutePosition: false,
          renderMode: LayerRenderMode.image,
        );
      }

      for (var i = 0; i < 200; i++) {
        final random = Random();
        final diffX = random.nextInt((blockSize / 2 - 20).ceil()).toDouble() *
            (random.nextBool() ? -1 : 1);
        final diffY = random.nextInt((blockSize / 2 - 20).ceil()).toDouble() *
            (random.nextBool() ? -1 : 1);
        final position = (cell.rect.size / 2).toVector2()
          ..add(Vector2(diffX, diffY));
        final water = Water(
          position: position,
          animation: waterAnimation,
        );
        water.currentCell = cell;
        water.tileCache = waterTile;
        layersManager.addComponent(
          component: water,
          layerType: MapLayerType.animated,
          layerName: 'Water',
          absolutePosition: false,
        );
      }
    }
  }

  @override
  bool pureTypeCheck(Type activeItemType, Type potentialItemType) {
    if (activeItemType == Bullet) {
      if (potentialItemType == Bullet || potentialItemType == Player) {
        return false;
      }
    }
    return true;
  }
}

class MyWorld extends World with HasGameRef<SpatialGridExample> {
  static const mapSize = 50;

  final Player player = Player(
    position: Vector2(0, 0),
    size: Vector2.all(tileSize),
    priority: 10,
  );

  final bullets = Component();
  final actors = Component();

  int npcCount = 0;

  @override
  Future<void> onLoad() async {
    bullets.priority = 100;
    add(bullets);
    add(actors);
    spawnNpcTeam();
  }

  void spawnNpcTeam([bool aiEnabled = false, Offset offset = Offset.zero]) {
    // return;
    for (var i = 1; i <= 80; i++) {
      final x = i <= 40 ? 10.0 * i : 10.0 * (i - 40);
      final y = i <= 40 ? 0.0 : -20.0;
      final position = offset.toVector2()
        ..add(Vector2(-100, 0))
        ..add(Vector2(x, y));
      final npc = Npc(
        position: position,
        size: Vector2.all(tileSize),
        priority: player.priority,
      );
      npc.isAIEnabled = aiEnabled;
      actors.add(npc);
      npcList.add(npc);
      npcCount++;
    }
  }

  final npcList = <Npc>[];
}

class DemoMapLoader extends TiledMapLoader {
  DemoMapLoader([Vector2? initialPosition]) {
    if (initialPosition != null) {
      this.initialPosition = initialPosition;
    }
    preloadTileSets = true;
    fileName = 'example.tmx';
  }

  @override
  Vector2 get destTileSize => Vector2.all(8);

  @override
  TileBuilderFunction? get notFoundBuilder => onBackgroundBuilder;

  @override
  Map<String, TileBuilderFunction> get tileBuilders => {
        'Brick': onBuildBrick,
        'Water': onBuildWater,
        'TestObject': onBuildTestObject,
      };

  Future<void> onBuildBrick(TileBuilderContext context) async {
    final spriteBrick = getPreloadedTileData('tileset', 'Brick')?.sprite;
    final brick = Brick(
      position: context.absolutePosition,
      sprite: spriteBrick,
      ctx: context,
    );
    brick.currentCell = context.cell;
    game.layersManager.addComponent(
      component: brick,
      layerType: MapLayerType.static,
      layerName: 'Brick',
    );
  }

  Future<void> onBuildWater(TileBuilderContext context) async {
    final waterAnimation =
        getPreloadedTileData('tileset', 'Water')?.spriteAnimation;
    final water = Water(
      position: context.absolutePosition,
      animation: waterAnimation,
      ctx: context,
    );
    water.currentCell = context.cell;
    game.layersManager.addComponent(
      component: water,
      layerType: MapLayerType.animated,
      layerName: 'Water',
    );
  }

  Future<void> onBuildTestObject(TileBuilderContext context) async {
    final waterAnimation =
        getPreloadedTileData('tileset', 'Water')?.spriteAnimation;

    final stepSize = waterAnimation?.createTicker().getSprite().srcSize.x;
    if (stepSize == null) {
      return;
    }
    for (var y = context.absolutePosition.y;
        y < context.absolutePosition.y + context.size.y;
        y += stepSize) {
      for (var x = context.absolutePosition.x;
          x < context.absolutePosition.x + context.size.x;
          x += stepSize) {
        final water = Water(
          position: Vector2(x, y),
          animation: waterAnimation,
          ctx: context,
        );
        game.layersManager.addComponent(
          component: water,
          layerType: MapLayerType.animated,
          layerName: 'Water',
        );
      }
    }
  }

  Future<void> onBackgroundBuilder(TileBuilderContext context) async {
    var priority = -1;
    if (context.layerInfo.name == 'bricks') {
      priority = 100;
    }

    context.priorityOverride = priority;

    super.genericTileBuilder(context);
  }

  @override
  Map<String, TileBuilderFunction>? get globalObjectBuilder => null;

  @override
  Map<String, LayerBuilderFunction>? get layerBuilders => null;

  @override
  CellLayer customLayerBuilder(
    PositionComponent component,
    Cell cell,
    String layerName,
    LayerComponentsStorageMode componentsStorageMode,
  ) {
    throw UnimplementedError();
  }
}
//#endregion

//#region Player NPC

class Player extends SpriteComponent
    with
        CollisionCallbacks,
        HasGameRef<SpatialGridExample>,
        HasGridSupport,
        GameCollideable {
  Player({
    required super.position,
    required super.size,
    required super.priority,
  }) {
    Sprite.load(
      'retro_tiles.png',
      srcSize: Vector2.all(tileSize),
      srcPosition: Vector2(tileSize * 3, tileSize),
    ).then((value) {
      sprite = value;
    });
    boundingBox.collisionType =
        boundingBox.defaultCollisionType = CollisionType.active;
    boundingBox.doExtendedTypeCheck = false;
    // boundingBox.groupCollisionsTags
    //   ..add('Water')
    //   ..add('Brick');
  }

  @override
  BoundingHitboxFactory get boundingHitboxFactory => BoundingBoxGridGame.new;

  static const stepSize = 2.0;
  double stepDone = 0;
  final positionNoCollision = Vector2.zero();

  final vector = Vector2.zero();
  bool manuallyControlled = true;

  void move(Vector2 diff) {
    vector.setFrom(diff);
  }

  @override
  void update(double dt) {
    if (manuallyControlled && !vector.isZero()) {
      if (activeCollisions.isEmpty) {
        positionNoCollision.setFrom(position);
      }
      position.setFrom(position + vector);
      createTrail(3);
      vector.setZero();
    }
    super.update(dt);
  }

  void createTrail(int value) {
    if (!game.trailsEnabled) {
      return;
    }
    stepDone += vector.x.abs() / value + vector.y.abs() / value;
    if (stepDone >= stepSize) {
      stepDone = 0;
      final step = PlayerStep(this);
      final layer = game.layersManager.addComponent(
        component: step,
        currentCell: currentCell,
        layerType: MapLayerType.trail,
        layerName: 'trail',
        optimizeCollisions: false,
      );

      if (layer is CellTrailLayer) {
        layer.fadeOutConfig = game.fadeOutConfig;
      }
    }
  }

  bool canMoveLeft = true;
  bool canMoveRight = true;
  bool canMoveTop = true;
  bool canMoveBottom = true;

  @override
  void onCollision(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    final myCenter = boundingBox.aabbCenter;
    if (other is GameCollideable || other is CellLayer) {
      if (game.player == this) {
        position.setFrom(positionNoCollision);
        game.camera.updateTree(0.01);
      } else if (other is GameCollideable) {
        final diffX = myCenter.x - other.boundingBox.aabbCenter.x;
        if (diffX < 0) {
          canMoveRight = false;
        } else if (diffX > 0) {
          canMoveLeft = false;
        }

        final diffY = myCenter.y - other.boundingBox.aabbCenter.y;
        if (diffY < 0) {
          canMoveBottom = false;
        } else if (diffY > 0) {
          canMoveTop = false;
        }
        final newPos = Vector2(position.x + diffX / 3, position.y + diffY / 3);
        position.setFrom(newPos);
      } else {
        final vector = positionNoCollision - position;
        position.setFrom(positionNoCollision);
        positionNoCollision.add(vector);
      }
    }
    super.onCollision(intersectionPoints, other);
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    canMoveLeft = true;
    canMoveRight = true;
    canMoveTop = true;
    canMoveBottom = true;
    super.onCollisionEnd(other);
  }
}

class PlayerRaycast extends Component
    with HasGameReference<SpatialGridExample> {
  PlayerRaycast(this.player) {
    origin.setFrom(player.position.translated(4, 4));
    priority = 1000;
  }

  final Player player;
  final origin = Vector2(0, 0);
  Paint rayPaint = Paint();

  final _colorTween = ColorTween(
    begin: Colors.blue.withOpacity(0.8),
    end: Colors.red.withOpacity(0.8),
  );

  var _timePassed = 0.0;
  static const numberOfRays = 50;
  final List<RaycastResult<ShapeHitbox>> results = [];

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    renderResult(canvas, origin, results, rayPaint);
  }

  void renderResult(
    Canvas canvas,
    Vector2 origin,
    List<RaycastResult<ShapeHitbox>> results,
    Paint paint,
  ) {
    final originOffset = origin.toOffset();
    for (final result in results) {
      if (!result.isActive) {
        continue;
      }
      final intersectionPoint = result.intersectionPoint!.toOffset();
      canvas.drawLine(
        originOffset,
        intersectionPoint,
        paint,
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (origin != player.position || results.isEmpty) {
      origin.setFrom(player.position.translated(4, 4));
      game.collisionDetection.raycastAll(
        origin,
        numberOfRays: numberOfRays,
        out: results,
        ignoreHitboxes: [player.boundingBox],
      );
    }

    _timePassed += dt;
    rayPaint.color = _colorTween.transform(0.5 + (sin(_timePassed) / 2))!;
  }
}

class PlayerStep extends PositionComponent with HasPaint {
  PlayerStep(Player player) {
    paint.color = Colors.white38;
    paint.strokeWidth = 1;
    paint.isAntiAlias = false;
    final playerCell = player.currentCell;
    if (playerCell != null) {
      position = player.position + Vector2(0, 8);
      size = Vector2(8, 2);
      // currentCell = playerCell;
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawPoints(
      PointMode.points,
      [const Offset(1.5, 1), const Offset(6.5, 0)],
      paint,
    );
  }
}

class Npc extends Player with DebuggerPause {
  Npc({required super.position, required super.size, required super.priority}) {
    final matrix = [
      -0.5,
      0.000,
      0.000,
      0.000,
      0.000,
      0.8,
      1.000,
      0.000,
      0.000,
      0.000,
      -0.5,
      0.000,
      1.000,
      0.000,
      0.000,
      0.000,
      0.000,
      0.000,
      1.000,
      0.000,
    ];
    manuallyControlled = false;
    paint.colorFilter = ColorFilter.matrix(matrix);
    boundingBox.groupCollisionsTags
      ..add('Brick')
      ..add('Water');
    boundingBox.parentSpeedGetter = () => _lastDtSpeed;
  }

  final speed = 20;

  double dtElapsed = 0;
  final dtMax = 1000;
  bool isAIEnabled = false;

  double _lastDtSpeed = 0;

  @override
  void update(double dt) {
    dtElapsed++;
    if (activeCollisions.isEmpty) {
      positionNoCollision.setFrom(position);
    }
    if (dtElapsed >= dtMax) {
      vector.setZero();
      dtElapsed = 0;
    }
    if (vector.isZero()) {
      _createNewVector();
    }

    final dtSpeed = speed * dt;
    final newStep = vector * dtSpeed;
    final longest = max(newStep.x, newStep.y);
    if (_lastDtSpeed - longest > 0.5) {
      boundingBox.onParentSpeedChange();
    }
    _lastDtSpeed = longest;

    if (!vector.isZero()) {
      position.add(newStep);
      createTrail(6);
    }
    super.update(dt);
  }

  void _createNewVector() {
    if (game.isAIEnabled && isAIEnabled) {
      final rand = Random();
      final xSign = rand.nextBool() ? -1 : 1;
      final ySign = rand.nextBool() ? -1 : 1;
      final xValue = rand.nextDouble();
      final yValue = rand.nextDouble();
      vector.setValues(xValue * xSign, yValue * ySign);
      if (vector.x.abs() < 0.05 && vector.y.abs() < 0.05) {
        boundingBox.collisionCheckFrequency = 5;
      } else if (vector.x.abs() < 0.2 && vector.y.abs() < 0.2) {
        boundingBox.collisionCheckFrequency = 3;
      } else {
        boundingBox.collisionCheckFrequency = 1.5;
      }
    }
  }

  @override
  void onCollision(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    if (isRemoving) {
      return;
    }
    if (other is GameCollideable || other is CellLayer) {
      vector.setValues(0, 0);
    } else if (other is Bullet) {
      removeFromParent();
      game.world.npcCount--;
      if (game.world.npcCount == 0) {
        game.world.spawnNpcTeam();
      }
    }
    super.onCollision(intersectionPoints, other);
  }

  static Image? coloredSprite;

  @override
  // ignore: must_call_super
  Future<void> render(Canvas canvas) async {
    _createColoredSprite();
    canvas.drawImage(coloredSprite!, Offset.zero, paint);
  }

  void _createColoredSprite() {
    if (coloredSprite != null) {
      return;
    }
    final recorder = PictureRecorder();
    final recorderCanvas = Canvas(recorder);
    recorderCanvas.saveLayer(null, paint);
    super.render(recorderCanvas);
    final picture = recorder.endRecording();
    coloredSprite = picture.toImageSync(8, 8);
    picture.dispose();
  }

  @override
  void onRemove() {
    game.world.npcList.remove(this);
    super.onRemove();
  }
}

class Bullet extends PositionComponent
    with CollisionCallbacks, HasPaint, HasGridSupport {
  Bullet({
    required super.position,
    required this.displacement,
    this.killWater = false,
  }) {
    paint.color = Colors.deepOrange;
    priority = 10;
    size = Vector2.all(1);
    boundingBox.doExtendedTypeCheck = false;
    boundingBox.collisionType =
        boundingBox.defaultCollisionType = CollisionType.active;
  }

  @override
  BoundingHitboxFactory get boundingHitboxFactory => BoundingBoxGridGame.new;

  double lifetime = 20.0;
  final Vector2 displacement;
  final bool killWater;

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset.zero, 1, paint);
  }

  @override
  void update(double dt) {
    lifetime -= dt;
    if (lifetime <= 0) {
      removeFromParent();
    } else {
      final d = displacement * dt;
      position = Vector2(position.x + d.x, position.y + d.y);
    }
    super.update(dt);
  }

  @override
  void onResume(double dtElapsedWhileSuspended) {
    lifetime -= dtElapsedWhileSuspended;
    if (kDebugMode) {
      print('resumed! $dtElapsedWhileSuspended');
    }
    if (lifetime <= 0) {
      removeFromParent();
    } else {
      final d = displacement * dtElapsedWhileSuspended;
      position = Vector2(position.x + d.x, position.y + d.y);
    }
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    if (other is Water && killWater) {
      removeFromParent();
      super.onCollisionStart(intersectionPoints, other);
    } else if (other is! Water) {
      removeFromParent();
      super.onCollisionStart(intersectionPoints, other);
    }
  }
}

//#endregion

//#region Environment

class Brick extends SpriteComponent
    with
        CollisionCallbacks,
        HasGridSupport,
        GameCollideable,
        UpdateOnDemand,
        RestorableStateMixin<void> {
  Brick({
    required super.position,
    required super.sprite,
    TileBuilderContext? ctx,
  }) {
    size = Vector2.all(tileSize);
    paint.isAntiAlias = false;
    paint.filterQuality = FilterQuality.none;
    priority = 2;
    initCollision();
    if (ctx != null) {
      context = ctx;
    }
  }

  @override
  BoundingHitboxFactory get boundingHitboxFactory => BoundingBoxGridGame.new;

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    if (other is Bullet) {
      context?.remove();
      removeFromParent();
    }
    super.onCollisionStart(intersectionPoints, other);
  }

  @override
  void get userData => null;
}

class Water extends SpriteAnimationComponent
    with
        CollisionCallbacks,
        HasGridSupport,
        GameCollideable,
        UpdateOnDemand,
        RestorableStateMixin<void> {
  Water({
    required super.position,
    required super.animation,
    TileBuilderContext? ctx,
  }) {
    size = Vector2.all(tileSize);
    paint.isAntiAlias = false;
    paint.filterQuality = FilterQuality.none;
    priority = 0;
    initCollision();

    if (ctx != null) {
      context = ctx;
    }
  }

  @override
  BoundingHitboxFactory get boundingHitboxFactory => BoundingBoxGridGame.new;

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    if (other is Bullet && other.killWater) {
      context?.remove();
      removeFromParent();
      super.onCollisionStart(intersectionPoints, other);
    }
  }

  @override
  void get userData => null;
}

mixin GameCollideable on HasGridSupport {
  void initCollision() {
    boundingBox.collisionType =
        boundingBox.defaultCollisionType = CollisionType.passive;
    boundingBox.isSolid = true;
  }

  Vector2 get cachedCenter => boundingBox.aabbCenter;
}

class SpatialGridDebugCameraWrapper extends SpatialGridCameraWrapper {
  SpatialGridDebugCameraWrapper(super.cameraComponent);

  @override
  void onAfterZoom() {
    try {
      if (!game.isSpatialGridDebugEnabled) {
        game.onAfterZoom();
      }
      // ignore: avoid_catches_without_on_clauses, empty_catches
    } catch (e) {}
  }
}

class BoundingBoxGridGame extends BoundingHitbox {
  @override
  FutureOr<void> onLoad() {
    doExtendedTypeCheck = false;
    cacheAbsoluteScaledSize = cacheAbsoluteAngle =
        groupAbsoluteCacheByType = fastCollisionForRects = true;
    return super.onLoad();
  }
}

class TouchEventsHandler extends Component
    with TapCallbacks, HasGameReference<SpatialGridExample> {
  @override
  bool containsLocalPoint(Vector2 point) => true;

  @override
  void onTapDown(TapDownEvent event) {
    if (game.teleportMode) {
      game.player.position.setFrom(event.localPosition);
    }
    if (event.deviceKind == PointerDeviceKind.mouse) {}
    event.continuePropagation = false;
    return;
    final tapPosition = event.localPosition;
    // final cellsUnderCursor = <Cell>[];
    // gameRef.spatialGrid.cells.forEach((rect, cell) {
    //   if (cell.rect.containsPoint(tapPosition)) {
    //     cellsUnderCursor.add(cell);
    //     if (kDebugMode) {
    //       print(cell.outOfBoundsCounter);
    //     }
    //     // print('State:  + ${cell.state}');
    //     if (kDebugMode) {
    //       print('Rect: $rect');
    //     }
    //
    //     // print('Components count: ${cell.components.length}');
    //   }
    // });

    // if (kDebugMode) {
    //   print('========================================');
    // }
    final list = componentsAtPoint(tapPosition).toList(growable: false);
    for (final component in list) {
      if (component is! HasGridSupport) {
        continue;
      }
      if (component is CellStaticLayer) {
        if (kDebugMode) {
          print('123');
        }
      }
      //
      // final optimized = game.collisionDetection.broadphase
      //     .optimizedCollisionsByGroupBox[component.currentCell];
      // print(optimized?.length);
      // print(component.runtimeType);
    }
  }
}
//#endregion
