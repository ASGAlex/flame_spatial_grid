import 'dart:collection';
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';
import 'package:flutter/material.dart' hide Image, Draggable;
import 'package:flutter/services.dart';

const tileSize = 8.0;

class ClusterizerExample extends FlameGame
    with
        HasClusterizedCollisionDetection,
        KeyboardEvents,
        ScrollDetector,
        ScaleDetector,
        HasTappableComponents {
  ClusterizerExample();

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

  final demoMapLoader = DemoMapLoader();

  @override
  Future<void> onLoad() async {
    super.onLoad();

    player = world.player;
    const blockSize = 100.0;
    initializeCollisionDetection(
        debug: false,
        activeRadius: 3,
        unloadRadius: 5,
        blockSize: blockSize,
        trackedComponent: player,
        rootComponent: world,
        cellBuilder: demoMapLoader.cellBuilder);
    await demoMapLoader.init(this);
    cameraComponent = CameraComponent(world: world);
    cameraComponent.viewfinder.zoom = 3;
    add(world);
    add(cameraComponent);
    cameraComponent.follow(player);

    add(FpsTextComponent());
  }

  final elapsedMicroseconds = <double>[];

  late final CameraComponent cameraComponent;
  MyWorld world = MyWorld();

  late Player player;
  final _playerDisplacement = Vector2.zero();
  var _fireBullet = false;
  var _killWater = false;

  static const stepSize = 2.0;

  @override
  KeyEventResult onKeyEvent(
    RawKeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    for (final key in keysPressed) {
      if (key == LogicalKeyboardKey.keyW && player.canMoveTop) {
        _playerDisplacement.setValues(0, -stepSize);
        player.position = player.position.translate(0, -stepSize);
      }
      if (key == LogicalKeyboardKey.keyA && player.canMoveLeft) {
        _playerDisplacement.setValues(-stepSize, 0);
        player.position = player.position.translate(-stepSize, 0);
      }
      if (key == LogicalKeyboardKey.keyS && player.canMoveBottom) {
        _playerDisplacement.setValues(0, stepSize);
        player.position = player.position.translate(0, stepSize);
      }
      if (key == LogicalKeyboardKey.keyD && player.canMoveRight) {
        _playerDisplacement.setValues(stepSize, 0);
        player.position = player.position.translate(stepSize, 0);
      }
      if (key == LogicalKeyboardKey.shiftLeft) {
        _killWater = !_killWater;
      }
      if (key == LogicalKeyboardKey.space) {
        _fireBullet = true;
      }
      if (key == LogicalKeyboardKey.keyT) {
        final collisionType = player.boundingBox.collisionType;
        if (collisionType == CollisionType.active) {
          player.boundingBox.collisionType = CollisionType.inactive;
        } else if (collisionType == CollisionType.inactive) {
          player.boundingBox.collisionType = CollisionType.active;
        }
      }

      if (key == LogicalKeyboardKey.keyM) {
        isClusterizerDebugEnabled = !isClusterizerDebugEnabled;
      }
    }
    if (_fireBullet && !_playerDisplacement.isZero()) {
      final bullet = Bullet(
          position: player.position,
          displacement: _playerDisplacement * 30,
          killWater: _killWater);
      bullet.currentCell = player.currentCell;
      world.add(bullet);
      _playerDisplacement.setZero();
      _fireBullet = false;
    }

    return KeyEventResult.handled;
  }

  @override
  void onScroll(PointerScrollInfo info) {
    var zoom = cameraComponent.viewfinder.zoom;
    zoom += info.scrollDelta.game.y.sign * 0.08;
    cameraComponent.viewfinder.zoom = zoom.clamp(0.05, 5.0);
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    var zoom = cameraComponent.viewfinder.zoom;
    zoom += info.delta.game.y.sign * 0.08;
    cameraComponent.viewfinder.zoom = zoom.clamp(0.05, 5.0);
  }

  @override
  void update(double dt) {
    // final sw = Stopwatch()..start();
    super.update(dt);
    // sw.stop();
    // print(sw.elapsedMicroseconds);
  }
}

class MyWorld extends World with TapCallbacks, HasGameRef<ClusterizerExample> {
  static const mapSize = 50;

  final Player player = Player(
      position: Vector2(400, 156), size: Vector2.all(tileSize), priority: 2);

  @override
  onLoad() async {
    add(player);
  }

  @override
  void onTapDown(TapDownEvent event) {
    final tapPosition = event.localPosition;
    final cellsUnderCursor = <Cell>[];
    gameRef.clusterizer.cells.forEach((rect, cell) {
      if (cell.rect.containsPoint(tapPosition)) {
        cellsUnderCursor.add(cell);
        print('State:  + ${cell.state}');
        print('Rect: $rect');
        // print('Components count: ${cell.components.length}');
      }
    });

    final list = componentsAtPoint(tapPosition);
    for (var component in list) {
      if (component is! ClusterizedComponent) continue;
      print(component.runtimeType);
    }

    player.position = event.localPosition;
  }
}

//#region Player

class Player extends SpriteComponent
    with
        CollisionCallbacks,
        HasGameRef<ClusterizerExample>,
        ClusterizedComponent {
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

class Bullet extends PositionComponent
    with CollisionCallbacks, HasPaint, ClusterizedComponent {
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
    if (other is Player /* || other is Water*/) {
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
    with
        CollisionCallbacks,
        ClusterizedComponent,
        GameCollideable,
        UpdateOnDemand {
  Brick({
    required super.position,
    required super.sprite,
  }) {
    size = Vector2.all(tileSize);
    initCollision();
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    if (other is Bullet) {
      removeFromParent();
    }
    super.onCollisionStart(intersectionPoints, other);
  }
}

class Water extends SpriteAnimationComponent
    with CollisionCallbacks, ClusterizedComponent, GameCollideable {
  Water({required super.position, required super.animation}) {
    size = Vector2.all(tileSize);
    initCollision();
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    if (other is Bullet && other.killWater) {
      removeFromParent();
      super.onCollisionStart(intersectionPoints, other);
    }
  }
}

mixin GameCollideable on ClusterizedComponent {
  void initCollision() {
    boundingBox.collisionType =
        boundingBox.defaultCollisionType = CollisionType.passive;
    boundingBox.isSolid = true;
  }

  Vector2 get cachedCenter => boundingBox.aabbCenter;
}

//#endregion

//#region Utils

mixin UpdateOnce on PositionComponent {
  bool updateOnce = true;

  @override
  void updateTree(double dt) {
    if (updateOnce) {
      super.updateTree(dt);
      updateOnce = false;
    }
  }
}

extension Vector2Ext on Vector2 {
  Vector2 translate(double x, double y) {
    return Vector2(this.x + x, this.y + y);
  }
}

class DemoMapLoader extends TiledMapLoader {
  @override
  Vector2 get initialPosition => Vector2(0, 0);

  @override
  TileBuilderFunction? get defaultBuilder => null;

  @override
  Vector2 get destTileSize => Vector2.all(8);

  @override
  String get fileName => 'example.tmx';

  @override
  TileBuilderFunction? get notFoundBuilder => null; //onBackgroundBuilder;

  @override
  Map<String, TileBuilderFunction> get tileBuilders =>
      {'Brick': onBuildBrick, 'Water': onBuildWater};

  final _animationLayers = HashMap<Cell, CellStaticAnimationLayer>();

  Sprite? spriteBrick;
  SpriteAnimation? waterAnimation;

  //TODO: optimize into layer
  Future<void> onBuildBrick(
      TileDataProvider tile, Vector2 position, Vector2 size, Cell cell) async {
    spriteBrick ??= await tile.getSprite();
    final brick = Brick(position: position, sprite: spriteBrick);
    brick.currentCell = cell;
    rootComponent.add(brick);
  }

  //TODO: make map loader with autogrouping to layers
  Future<void> onBuildWater(
      TileDataProvider tile, Vector2 position, Vector2 size, Cell cell) async {
    final animationLayer =
        _animationLayers[cell] ?? CellStaticAnimationLayer(cell);
    animationLayer.priority = 1;
    animationLayer.optimizeCollisions = true;

    waterAnimation ??= await tile.getSpriteAnimation();
    final water = Water(
      position: position - cell.rect.topLeft.toVector2(),
      animation: waterAnimation,
    );

    water.currentCell = cell;
    animationLayer.add(water);

    if (_animationLayers[cell] == null) {
      _animationLayers[cell] = animationLayer;
      rootComponent.add(animationLayer);
    }
  }

  static const blockSize = 100.0;

  @override
  Future<void> cellBuilder(Cell cell, Component rootComponent) async {
    await super.cellBuilder(cell, rootComponent);
    if (mapRect == Rect.zero) return;

    final checkList = [
      cell.rect.topLeft,
      cell.rect.bottomLeft,
      cell.rect.topRight,
      cell.rect.bottomRight
    ];
    var isCellOutsideOfMap = true;
    for (final cellPoint in checkList) {
      if (mapRect.contains(cellPoint)) {
        isCellOutsideOfMap = false;
        break;
      }
    }

    if (isCellOutsideOfMap) {
      final staticLayer = CellStaticLayer(cell);
      staticLayer.optimizeCollisions = true;
      staticLayer.priority = 2;
      for (var i = 0; i < 200; i++) {
        final random = Random();
        final diffX = random.nextInt((blockSize / 2 - 25).ceil()).toDouble() *
            (random.nextBool() ? -1 : 1);
        final diffY = random.nextInt((blockSize / 2 - 25).ceil()).toDouble() *
            (random.nextBool() ? -1 : 1);
        final position =
            (cell.rect.size / 2).toVector2().translate(diffX, diffY);
        final brick = Brick(position: position, sprite: spriteBrick);
        brick.currentCell = cell;
        staticLayer.add(brick);
      }

      rootComponent.add(staticLayer);

      final animationLayer = CellStaticAnimationLayer(cell);
      animationLayer.priority = 1;

      for (var i = 0; i < 200; i++) {
        final random = Random();
        final diffX = random.nextInt((blockSize / 2 - 20).ceil()).toDouble() *
            (random.nextBool() ? -1 : 1);
        final diffY = random.nextInt((blockSize / 2 - 20).ceil()).toDouble() *
            (random.nextBool() ? -1 : 1);
        final position =
            (cell.rect.size / 2).toVector2().translate(diffX, diffY);
        final water = Water(
          position: position,
          animation: waterAnimation,
        );
        water.currentCell = cell;
        animationLayer.add(water);
      }

      animationLayer.optimizeCollisions = true;
      rootComponent.add(animationLayer);
    }
  }

// Future<void> onBackgroundBuilder(
//     TileBuilder tile, Vector2 position, Vector2 size) {
//
// }
}
//#endregion
