import 'dart:collection';
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

mixin ClusterizedComponent on PositionComponent {
  static final _componentHitboxes =
      HashMap<ShapeHitbox, ClusterizedComponent>();

  // TODO: pass into ShapeHitbox
  static final _cachedCenters = HashMap<ShapeHitbox, Vector2>();

  static final _defaultCollisionType = HashMap<ShapeHitbox, CollisionType>();

  @internal
  final visibilityNotifier = ValueNotifier<bool>(true);

  bool get isVisible => visibilityNotifier.value;

  set isVisible(bool visible) {
    visibilityNotifier.value = visible;
  }

  @internal
  final suspendNotifier = ValueNotifier<bool>(false);

  bool toggleCollisionOnSuspendChange = true;

  bool get isSuspended => suspendNotifier.value;

  set isSuspended(bool suspend) {
    if (suspendNotifier.value != suspend) {
      if (suspend) {
        onSuspend();
      } else {
        onResume(_dtElapsedWhileSuspended);
        _dtElapsedWhileSuspended = 0;
      }
    }
    suspendNotifier.value = suspend;
  }

  Cell? currentCell;

  Clusterizer? _clusterizer;

  Clusterizer get clusterizer => _clusterizer!;

  void setClusterizer(Clusterizer clusterizer) {
    _clusterizer ??= clusterizer;
  }

  bool get isTracked => this == currentCell?.clusterizer.trackedComponent;

  final boundingBox = RectangleHitbox()..collisionType = CollisionType.inactive;

  double _dtElapsedWhileSuspended = 0;

  double _minDistanceQuad = 0;

  double get minDistanceQuad => _minDistanceQuad;

  double get minDistance => sqrt(_minDistanceQuad);

  @mustCallSuper
  void onClusterizerMounted() {}

  @override
  Future<void>? onLoad() {
    add(boundingBox);
    boundingBox.transform.addListener(_onBoundingBoxTransform);
    return super.onLoad();
  }

  void _onBoundingBoxTransform() {
    _minDistanceQuad =
        (pow(boundingBox.width / 2, 2) + pow(boundingBox.height / 2, 2))
            .toDouble();
  }

  @override
  void onRemove() {
    boundingBox.transform.removeListener(_onBoundingBoxTransform);
  }

  @override
  void updateTree(double dt) {
    isSuspended = (currentCell?.state == CellState.suspended ? true : false);
    if (isSuspended) {
      _dtElapsedWhileSuspended += dt;
      updateSuspendedTree(_dtElapsedWhileSuspended);
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
    isVisible = (currentCell?.state == CellState.active ? true : false);
    if (isVisible) {
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
        currentCell = clusterizer.findExistingCellByPosition(componentCenter);
    if (current == null) {
      throw 'Cell did not found at position $componentCenter';
    }
    if (current.rect.containsPoint(componentCenter) != true) {
      Cell? newCell;
      //look close neighbours
      for (var cell in current.neighbours) {
        if (cell.rect.containsPoint(componentCenter)) {
          newCell = cell;
          break;
        }
      }
      //if nothing - search among all cells
      if (newCell == null) {
        for (var cell in clusterizer.cells.entries) {
          if (cell.value.rect.containsPoint(componentCenter)) {
            newCell = cell.value;
            break;
          }
        }
      }
      //if nothing again - try to locate new cell's position from component's
      //coordinates
      newCell ??= clusterizer.createNewCellAtPosition(componentCenter);

      newCell.left;
      newCell.right;
      newCell.top;
      newCell.bottom;
      currentCell = newCell;
      if (isTracked) {
        clusterizer.setActiveCell(newCell);
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

extension ClusterizedRectangleHitbox on RectangleHitbox {
  Vector2 get aabbCenter {
    var cache = ClusterizedComponent._cachedCenters[this];
    if (cache == null) {
      ClusterizedComponent._cachedCenters[this] = aabb.center;
      cache = ClusterizedComponent._cachedCenters[this];
    }
    return cache!;
  }
}

extension ClusterizedShapeHitbox on ShapeHitbox {
  // TODO: pass into ShapeHitbox?
  Vector2 get aabbCenter {
    var cache = ClusterizedComponent._cachedCenters[this];
    if (cache == null) {
      ClusterizedComponent._cachedCenters[this] = aabb.center;
      cache = ClusterizedComponent._cachedCenters[this];
    }
    return cache!;
  }

  ClusterizedComponent? get clusterizedParent {
    var component = ClusterizedComponent._componentHitboxes[this];
    if (component == null) {
      try {
        component = ancestors().firstWhere(
          (c) => c is ClusterizedComponent,
        ) as ClusterizedComponent;
        ClusterizedComponent._componentHitboxes[this] = component;
        return component;
      } catch (e) {
        return null;
      }
    }
    return component;
  }

  @internal
  void clearClusterizedParent() {
    ClusterizedComponent._componentHitboxes.remove(this);
  }

  set defaultCollisionType(CollisionType defaultCollisionType) {
    ClusterizedComponent._defaultCollisionType[this] = defaultCollisionType;
  }

  CollisionType get defaultCollisionType {
    var cache = ClusterizedComponent._defaultCollisionType[this];
    if (cache == null) {
      ClusterizedComponent._defaultCollisionType[this] = collisionType;
      cache = ClusterizedComponent._defaultCollisionType[this];
    }
    return cache!;
  }
}
