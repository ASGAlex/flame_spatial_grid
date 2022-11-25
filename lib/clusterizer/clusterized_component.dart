import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'cell.dart';

mixin ClusterizedComponent on PositionComponent {
  // TODO: pass into ShapeHitbox
  static final componentHitboxes = <ShapeHitbox, ClusterizedComponent>{};

  bool isVisible = true;

  final suspendNotifier = ValueNotifier<bool>(false);

  bool toggleCollisionOnSuspendChange = true;

  bool get isSuspended => suspendNotifier.value;

  Cell? currentCell;

  bool get isTracked => this == currentCell?.clusterizer.trackedComponent;

  final defaultHitbox = RectangleHitbox()
    ..collisionType = CollisionType.inactive;

  double _dtElapsedWhileSuspended = 0;

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
    add(defaultHitbox);
  }

  @override
  void onRemove() {
    remove(defaultHitbox);
  }

  @override
  void updateTree(double dt) {
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
  void updateTransform() {
    final lookAtPoint = toRect().center.toVector2();
    final current = currentCell;
    if (current == null) throw 'current cell cant be null!';
    final clusterizer = current.clusterizer;
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
        final diff = lookAtPoint - current.rect.center.toVector2();
        final stepSize = current.rect.width;
        final pos = current.rect.center.toVector2();
        var xSign = diff.x > 0 ? 1 : -1;
        var ySign = diff.y > 0 ? 1 : -1;
        var newTemporaryCell = current;
        while ((lookAtPoint.x - pos.x).abs() >= stepSize / 3) {
          if (xSign > 0) {
            newTemporaryCell = newTemporaryCell.right;
          } else {
            newTemporaryCell = newTemporaryCell.left;
          }
          pos.x = newTemporaryCell.rect.center.dx;
        }
        while ((lookAtPoint.y - pos.y).abs() >= stepSize / 3) {
          if (ySign > 0) {
            newTemporaryCell = newTemporaryCell.bottom;
          } else {
            newTemporaryCell = newTemporaryCell.top;
          }
          pos.y = newTemporaryCell.rect.center.dy;
        }
        if (newTemporaryCell.rect.contains(lookAtPoint.toOffset())) {
          newCell = newTemporaryCell;
        } else {
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
    }
  }
}

// TODO: pass into ShapeHitbox
extension ClusterizedShapeHitbox on ShapeHitbox {
  ClusterizedComponent? get clusterizedParent {
    final component = ClusterizedComponent.componentHitboxes[this];
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
}
