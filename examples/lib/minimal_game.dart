import 'dart:async';
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/material.dart' hide Image, Draggable;

class MinimalGame extends FlameGame with HasSpatialGridFramework {
  MinimalGame();

  @override
  FutureOr<void> onLoad() async {
    final player = Player(position: Vector2(160, 190), isPrimary: true);
    await initializeSpatialGrid(
      blockSize: 50,
      debug: true,
      activeRadius: const Size(2, 2),
      unloadRadius: const Size(2, 2),
      trackWindowSize: false,
      trackedComponent: player,
      cellBuilderNoMap: onBuildNewCell,
      suspendedCellLifetime: const Duration(seconds: 30),
    );

    add(player);
    for (var i = 0; i < 100; i++) {
      add(Player(position: Vector2(i * 10.0, 20)));
    }
    // add(FpsTextComponent());
    return super.onLoad();
  }

  Future<void> onBuildNewCell(
    Cell cell,
    Component rootComponent,
    bool isFullyOutside,
  ) async {
    final random = Random();
    final doCreation = random.nextBool();
    if (doCreation) {
      add(Player(position: cell.center)..currentCell = cell);
    }
  }
}

class Player extends PositionComponent
    with HasGridSupport, HasPaint, CollisionCallbacks {
  Player({super.position, bool? isPrimary}) : super(size: Vector2(10, 10)) {
    _isPrimary = isPrimary ?? false;
    paint.color = _isPrimary ? Colors.indigoAccent : Colors.brown;
    _rect = Rect.fromLTWH(0, 0, size.x, size.y);

    if (!_isPrimary) {
      debugMode = true;
    }

    boundingBox.collisionType =
        boundingBox.defaultCollisionType = CollisionType.active;
  }

  late final Rect _rect;
  late final bool _isPrimary;

  @override
  void render(Canvas canvas) {
    canvas.drawRect(_rect, paint);
  }

  final speed = 80;
  final vector = Vector2.zero();
  double dtElapsed = 0;
  final dtMax = 400;

  @override
  void update(double dt) {
    dtElapsed++;
    if (dtElapsed >= dtMax || _outOfBounds()) {
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

  void _createNewVector() {
    final rand = Random();
    var xSign = rand.nextBool() ? -1 : 1;
    var ySign = rand.nextBool() ? -1 : 1;
    if (position.x >= 900) {
      xSign = -1;
    } else if (position.x <= 0) {
      xSign = 1;
    }

    if (position.y >= 500) {
      ySign = -1;
    } else if (position.y <= 0) {
      ySign = 1;
    }
    final xValue = rand.nextDouble();
    final yValue = rand.nextDouble();
    vector.setValues(xValue * xSign, yValue * ySign);
  }

  bool _outOfBounds() =>
      position.x <= 0 ||
      position.y <= 0 ||
      position.x >= 900 ||
      position.y >= 500;

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    if (other is Player) {
      vector.setZero();
    }

    super.onCollision(intersectionPoints, other);
  }
}
