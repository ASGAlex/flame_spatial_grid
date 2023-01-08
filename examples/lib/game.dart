import 'dart:math';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/material.dart' hide Image, Draggable;
import 'package:flutter/services.dart';

//#region World

const tileSize = 8.0;

class SpatialGridExample extends FlameGame
    with
        HasSpatialGridFramework,
        KeyboardEvents,
        ScrollDetector,
        ScaleDetector,
        HasTappableComponents {
  SpatialGridExample();

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

  @override
  Future<void> onLoad() async {
    super.onLoad();

    player = world.player;
    const blockSize = 100.0;
    await initializeSpatialGrid(
        debug: false,
        activeRadius: const Size(3, 2),
        unloadRadius: const Size(5, 5),
        blockSize: blockSize,
        trackedComponent: player,
        rootComponent: world,
        buildCellsPerUpdate: 1,
        removeCellsPerUpdate: 0.25,
        suspendedCellLifetime: const Duration(minutes: 1),
        cellBuilderNoMap: noMapCellBuilder,
        onAfterCellBuild: world.onAfterCellBuild,
        maps: [
          DemoMapLoader(Vector2(600, 0)),
        ],
        worldLoader: WorldLoader(fileName: 'example.world', mapLoader: {
          'example': DemoMapLoader(),
          'another_map': DemoMapLoader()
        }));
    // await demoMapLoader.init(this);
    cameraComponent = CameraComponent(world: world);
    cameraComponent.viewfinder.zoom = 5;
    add(world);
    add(cameraComponent);
    cameraComponent.follow(player);

    add(FpsTextComponent());
    gameInitializationDone();
  }

  final elapsedMicroseconds = <double>[];

  late final CameraComponent cameraComponent;
  MyWorld world = MyWorld();

  late Player player;
  final _playerDisplacement = Vector2.zero();
  var _fireBullet = false;
  var _killWater = false;

  var teleportMode = true;
  var isAIEnabled = true;

  final fadeOutConfig = FadeOutConfig(
      fadeOutTimeout: const Duration(seconds: 1),
      operationsLimitToSavePicture: 5,
      transparencyPerStep: 0.1);

  @override
  KeyEventResult onKeyEvent(
    RawKeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    for (final key in keysPressed) {
      if (key == LogicalKeyboardKey.keyW && player.canMoveTop) {
        _playerDisplacement.setValues(0, -Player.stepSize);
        player.position = player.position.translate(0, -Player.stepSize);
      }
      if (key == LogicalKeyboardKey.keyA && player.canMoveLeft) {
        _playerDisplacement.setValues(-Player.stepSize, 0);
        player.position = player.position.translate(-Player.stepSize, 0);
      }
      if (key == LogicalKeyboardKey.keyS && player.canMoveBottom) {
        _playerDisplacement.setValues(0, Player.stepSize);
        player.position = player.position.translate(0, Player.stepSize);
      }
      if (key == LogicalKeyboardKey.keyD && player.canMoveRight) {
        _playerDisplacement.setValues(Player.stepSize, 0);
        player.position = player.position.translate(Player.stepSize, 0);
      }
      if (key == LogicalKeyboardKey.shiftLeft) {
        _killWater = !_killWater;
      }
      if (key == LogicalKeyboardKey.space) {
        _fireBullet = true;
      }
      if (key == LogicalKeyboardKey.keyC) {
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
      if (key == LogicalKeyboardKey.keyR) {
        removeUnusedCells();
      }
      if (key == LogicalKeyboardKey.keyT) {
        teleportMode = !teleportMode;
      }
      if (key == LogicalKeyboardKey.keyI) {
        isAIEnabled = !isAIEnabled;
        final npcList = world.children.whereType<Npc>();
        for (final npc in npcList) {
          npc.vector.setZero();
        }
      }
    }
    if (!_playerDisplacement.isZero()) {
      if (_fireBullet) {
        final bullet = Bullet(
            position: player.position,
            displacement: _playerDisplacement * 30,
            killWater: _killWater);
        bullet.currentCell = player.currentCell;
        world.bullets.add(bullet);
        _fireBullet = false;
      }
      _playerDisplacement.setZero();
    }

    return KeyEventResult.handled;
  }

  @override
  void onScroll(PointerScrollInfo info) {
    var zoom = cameraComponent.viewfinder.zoom;
    zoom += info.scrollDelta.game.y.sign * 0.08;
    cameraComponent.viewfinder.zoom = zoom.clamp(0.8, 8.0);
    if (!isSpatialGridDebugEnabled) {
      onAfterZoom();
    }
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    var zoom = cameraComponent.viewfinder.zoom;
    zoom += info.delta.game.y.sign * 0.08;
    cameraComponent.viewfinder.zoom = zoom.clamp(0.8, 8.0);
    if (!isSpatialGridDebugEnabled) {
      onAfterZoom();
    }
  }

  @override
  Future update(double dt) async {
    // final sw = Stopwatch()..start();
    super.update(dt);
    // sw.stop();
    // print(sw.elapsedMicroseconds);
  }

  Future<void> noMapCellBuilder(Cell cell, Component rootComponent) async {
    // return;
    final map = TiledMapLoader.loadedMaps.whereType<DemoMapLoader>().first;

    final spriteBrick = map.getPreloadedTileData('tileset', 'Brick')?.sprite;
    final waterAnimation =
        map.getPreloadedTileData('tileset', 'Water')?.spriteAnimation;

    for (var i = 0; i < 200; i++) {
      final random = Random();
      final diffX = random.nextInt((map.blockSize / 2 - 25).ceil()).toDouble() *
          (random.nextBool() ? -1 : 1);
      final diffY = random.nextInt((map.blockSize / 2 - 25).ceil()).toDouble() *
          (random.nextBool() ? -1 : 1);
      final position = (cell.rect.size / 2).toVector2().translate(diffX, diffY);
      final brick = Brick(position: position, sprite: spriteBrick);
      brick.currentCell = cell;

      layersManager.addComponent(
          component: brick,
          layerType: MapLayerType.static,
          layerName: 'Brick',
          absolutePosition: false,
          priority: 2);
    }

    for (var i = 0; i < 200; i++) {
      final random = Random();
      final diffX = random.nextInt((map.blockSize / 2 - 20).ceil()).toDouble() *
          (random.nextBool() ? -1 : 1);
      final diffY = random.nextInt((map.blockSize / 2 - 20).ceil()).toDouble() *
          (random.nextBool() ? -1 : 1);
      final position = (cell.rect.size / 2).toVector2().translate(diffX, diffY);
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
          priority: 1);
    }
  }
}

class MyWorld extends World with TapCallbacks, HasGameRef<SpatialGridExample> {
  static const mapSize = 50;

  final Player player = Player(
      position: Vector2(-100, 0), size: Vector2.all(tileSize), priority: 10);

  final bullets = Component();

  var npcCount = 0;

  @override
  onLoad() async {
    add(player);
    add(bullets);
    spawnNpcTeam();
  }

  void spawnNpcTeam() {
    for (var i = 1; i <= 80; i++) {
      final double x = i <= 40 ? 10.0 * i : 10.0 * (i - 40);
      final double y = i <= 40 ? 0 : -20;
      final position = Vector2(-100, 0)..add(Vector2(x, y));
      final cell = game.spatialGrid.findExistingCellByPosition(position) ??
          game.spatialGrid.createNewCellAtPosition(position);
      final enableAI = cell.isCellBuildFinished;
      add(Npc(
          position: position,
          size: Vector2.all(tileSize),
          priority: player.priority)
        ..currentCell = cell
        ..isAIEnabled = enableAI);
      npcCount++;
    }
  }

  Future<void> onAfterCellBuild(Cell cell, Component rootComponent) async {
    final npcList = cell.components.whereType<Npc>();
    Future.delayed(const Duration(seconds: 3)).then((value) {
      for (final npc in npcList) {
        npc.isAIEnabled = true;
      }
    });
  }

  @override
  void onTapDown(TapDownEvent event) {
    final tapPosition = event.localPosition;
    final cellsUnderCursor = <Cell>[];
    gameRef.spatialGrid.cells.forEach((rect, cell) {
      if (cell.rect.containsPoint(tapPosition)) {
        cellsUnderCursor.add(cell);
        print('State:  + ${cell.state}');
        print('Rect: $rect');
        // print('Components count: ${cell.components.length}');
      }
    });

    final list = componentsAtPoint(tapPosition).toList(growable: false);
    for (final component in list) {
      if (component is! HasGridSupport) continue;
      print(component.runtimeType);
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
  TileBuilderFunction? get cellPostBuilder => null;

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
        position: context.position, sprite: spriteBrick, context: context);
    brick.currentCell = context.cell;
    game.layersManager.addComponent(
        component: brick,
        layerType: MapLayerType.static,
        layerName: 'Brick',
        priority: 2);
  }

  Future<void> onBuildWater(CellBuilderContext context) async {
    final waterAnimation =
        getPreloadedTileData('tileset', 'Water')?.spriteAnimation;
    final water = Water(
        position: context.position,
        animation: waterAnimation,
        context: context);
    water.currentCell = context.cell;
    game.layersManager.addComponent(
        component: water,
        layerType: MapLayerType.animated,
        layerName: 'Water',
        priority: 1);
  }

  Future<void> onBuildTestObject(CellBuilderContext context) async {
    final waterAnimation =
        getPreloadedTileData('tileset', 'Water')?.spriteAnimation;

    final stepSize = waterAnimation?.getSprite().srcSize.x;
    if (stepSize == null) return;
    for (var y = context.position.y;
        y < context.position.y + context.size.y;
        y += stepSize) {
      for (var x = context.position.x;
          x < context.position.x + context.size.x;
          x += stepSize) {
        final water = Water(
            position: Vector2(x, y),
            animation: waterAnimation,
            context: context);
        game.layersManager.addComponent(
            component: water,
            layerType: MapLayerType.animated,
            layerName: 'Water',
            priority: 1);
      }
    }
  }

  final blockSize = 100.0;

  Future<void> onBackgroundBuilder(CellBuilderContext context) async {
    var priority = -1;
    if (context.layerInfo.name == 'bricks') {
      priority = 100;
    }

    context.priorityOverride = priority;

    super.genericTileBuilder(context);
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
    previousPosition.setFrom(position);
    position.addListener(_onPositionUpdate);
  }

  static const stepSize = 2.0;
  double stepDone = 0;
  final previousPosition = Vector2.zero();

  _onPositionUpdate() {
    final diff = position - previousPosition;
    stepDone += diff.x.abs() / 3 + diff.y.abs() / 3;
    if (stepDone >= stepSize) {
      stepDone = 0;
      final step = PlayerStep(this);
      final stepCell = step.currentCell;
      if (stepCell != null) {
        final layer = game.layersManager.addComponent(
            component: step,
            layerType: MapLayerType.trail,
            layerName: 'trail',
            optimizeCollisions: false) as CellTrailLayer;
        layer.fadeOutConfig = game.fadeOutConfig;
      }
    }

    previousPosition.setFrom(position);
  }

  bool canMoveLeft = true;
  bool canMoveRight = true;
  bool canMoveTop = true;
  bool canMoveBottom = true;

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    final myCenter = boundingBox.aabbCenter;
    if (other is GameCollideable) {
      final diffX = myCenter.x - other.cachedCenter.x;
      if (diffX < 0) {
        canMoveRight = false;
      } else if (diffX > 0) {
        canMoveLeft = false;
      }

      final diffY = myCenter.y - other.cachedCenter.y;
      if (diffY < 0) {
        canMoveBottom = false;
      } else if (diffY > 0) {
        canMoveTop = false;
      }
      final newPos = Vector2(position.x + diffX / 3, position.y + diffY / 3);
      position = newPos;
    }
    super.onCollisionStart(intersectionPoints, other);
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

class PlayerStep extends PositionComponent with HasGridSupport, HasPaint {
  PlayerStep(Player player) {
    paint.color = Colors.white38;
    paint.strokeWidth = 1;
    paint.isAntiAlias = false;
    final playerCell = player.currentCell;
    if (playerCell != null) {
      position = player.position;
      size = player.size;
      currentCell = playerCell;
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawPoints(PointMode.points,
        [Offset(1.5, size.y - 1), Offset(6.5, size.y)], paint);
  }
}

class Npc extends Player {
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
    paint.colorFilter = ColorFilter.matrix(matrix);
  }

  final speed = 8;
  final vector = Vector2.zero();
  double dtElapsed = 0;
  final dtMax = 1000;
  bool isAIEnabled = false;

  @override
  void update(double dt) {
    dtElapsed++;
    if (dtElapsed >= dtMax) {
      vector.setZero();
      dtElapsed = 0;
    }
    if (vector.isZero()) {
      _createNewVector();
    }

    final dtSpeed = speed * dt;
    final newStep = vector * dtSpeed;
    if (!vector.isZero()) {
      position.add(newStep);
    }
    super.update(dt);
  }

  _createNewVector() {
    if (game.isAIEnabled && isAIEnabled) {
      final rand = Random();
      final xSign = rand.nextBool() ? -1 : 1;
      final ySign = rand.nextBool() ? -1 : 1;
      final xValue = rand.nextDouble();
      final yValue = rand.nextDouble();
      vector.setValues(xValue * xSign, yValue * ySign);
    }
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    if (isRemoving) return;
    if (other is GameCollideable) {
      vector.setValues(0, 0);
    } else if (other is Bullet) {
      removeFromParent();
      game.world.npcCount--;
      if (game.world.npcCount == 0) {
        game.world.spawnNpcTeam();
      }
    }
    super.onCollisionStart(intersectionPoints, other);
  }

  Image? coloredSprite;

  @override
  void render(Canvas canvas) async {
    if (coloredSprite == null) {
      final recorder = PictureRecorder();
      final recorderCanvas = Canvas(recorder);
      recorderCanvas.saveLayer(null, paint);
      super.render(recorderCanvas);
      coloredSprite = await recorder.endRecording().toImageSafe(8, 8);
    } else {
      canvas.drawImage(coloredSprite!, Offset.zero, paint);
    }
  }
}

class Bullet extends PositionComponent
    with CollisionCallbacks, HasPaint, HasGridSupport {
  Bullet(
      {required super.position,
      required this.displacement,
      this.killWater = false}) {
    paint.color = Colors.deepOrange;
    priority = 10;
    size = Vector2.all(1);
    boundingBox.collisionType =
        boundingBox.defaultCollisionType = CollisionType.active;
  }

  var lifetime = 20.0;
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
  bool onComponentTypeCheck(PositionComponent other) {
    if ((other is Player && other is! Npc) || other is Bullet) {
      return false;
    }
    return super.onComponentTypeCheck(other);
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
    initCollision();
  }

  final CellBuilderContext? context;

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
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
    initCollision();
  }

  final CellBuilderContext? context;

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
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

//#endregion

//#region Utils

extension Vector2Ext on Vector2 {
  Vector2 translate(double x, double y) {
    return Vector2(this.x + x, this.y + y);
  }
}

//#endregion
