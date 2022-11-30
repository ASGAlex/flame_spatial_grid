import 'package:cluisterizer_test/clusterizer/cell_builder.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/layers.dart';
import 'package:flutter/material.dart' hide Image, Draggable;
import 'package:flutter/services.dart';

import 'clusterizer/clusterized_component.dart';
import 'clusterizer/collisions/has_clusterized_collision_detection.dart';

const tileSize = 8.0;

class QuadTreeExample extends FlameGame
    with HasClusterizedCollisionDetection, KeyboardEvents, ScrollDetector {
  QuadTreeExample();

  static const description = '''
In this example the standard "Sweep and Prune" algorithm is replaced by  
"Quad Tree". Quad Tree is often a more efficient approach of handling collisions,
its efficiency is shown especially on huge maps with big amounts of collidable 
components.
Some bricks are highlighted when placed on an edge of a quadrant. It is
important to understand that handling hitboxes on edges requires more
resources.
Blue lines visualise the quad tree's quadrant positions.

Use WASD to move the player and use the mouse scroll to change zoom.
Hold direction button and press space to fire a bullet. 
Notice that bullet will fly above water but collides with bricks.

Also notice that creating a lot of bullets at once leads to generating new
quadrants on the map since it becomes more than 25 objects in one quadrant.

Press O button to rescan the tree and optimize it, removing unused quadrants.

Press T button to toggle player to collide with other objects.
  ''';

  @override
  Future<void> onLoad() async {
    super.onLoad();

    // final random = Random();
    // final spriteBrick = await Sprite.load(
    //   'retro_tiles.png',
    //   srcPosition: Vector2.all(0),
    //   srcSize: Vector2.all(tileSize),
    // );
    //
    // final spriteWater = await Sprite.load(
    //   'retro_tiles.png',
    //   srcPosition: Vector2(0, tileSize),
    //   srcSize: Vector2.all(tileSize),
    // );
    // for (var i = 0; i < bricksCount; i++) {
    //   final x = random.nextInt(mapSize);
    //   final y = random.nextInt(mapSize);
    //   final brick = Brick(
    //     position: Vector2(x.toDouble() * tileSize, y.toDouble() * tileSize),
    //     size: Vector2.all(tileSize),
    //     priority: 0,
    //     sprite: spriteBrick,
    //   );
    //   add(brick);
    //   staticLayer.components.add(brick);
    // }
    //
    // staticLayer.reRender();

    final spriteBrick = await Sprite.load(
      'retro_tiles.png',
      srcPosition: Vector2.all(0),
      srcSize: Vector2.all(tileSize),
    );

    player = world.player;
    var firstBrick = true;
    initializeCollisionDetection(
        debug: true,
        activeRadius: 2,
        blockSize: 100,
        trackedComponent: player,
        rootComponent: world,
        cellBuilder: CellBuilder(
          builder: (cell, parentComponent) async {
            if (firstBrick) {
              firstBrick = false;
              return [];
            }
            final brick = Brick(
                position: cell.rect.center.toVector2(),
                priority: 1,
                sprite: spriteBrick);
            return [brick];
          },
        ));
    cameraComponent = CameraComponent(world: world);
    cameraComponent.viewfinder.zoom = 0.2;
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

  final staticLayer = StaticLayer();
  static const stepSize = 160.0;

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
      if (key == LogicalKeyboardKey.space) {
        _fireBullet = true;
      }
      if (key == LogicalKeyboardKey.keyT) {
        final collisionType = player.defaultHitbox.collisionType;
        if (collisionType == CollisionType.active) {
          player.defaultHitbox.collisionType = CollisionType.inactive;
        } else if (collisionType == CollisionType.inactive) {
          player.defaultHitbox.collisionType = CollisionType.active;
        }
      }
      if (key == LogicalKeyboardKey.keyO) {
        // collisionDetection.broadphase.tree.optimize();
      }
    }
    if (_fireBullet && !_playerDisplacement.isZero()) {
      final bullet = Bullet(
        position: player.position,
        displacement: _playerDisplacement * 50,
      );
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
}

class MyWorld extends World {
  static const mapSize = 300;
  static const bricksCount = 8000;

  final Player player = Player(
      position: Vector2.all(mapSize * tileSize / 2 + 6),
      size: Vector2.all(tileSize),
      priority: 2);

  @override
  onLoad() async {
    add(player);
  }
}

//#region Player

class Player extends SpriteComponent
    with CollisionCallbacks, HasGameRef<QuadTreeExample>, ClusterizedComponent {
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
    defaultHitbox.collisionType =
        defaultHitbox.defaultCollisionType = CollisionType.active;
    // add(hitbox);
  }

  // final hitbox = RectangleHitbox();
  bool canMoveLeft = true;
  bool canMoveRight = true;
  bool canMoveTop = true;
  bool canMoveBottom = true;

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    final myCenter = defaultHitbox.aabbCenter;
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
  Bullet({required super.position, required this.displacement}) {
    paint.color = Colors.deepOrange;
    priority = 10;
    size = Vector2.all(1);
    defaultHitbox.collisionType =
        defaultHitbox.defaultCollisionType = CollisionType.active;
  }

  final Vector2 displacement;

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset.zero, 1, paint);
  }

  @override
  void update(double dt) {
    final d = displacement * dt;
    position = Vector2(position.x + d.x, position.y + d.y);
    super.update(dt);
  }

  @override
  bool onComponentTypeCheck(PositionComponent other) {
    if (other is Player || other is Water) {
      return false;
    }
    return super.onComponentTypeCheck(other);
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    removeFromParent();
    super.onCollisionStart(intersectionPoints, other);
  }
}

//#endregion

//#region Environment

class Brick extends SpriteComponent
    with CollisionCallbacks, ClusterizedComponent, GameCollideable, UpdateOnce {
  Brick({
    required super.position,
    required super.priority,
    required super.sprite,
  }) {
    size = Vector2.all(tileSize);
    initCollision();
  }

  bool rendered = false;

  @override
  void renderTree(Canvas canvas) {
    if (!rendered) {
      super.renderTree(canvas);
    }
  }
}

class Water extends SpriteComponent
    with CollisionCallbacks, ClusterizedComponent, GameCollideable, UpdateOnce {
  Water({
    required super.position,
    required super.size,
    required super.priority,
    required super.sprite,
  }) {
    initCollision();
  }
}

mixin GameCollideable on ClusterizedComponent {
  void initCollision() {
    defaultHitbox.collisionType =
        defaultHitbox.defaultCollisionType = CollisionType.passive;
  }

  Vector2 get cachedCenter => defaultHitbox.aabbCenter;
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

class StaticLayer extends PreRenderedLayer {
  StaticLayer();

  List<PositionComponent> components = [];

  @override
  void drawLayer() {
    for (final element in components) {
      if (element is Brick) {
        element.rendered = false;
        element.renderTree(canvas);
        element.rendered = true;
      }
    }
  }
}

class LayerComponent extends PositionComponent {
  LayerComponent(this.layer);

  StaticLayer layer;

  @override
  void render(Canvas canvas) {
    layer.render(canvas);
  }
}

extension Vector2Ext on Vector2 {
  Vector2 translate(double x, double y) {
    return Vector2(this.x + x, this.y + y);
  }
}

//#endregion
