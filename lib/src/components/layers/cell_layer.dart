import 'dart:async';
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
          size: cell.rect.size.toVector2(),
        ) {
    currentCell = cell;
    collisionOptimizer = CollisionOptimizer(this);
  }

  bool optimizeCollisions = false;
  bool optimizeGraphics = true;

  final bool isRenewable;

  @protected
  final nonRenewableComponents = <Component>[];

  @internal
  late final CollisionOptimizer collisionOptimizer;

  @protected
  final correctionTopLeft = Vector2.zero();

  @protected
  final correctionBottomRight = Vector2.zero();

  set persistentCorrection(double value) {
    correctionTopLeft.x = -value;
    correctionTopLeft.y = -value;
    correctionBottomRight.x = size.x + value;
    correctionBottomRight.y = size.y + value;
  }

  final _listenerChildrenUpdate = <Component, VoidCallback>{};

  final _pendingComponents = <Future>[];

  @protected
  FutureOr compileToSingleLayer(Iterable<Component> children);

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
  FutureOr<void>? add(Component component, {bool internalCall = false}) async {
    updateCorrections(component);

    if (isRenewable) {
      if (component is HasGridSupport) {
        component.transform.addListener(onChildrenUpdate);
        _listenerChildrenUpdate[component] = onChildrenUpdate;
      }
      if (!internalCall) {
        onBeforeChildrenChanged(component, ChildrenChangeType.added);
      }
      final future = component.loaded;
      _pendingComponents.add(future);
      super.add(component);
      return future;
    } else {
      nonRenewableComponents.add(component);
      if (component is HasGridSupport) {
        component.currentCell = null;
      }
      if (!component.isLoaded) {
        final future = component.onLoad();
        if (future is Future) {
          _pendingComponents.add(future);
        }
        return future;
      }
    }
  }

  @override
  void remove(Component component, {bool internalCall = false}) {
    if (isRenewable) {
      final callback = _listenerChildrenUpdate.remove(component);
      if (callback != null && component is HasGridSupport) {
        component.transform.removeListener(callback);
      }

      if (!internalCall) {
        onBeforeChildrenChanged(component, ChildrenChangeType.removed);
      }
      super.remove(component);
    } else {
      nonRenewableComponents.remove(component);
    }
  }

  Future<void> waitForComponents() => Future.wait<void>(_pendingComponents);

  @override
  void updateTree(double dt) {
    updateLayer();
  }

  Future<void>? _updateLayerFuture;

  Future<void> updateLayer() {
    if (isUpdateNeeded) {
      if (_updateLayerFuture != null) {
        return Future<void>.value();
      }
      if (isRenewable) {
        _updateLayerFuture = waitForComponents().whenComplete(() async {
          if (isRemovedLayer) {
            return;
          }
          processQueuesTree();
          if (optimizeCollisions) {
            collisionOptimizer.optimize();
            processQueuesTree();
          }
          if (optimizeGraphics) {
            await compileToSingleLayer(children);
          }
          _pendingComponents.clear();
          _updateLayerFuture = null;
        });
      } else {
        final futures = List<Future>.from(_pendingComponents, growable: false);
        _pendingComponents.clear();
        _updateLayerFuture = Future.wait<void>(futures).whenComplete(() {
          if (isRemovedLayer) {
            return;
          }
          final result = compileToSingleLayer(nonRenewableComponents);
          if (result is Future) {
            result.whenComplete(
              () {
                nonRenewableComponents.clear();
                _updateLayerFuture = null;
              },
            );
          } else {
            nonRenewableComponents.clear();
            _updateLayerFuture = null;
          }
        });
      }
      isUpdateNeeded = false;
    }

    return _updateLayerFuture ?? Future<void>.value();
  }

  bool get isRemovedLayer =>
      isRemoving ||
      isRemoved ||
      currentCell == null ||
      // ignore: use_if_null_to_convert_nulls_to_bools
      currentCell?.isRemoving == true;

  @override
  void onRemove() {
    final cell = currentCell;
    if (cell != null) {
      game.layersManager.removeLayer(name: name, cell: cell);
    }
    if (_updateLayerFuture != null) {
      _updateLayerFuture!.ignore();
      _updateLayerFuture = null;
    }

    //needed for removing listeners
    for (final component in children) {
      final callback = _listenerChildrenUpdate.remove(component);
      if (callback != null && component is PositionComponent) {
        component.transform.removeListener(callback);
      }
    }
    _pendingComponents.clear();
    collisionOptimizer.clear();
    super.onRemove();
  }

  @override
  void renderTree(Canvas canvas) {
    if (currentCell?.state == CellState.active) {
      decorator.applyChain(render, canvas);
    }
    if (game.isSpatialGridDebugEnabled) {
      for (final element in children) {
        if (element is! GroupHitbox) {
          continue;
        }
        decorator.applyChain(element.renderDebugMode, canvas);
      }
    }
  }

  bool _isUpdateProhibited() {
    final cell = currentCell;
    if (cell == null) {
      return true;
    }

    if (cell.isRemoving || !cell.isCellBuildFinished) {
      return true;
    }

    return false;
  }

  void onChildrenUpdate() {
    if (_isUpdateProhibited()) {
      return;
    }
    isUpdateNeeded = true;
  }

  void onBeforeChildrenChanged(Component child, ChildrenChangeType type) {
    if (_isUpdateProhibited()) {
      return;
    }

    if (child is UpdateOnDemand) {
      child.isUpdateNeeded = true;
    }
    isUpdateNeeded = true;
  }
}
