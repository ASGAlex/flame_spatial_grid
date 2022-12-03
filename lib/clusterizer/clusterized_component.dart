import 'dart:math';

import 'package:cluisterizer_test/clusterizer/clusterizer.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'cell.dart';

mixin ClusterizedComponent on PositionComponent {
  static final _componentHitboxes = <ShapeHitbox, ClusterizedComponent>{};

  // TODO: pass into ShapeHitbox
  static final _cachedCenters = <ShapeHitbox, Vector2>{};

  static final _defaultCollisionType = <ShapeHitbox, CollisionType>{};

  bool isVisible = true;

  @internal
  final suspendNotifier = ValueNotifier<bool>(false);

  bool toggleCollisionOnSuspendChange = true;

  bool get isSuspended => suspendNotifier.value;

  Cell? currentCell;

  late final Clusterizer clusterizer;

  bool get isTracked => this == currentCell?.clusterizer.trackedComponent;

  final boundingBox = RectangleHitbox()..collisionType = CollisionType.inactive;

  double _dtElapsedWhileSuspended = 0;

  double _minDistanceQuad = 0;

  double get minDistanceQuad => _minDistanceQuad;

  double get minDistance => sqrt(_minDistanceQuad);

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

  @override
  onMount() {
    add(boundingBox);
    boundingBox.transform.addListener(_onBoundingBoxTransform);
  }

  void _onBoundingBoxTransform() {
    _minDistanceQuad =
        (pow(boundingBox.width / 2, 2) + pow(boundingBox.height / 2, 2))
            .toDouble();
  }

  @override
  void onRemove() {
    boundingBox.transform.removeListener(_onBoundingBoxTransform);
    remove(boundingBox);
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
  }

  // @override
  // void onMount() {
  //   super.onMount();
  //   transform.addListener(_onTransform);
  // }
  //
  // @override
  // void onRemove() {
  //   transform.removeListener(_onTransform);
  //   super.onRemove();
  // }

  @internal
  bool updateTransform() {
    _cachedCenters.remove(boundingBox);
    final lookAtPoint = boundingBox.aabbCenter;
    final current = currentCell;
    if (current == null) throw 'current cell cant be null!';
    if (clusterizer == null) throw 'clusterizer cant be null!';
    if (current.rect.containsPoint(lookAtPoint) != true) {
      Cell? newCell;
      //look close neighbours
      for (var cell in current.neighbours) {
        if (cell.rect.containsPoint(lookAtPoint)) {
          newCell = cell;
          break;
        }
      }
      //if nothing - search among all cells
      if (newCell == null) {
        for (var cell in clusterizer.cells.entries) {
          if (cell.value.rect.containsPoint(lookAtPoint)) {
            newCell = cell.value;
            break;
          }
        }
      }
      //if nothing again - try to locate new cell's position from component's
      //coordinates
      if (newCell == null) {
        newCell = clusterizer.createNewCellAtPosition(lookAtPoint);

        if (newCell == null) {
          throw 'teleportation error';
        }
      }

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
    final component = ClusterizedComponent._componentHitboxes[this];
    if (component == null) {
      try {
        return ancestors().firstWhere(
          (c) => c is ClusterizedComponent,
        ) as ClusterizedComponent;
      } catch (e) {
        return null;
      }
    }
    return component;
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
