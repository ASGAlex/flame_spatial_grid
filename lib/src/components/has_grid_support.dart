import 'dart:collection';
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/broadphase.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

mixin HasGridSupport on PositionComponent {
  static final _componentHitboxes = HashMap<ShapeHitbox, HasGridSupport>();

  // TODO: pass into ShapeHitbox
  static final _cachedCenters = HashMap<ShapeHitbox, Vector2>();

  static final _defaultCollisionType = HashMap<ShapeHitbox, CollisionType>();

  bool isVisible = true;

  @internal
  final suspendNotifier = ValueNotifier<bool>(false);

  bool toggleCollisionOnSuspendChange = true;

  bool get isSuspended => suspendNotifier.value;

  Cell? _currentCell;

  Cell? get currentCell => _currentCell;

  set currentCell(Cell? value) {
    final previousCell = _currentCell;
    final hitboxes = children.whereType<ShapeHitbox>();

    _currentCell = value;
    value?.components.add(this);

    for (final hitbox in hitboxes) {
      if (previousCell != null) {
        previousCell.components.remove(this);
      }
      if (hitbox.collisionType == CollisionType.inactive) {
        if (previousCell != null) {
          spatialGrid.game.collisionDetection.broadphase.scheduledOperations
              .add(ScheduledHitboxOperation.removePassive(
                  hitbox: hitbox, cell: previousCell));
        }
        spatialGrid.game.collisionDetection.broadphase.scheduledOperations.add(
            ScheduledHitboxOperation.addPassive(
                hitbox: hitbox, cell: _currentCell));
      }
    }
  }

  SpatialGrid? _spatialGrid;

  SpatialGrid get spatialGrid => _spatialGrid!;

  void setSpatialGrid(SpatialGrid spatialGrid) {
    _spatialGrid ??= spatialGrid;
  }

  bool get isTracked => this == currentCell?.spatialGrid.trackedComponent;

  final boundingBox = RectangleHitbox()..collisionType = CollisionType.inactive;

  @internal
  double dtElapsedWhileSuspended = 0;

  double _minDistanceQuad = 0;

  double get minDistanceQuad => _minDistanceQuad;

  double get minDistance => sqrt(_minDistanceQuad);

  double _minDistanceX = 0;
  double get minDistanceX => _minDistanceX;
  double _minDistanceY = 0;
  double get minDistanceY => _minDistanceY;

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

  @mustCallSuper
  void onSpatialGridSupportComponentMounted() {}

  @override
  @mustCallSuper
  onLoad() {
    add(boundingBox);
    boundingBox.transform.addListener(_onBoundingBoxTransform);
    return null;
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
  bool updateTransform() {
    _cachedCenters.remove(boundingBox);
    final componentCenter = boundingBox.aabbCenter;
    var current = currentCell;
    current ??=
        currentCell = spatialGrid.findExistingCellByPosition(componentCenter);
    if (current == null) {
      throw 'Cell did not found at position $componentCenter';
    }
    if (current.rect.containsPoint(componentCenter) != true) {
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

      newCell.left;
      newCell.right;
      newCell.top;
      newCell.bottom;
      currentCell = newCell;
      if (isTracked) {
        spatialGrid.currentCell = newCell;
      }
      return true; //cell changed;
    }
    return false; //cell not changed;
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

extension SpatialGridRectangleHitbox on RectangleHitbox {
  Vector2 get aabbCenter {
    var cache = HasGridSupport._cachedCenters[this];
    if (cache == null) {
      HasGridSupport._cachedCenters[this] = aabb.center;
      cache = HasGridSupport._cachedCenters[this];
    }
    return cache!;
  }
}

extension SpatialGridShapeHitbox on ShapeHitbox {
  // TODO: pass into ShapeHitbox?
  Vector2 get aabbCenter {
    var cache = HasGridSupport._cachedCenters[this];
    if (cache == null) {
      HasGridSupport._cachedCenters[this] = aabb.center;
      cache = HasGridSupport._cachedCenters[this];
    }
    return cache!;
  }

  HasGridSupport? get parentWithGridSupport {
    var component = HasGridSupport._componentHitboxes[this];
    if (component == null) {
      try {
        component = ancestors().firstWhere(
          (c) => c is HasGridSupport,
        ) as HasGridSupport;
        HasGridSupport._componentHitboxes[this] = component;
        return component;
      } catch (e) {
        return null;
      }
    }
    return component;
  }

  @internal
  void clearGridComponentParent() {
    HasGridSupport._componentHitboxes.remove(this);
  }

  set defaultCollisionType(CollisionType defaultCollisionType) {
    HasGridSupport._defaultCollisionType[this] = defaultCollisionType;
  }

  CollisionType get defaultCollisionType {
    var cache = HasGridSupport._defaultCollisionType[this];
    if (cache == null) {
      HasGridSupport._defaultCollisionType[this] = collisionType;
      cache = HasGridSupport._defaultCollisionType[this];
    }
    return cache!;
  }
}
