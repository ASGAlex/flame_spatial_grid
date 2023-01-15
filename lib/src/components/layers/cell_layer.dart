import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/collision_optimizer.dart';
import 'package:meta/meta.dart';

abstract class CellLayer extends PositionComponent
    with
        HasGridSupport,
        UpdateOnDemand,
        HasGameReference<HasSpatialGridFramework> {
  CellLayer(Cell cell, {this.name = '', bool? isRenewable})
      : isRenewable = isRenewable ?? true,
        super(
            position: cell.rect.topLeft.toVector2(),
            size: cell.rect.size.toVector2()) {
    currentCell = cell;
    collisionOptimizer = CollisionOptimizer(this);
    _pauseUpdate = !cell.isCellBuildFinished;
  }

  bool optimizeCollisions = false;

  bool doUpdateComponentsPriority = false;

  final bool isRenewable;

  final _nonRenewableComponents = <Component>[];

  late bool _pauseUpdate;

  @internal
  bool get pauseUpdate => _pauseUpdate;

  @internal
  set pauseUpdate(bool value) {
    _pauseUpdate = value;
    if (_pauseUpdate == false) {
      isUpdateNeeded = true;
    }
  }

  @protected
  late final CollisionOptimizer collisionOptimizer;

  @protected
  final correctionTopLeft = Vector2.zero();

  @protected
  final correctionBottomRight = Vector2.zero();

  final _listenerChildrenUpdate = <Component, VoidCallback>{};

  @protected
  Future compileToSingleLayer(Iterable<Component> children);

  final String name;

  Size get layerCalculatedSize {
    final cell = currentCell;
    if (cell == null) {
      throw 'layer should be connected with any cell!';
    }
    var width = cell.rect.width;
    var height = cell.rect.height;
    if (correctionBottomRight != Vector2.zero()) {
      final diff = correctionBottomRight - correctionTopLeft;
      width = max(diff.x.ceil().toDouble(), width);
      height = max(diff.y.ceil().toDouble(), height);
    }

    return Size(width, height);
  }

  @protected
  void updateCorrections(Component component) {
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
  }

  void resetCorrections() {
    correctionTopLeft.setZero();
    correctionBottomRight.setZero();
  }

  @override
  Future<void>? add(Component component) async {
    updateCorrections(component);

    if (isRenewable) {
      if (component is HasGridSupport) {
        component.transform.addListener(onChildrenUpdate);
        _listenerChildrenUpdate[component] = onChildrenUpdate;
      }
      onBeforeChildrenChanged(component, ChildrenChangeType.added);
      return super.add(component);
    } else {
      await component.onLoad();
      _nonRenewableComponents.add(component);
    }
  }

  @override
  void remove(Component component) {
    if (isRenewable) {
      final callback = _listenerChildrenUpdate.remove(component);
      if (callback != null && component is HasGridSupport) {
        component.transform.removeListener(callback);
      }

      onBeforeChildrenChanged(component, ChildrenChangeType.removed);
      super.remove(component);
    } else {
      _nonRenewableComponents.remove(component);
    }
  }

  @override
  void updateTree(double dt) {
    if (isUpdateNeeded) {
      if (isSuspended) {
        dtElapsedWhileSuspended += dt;
        updateSuspendedTree(dtElapsedWhileSuspended);
      } else {
        if (isRenewable) {
          _updateTree(dt);
          if (optimizeCollisions) {
            collisionOptimizer.optimize();
            isUpdateNeeded = true;
            _updateTree(dt);
          }
          compileToSingleLayer(children);
        } else if (_nonRenewableComponents.isNotEmpty) {
          compileToSingleLayer(_nonRenewableComponents);
          _nonRenewableComponents.clear();
        }
      }
    }
  }

  void _updateTree(double dt) {
    if (doUpdateComponentsPriority) {
      super.updateTree(dt);
    } else {
      _coreUpdateTreeOverride(dt);
      (updateNotifier as ActionNotifier).isActionNeeded = false;
    }
  }

  void _coreUpdateTreeOverride(double dt) {
    lifecycle.processQueues();
    update(dt);
    for (final c in children) {
      c.updateTree(dt);
    }
  }

  @override
  void onRemove() {
    final cell = currentCell;
    if (cell != null) {
      game.layersManager.removeLayer(name: name, cell: cell);
    }
    super.onRemove();
  }

  @override
  void renderTree(Canvas canvas) {
    if (currentCell?.state == CellState.active) {
      decorator.applyChain(render, canvas);
    }
    if (game.isSpatialGridDebugEnabled) {
      children.whereType<GroupHitbox>().forEach((element) {
        decorator.applyChain(element.renderDebugMode, canvas);
      });
    }
  }

  void onChildrenUpdate() {
    if (pauseUpdate) {
      return;
    }
    isUpdateNeeded = true;
  }

  void onBeforeChildrenChanged(Component child, ChildrenChangeType type) {
    if (pauseUpdate) {
      return;
    }

    if (child is UpdateOnDemand) {
      child.isUpdateNeeded = true;
    }
    isUpdateNeeded = true;
  }
}
