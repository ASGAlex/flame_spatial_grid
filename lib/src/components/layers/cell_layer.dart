import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';
import 'package:flame_clusterizer/src/collisions/collision_optimizer.dart';
import 'package:meta/meta.dart';

abstract class CellLayer extends PositionComponent
    with
        ClusterizedComponent,
        UpdateOnDemand,
        HasGameReference<HasClusterizedCollisionDetection> {
  CellLayer(Cell cell)
      : super(
            position: cell.rect.topLeft.toVector2(),
            size: cell.rect.size.toVector2()) {
    currentCell = cell;
    collisionOptimizer = CollisionOptimizer(this);
  }

  bool optimizeCollisions = false;

  @protected
  late final CollisionOptimizer collisionOptimizer;

  @protected
  final correctionTopLeft = Vector2.zero();

  @protected
  final correctionBottomRight = Vector2.zero();

  final _listenerChildrenUpdate = <Component, VoidCallback>{};

  void onChildrenUpdate() {
    isUpdateNeeded = true;
  }

  @protected
  compileToSingleLayer();

  Size get layerCalculatedSize {
    final cell = currentCell;
    if (cell == null) throw 'layer should be connected with any cell!';
    var width = cell.rect.width;
    var height = cell.rect.height;
    if (correctionBottomRight != Vector2.zero()) {
      final diff = correctionBottomRight - correctionTopLeft;
      width = diff.x.ceil().toDouble();
      height = diff.y.ceil().toDouble();
    }

    return Size(width, height);
  }

  @override
  Future<void>? add(Component component) {
    if (component is PositionComponent) {
      if (component.position.x < correctionTopLeft.x) {
        correctionTopLeft.x = component.position.x;
      }
      if (component.position.y < correctionTopLeft.y) {
        correctionTopLeft.y = component.position.y;
      }

      final bottomRightPosition = component.position + component.size;
      if (bottomRightPosition.x > correctionBottomRight.x) {
        correctionBottomRight.x = bottomRightPosition.x;
      }
      if (bottomRightPosition.y > correctionBottomRight.y) {
        correctionBottomRight.y = bottomRightPosition.y;
      }
    }

    if (component is ClusterizedComponent) {
      if (component is RepaintOnDemand) {
        component.repaintNotifier.addListener(onChildrenUpdate);
      } else {
        component.transform.addListener(onChildrenUpdate);
      }
      _listenerChildrenUpdate[component] = onChildrenUpdate;
    }
    onBeforeChildrenChanged(component, ChildrenChangeType.added);
    return super.add(component);
  }

  @override
  void updateTree(double dt) {
    if (isUpdateNeeded) {
      super.updateTree(dt);
      if (optimizeCollisions) {
        collisionOptimizer.optimize();
        isUpdateNeeded = true;
      }
      super.updateTree(dt);
      compileToSingleLayer();
    }
  }

  @override
  void renderTree(Canvas canvas) {
    isVisible = (currentCell?.state == CellState.active ? true : false);
    if (isVisible) {
      decorator.applyChain(render, canvas);
    }
  }

  @override
  void remove(Component component) {
    final callback = _listenerChildrenUpdate.remove(component);
    if (callback != null) {
      if (component is RepaintOnDemand) {
        component.repaintNotifier.removeListener(callback);
      } else {
        (component as PositionComponent).transform.removeListener(callback);
      }
    }

    onBeforeChildrenChanged(component, ChildrenChangeType.removed);

    super.remove(component);
  }

  void onBeforeChildrenChanged(Component child, ChildrenChangeType type) {
    if (child is UpdateOnDemand) {
      child.isUpdateNeeded = true;
    }
    isUpdateNeeded = true;
  }
}
