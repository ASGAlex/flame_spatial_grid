import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame_message_stream/flame_message_stream.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image, Draggable;
import 'package:flutter/services.dart';

//#region World

const tileSize = 8.0;
const blockSize = 100.0;

class SpatialGridExample extends FlameGame
    with
        HasSpatialGridFramework,
        KeyboardEvents,
        ScrollDetector,
        ScaleDetector,
        HasMessageProviders {
  SpatialGridExample() {
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
    super.onLoad();

    player = world.player;
    cameraComponent = CameraComponent(world: world);
    cameraComponent.viewfinder.zoom = 5;
    cameraComponent.follow(player, maxSpeed: 200, snap: true);

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
      processCellsLimitToPauseEngine = 150;
      buildCellsPerUpdate = 2;
      cleanupCellsPerUpdate = 2;
    }
    await initializeSpatialGrid(
      debug: false,
      unloadRadius: unloadRadius,
      preloadRadius: preloadRadius,
      processCellsLimitToPauseEngine: processCellsLimitToPauseEngine,
      collisionOptimizerDefaultGroupLimit: 50,
      blockSize: blockSize,
      trackedComponent: SpatialGridDebugCameraWrapper(cameraComponent),
      initialPositionChecker: (layer, object, mapOffset, worldName) {
        if (worldName == null) {
          return null;
        }
        if (object.name == 'spawn_player') {
          cameraComponent.viewfinder.position =
              player.position = mapOffset + Vector2(object.x, object.y);

          return player.position;
        }
        return null;
      },
      rootComponent: world,
      buildCellsPerUpdate: buildCellsPerUpdate,
      cleanupCellsPerUpdate: cleanupCellsPerUpdate,
      suspendedCellLifetime: const Duration(minutes: 10),
      cellBuilderNoMap: noMapCellBuilder,
      maps: [
        DemoMapLoader(Vector2(600, 0)),
      ],
      worldLoader: WorldLoader(
        fileName: 'example.world',
        mapLoader: {'example': DemoMapLoader(), 'another_map': DemoMapLoader()},
      ),
    );
    // await demoMapLoader.init(this);

    add(world);
    layersManager.layersRootComponent.add(player);
    add(FpsTextComponent());
  }

  final elapsedMicroseconds = <double>[];

  late final CameraComponent cameraComponent;
  MyWorld world = MyWorld();

  late Player player;
  var _fireBullet = false;
  var _killWater = false;

  bool teleportMode = true;
  bool trailsEnabled = true;
  bool isAIEnabled = true;

  final fadeOutConfig = FadeOutConfig(
    fadeOutTimeout: const Duration(seconds: 1),
    transparencyPerStep: 0.1,
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
    RawKeyEvent event,
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
        removeUnusedCells(forceCleanup: true);
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
        world.spawnNpcTeam(true);
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
    var zoom = cameraComponent.viewfinder.zoom;
    zoom += info.scrollDelta.game.y.sign * 0.08;
    cameraComponent.viewfinder.zoom = zoom.clamp(0.5, 8.0);
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    var zoom = cameraComponent.viewfinder.zoom;
    zoom += info.delta.game.y.sign * 0.08;
    cameraComponent.viewfinder.zoom = zoom.clamp(0.5, 8.0);
  }

  @override
  Future update(double dt) async {
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

  Future<void> noMapCellBuilder(
    Cell cell,
    Component rootComponent,
    bool isFullyOutside,
  ) async {
    return;
    if (!isFullyOutside) {
      return;
    }
    final spriteBrick = tilesetManager.getTile('tileset', 'Brick')?.sprite;
    final waterAnimation =
        tilesetManager.getTile('tileset', 'Water')?.spriteAnimation;

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

      final layer = layersManager.addComponent(
        component: brick,
        layerType: MapLayerType.static,
        layerName: 'Brick',
        absolutePosition: false,
        priority: 2,
      );
      (layer as CellStaticLayer).renderAsImage = true;
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
      layersManager.addComponent(
        component: water,
        layerType: MapLayerType.animated,
        layerName: 'Water',
        absolutePosition: false,
      );
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

class MyWorld extends World with TapCallbacks, HasGameRef<SpatialGridExample> {
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

  void spawnNpcTeam([bool aiEnabled = false]) {
    // return;
    for (var i = 1; i <= 80; i++) {
      final x = i <= 40 ? 10.0 * i : 10.0 * (i - 40);
      final y = i <= 40 ? 0.0 : -20.0;
      final position = Vector2(-100, 0)..add(Vector2(x, y));
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

  @override
  void onTapDown(TapDownEvent event) {
    final tapPosition = event.localPosition;
    final cellsUnderCursor = <Cell>[];
    gameRef.spatialGrid.cells.forEach((rect, cell) {
      if (cell.rect.containsPoint(tapPosition)) {
        cellsUnderCursor.add(cell);
        print(cell.outOfBoundsCounter);
        // print('State:  + ${cell.state}');
        print('Rect: $rect');

        // print('Components count: ${cell.components.length}');
      }
    });

    print('========================================');
    final list = componentsAtPoint(tapPosition).toList(growable: false);
    for (final component in list) {
      if (component is! HasGridSupport) {
        continue;
      }
      // if (component is CellStaticLayer) {
      //   component.collisionOptimizer.optimize();
      // }
      //
      // final optimized = game.collisionDetection.broadphase
      //     .optimizedCollisionsByGroupBox[component.currentCell];
      // print(optimized?.length);
      // print(component.runtimeType);
    }

    if (game.teleportMode) {
      player.position = event.localPosition;
    }
  }
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
        'TestObject': onBuildTestObject
      };

  Future<void> onBuildBrick(CellBuilderContext context) async {
    final spriteBrick = getPreloadedTileData('tileset', 'Brick')?.sprite;
    final brick = Brick(
      position: context.absolutePosition,
      sprite: spriteBrick,
      context: context,
    );
    brick.currentCell = context.cell;
    brick.priority = 2;
    game.layersManager.addComponent(
      component: brick,
      layerType: MapLayerType.static,
      layerName: 'Brick',
      optimizeGraphics: false,
      priority: 2,
    );
  }

  Future<void> onBuildWater(CellBuilderContext context) async {
    final waterAnimation =
        getPreloadedTileData('tileset', 'Water')?.spriteAnimation;
    final water = Water(
      position: context.absolutePosition,
      animation: waterAnimation,
      context: context,
    );
    water.currentCell = context.cell;
    game.layersManager.addComponent(
      component: water,
      layerType: MapLayerType.animated,
      layerName: 'Water',
    );
  }

  Future<void> onBuildTestObject(CellBuilderContext context) async {
    final waterAnimation =
        getPreloadedTileData('tileset', 'Water')?.spriteAnimation;

    final stepSize = waterAnimation?.ticker().getSprite().srcSize.x;
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
          context: context,
        );
        game.layersManager.addComponent(
          component: water,
          layerType: MapLayerType.animated,
          layerName: 'Water',
        );
      }
    }
  }

  Future<void> onBackgroundBuilder(CellBuilderContext context) async {
    var priority = -1;
    if (context.layerInfo.name == 'bricks') {
      priority = 100;
    }

    context.priorityOverride = priority;

    super.genericTileBuilder(context);
  }

  @override
  Map<String, TileBuilderFunction>? get globalObjectBuilder => null;
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
    // boundingBox.groupCollisionsTags
    //   ..add('Water')
    //   ..add('Brick');
  }

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
      if (other is GameCollideable) {
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
      0.000
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

    final dtSpeed = _lastDtSpeed = speed * dt;
    final newStep = vector * dtSpeed;
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
        boundingBox.collisionCheckFrequency = 0.8;
      } else if (vector.x.abs() < 0.2 && vector.y.abs() < 0.2) {
        boundingBox.collisionCheckFrequency = 0.5;
      } else {
        boundingBox.collisionCheckFrequency = 0.2;
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
    boundingBox.collisionType =
        boundingBox.defaultCollisionType = CollisionType.active;
  }

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
    with CollisionCallbacks, HasGridSupport, GameCollideable, UpdateOnDemand {
  Brick({required super.position, required super.sprite, this.context}) {
    size = Vector2.all(tileSize);
    paint.isAntiAlias = false;
    paint.filterQuality = FilterQuality.none;
    initCollision();
  }

  final CellBuilderContext? context;

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    if (other is Bullet) {
      context?.remove = true;
      removeFromParent();
    }
    super.onCollisionStart(intersectionPoints, other);
  }
}

class Water extends SpriteAnimationComponent
    with CollisionCallbacks, HasGridSupport, GameCollideable, UpdateOnDemand {
  Water({required super.position, required super.animation, this.context}) {
    size = Vector2.all(tileSize);
    paint.isAntiAlias = false;
    paint.filterQuality = FilterQuality.none;
    initCollision();
  }

  final CellBuilderContext? context;

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    if (other is Bullet && other.killWater) {
      context?.remove = true;
      removeFromParent();
      super.onCollisionStart(intersectionPoints, other);
    }
  }
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

//#endregion
