import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

mixin HasGridSupport on PositionComponent {
  @internal
  static final componentHitboxes = HashMap<ShapeHitbox, HasGridSupport>();

  @internal
  static final cachedCenters = HashMap<ShapeHitbox, Vector2>();

  @internal
  static final defaultCollisionType = HashMap<ShapeHitbox, CollisionType>();

  bool isVisible = true;

  @internal
  final suspendNotifier = ValueNotifier<bool>(false);

  bool toggleCollisionOnSuspendChange = true;

  bool get isSuspended => suspendNotifier.value;

  set isSuspended(bool suspend) {
    if (suspendNotifier.value != suspend) {
      if (suspend) {
        onSuspend();
      } else {
        onResume(dtElapsedWhileSuspended);
        dtElapsedWhileSuspended = 0;
      }
    }
    suspendNotifier.value = suspend;
  }

  Cell? _currentCell;

  Cell? get currentCell => _currentCell;

  set currentCell(Cell? value) {
    final previousCell = _currentCell;
    final hitboxes = children.whereType<ShapeHitbox>();

    _currentCell = value;
    value?.components.add(this);

    if (hitboxes.isNotEmpty) {
      final broadphase = spatialGrid.game.collisionDetection.broadphase;
      for (final hitbox in hitboxes) {
        if (previousCell != null) {
          previousCell.components.remove(this);
        }
        broadphase.updateHitboxIndexes(hitbox, previousCell);
      }
    }
  }

  SpatialGrid? _spatialGrid;

  SpatialGrid get spatialGrid => _spatialGrid!;

  void setSpatialGrid(SpatialGrid spatialGrid) {
    _spatialGrid ??= spatialGrid;
  }

  bool get isTracked => this == currentCell?.spatialGrid.trackedComponent;

  late final boundingBox = BoundingHitbox(
    position: Vector2.zero(),
    size: Vector2.zero(),
    parentWithGridSupport: this,
  )..collisionType = CollisionType.inactive;

  @internal
  double dtElapsedWhileSuspended = 0;

  double _minDistanceQuad = 0;

  double get minDistanceQuad => _minDistanceQuad;

  double get minDistance => sqrt(_minDistanceQuad);

  double _minDistanceX = 0;

  double get minDistanceX => _minDistanceX;
  double _minDistanceY = 0;

  double get minDistanceY => _minDistanceY;

  bool _outOfCellBounds = false;

  bool get isOutOfCellBounds => _outOfCellBounds;

  @mustCallSuper
  void onSpatialGridSupportComponentMounted() {}

  @override
  @mustCallSuper
  Future<void>? onLoad() {
    boundingBox.size.setFrom(Rect.fromLTWH(0, 0, size.x, size.y).toVector2());
    add(boundingBox);
    boundingBox.transform.addListener(_onBoundingBoxTransform);
    return null;
  }

  @override
  FutureOr<void>? add(Component component) {
    if (component != boundingBox && component is ShapeHitbox) {
      final currentRect = boundingBox.shouldFillParent
          ? Rect.fromLTWH(0, 0, size.x, size.y)
          : boundingBox.toRect();
      final addRect = component.toRect();
      final newRect = currentRect.expandToInclude(addRect);
      boundingBox.position.setFrom(newRect.topLeft.toVector2());
      boundingBox.size.setFrom(newRect.size.toVector2());
    }
    return super.add(component);
  }

  void _onBoundingBoxTransform() {
    _minDistanceQuad =
        (pow(boundingBox.width / 2, 2) + pow(boundingBox.height / 2, 2))
            .toDouble();
    _minDistanceX = boundingBox.width / 2;
    _minDistanceY = boundingBox.height / 2;
  }

  @override
  void onRemove() {
    boundingBox.transform.removeListener(_onBoundingBoxTransform);
  }

  @override
  void updateTree(double dt) {
    if (isSuspended) {
      dtElapsedWhileSuspended += dt;
      updateSuspendedTree(dtElapsedWhileSuspended);
    } else {
      super.updateTree(dt);
    }
  }

  /// Called instead of [updateTree] when component is suspended.
  /// [dtElapsedWhileSuspended] accumulates all [dt] values since
  /// component suspension
  void updateSuspendedTree(double dtElapsedWhileSuspended) {}

  /// Called when component state changes to "suspended". You should stop
  /// all undesired component's movements (for example) here
  void onSuspend() {}

  /// Called when component state changes from "suspended" to active.
  /// [dtElapsedWhileSuspended] accumulates all [dt] values since
  /// component suspension. Useful to calculate next animation step as if
  /// the component was never suspended.
  void onResume(double dtElapsedWhileSuspended) {}

  @override
  void renderTree(Canvas canvas) {
    if (isVisible && currentCell?.state == CellState.active) {
      super.renderTree(canvas);
    }
    if (debugMode) {
      renderDebugMode(canvas);
    }
  }

  @internal
  void updateTransform() {
    boundingBox.aabbCenter = boundingBox.aabb.center;
    cachedCenters.remove(boundingBox);
    final componentCenter = boundingBox.aabbCenter;
    var current = currentCell;
    current ??= spatialGrid.findExistingCellByPosition(componentCenter) ??
        spatialGrid.createNewCellAtPosition(componentCenter);
    if (current.rect.containsPoint(componentCenter)) {
      if (current != _currentCell) {
        isSuspended = current.state == CellState.suspended;
      }
      _currentCell = current;
    } else {
      Cell? newCell;
      //look close neighbours
      for (final cell in current.neighbours) {
        if (cell.rect.containsPoint(componentCenter)) {
          newCell = cell;
          break;
        }
      }
      //if nothing - search among all cells
      if (newCell == null) {
        for (final cell in spatialGrid.cells.entries) {
          if (cell.value.rect.containsPoint(componentCenter)) {
            newCell = cell.value;
            break;
          }
        }
      }
      //if nothing again - try to locate new cell's position from component's
      //coordinates
      newCell ??= spatialGrid.createNewCellAtPosition(componentCenter);

      currentCell = newCell;
      isSuspended = newCell.state == CellState.suspended;
      if (isTracked) {
        spatialGrid.currentCell = newCell;
      }
    }
    _outOfCellBounds = !boundingBox.isFullyInsideRect(current.rect);
  }

  @override
  void renderDebugMode(Canvas canvas) {
    super.renderDebugMode(canvas);
    debugTextPaint.render(
      canvas,
      '$runtimeType',
      Vector2(0, 0),
    );
  }
}
