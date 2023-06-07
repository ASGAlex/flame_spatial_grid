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

  Type? primaryHitboxCollisionType;

  final bool isRenewable;

  @protected
  final nonRenewableComponents = <Component>[];

  @internal
  late final CollisionOptimizer collisionOptimizer;

  @protected
  final correctionTopLeft = Vector2.zero();

  @protected
  final correctionBottomRight = Vector2.zero();

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
      final topLeftPosition = -component.size;
      if (topLeftPosition.x < correctionTopLeft.x) {
        correctionTopLeft.x = topLeftPosition.x;
      }
      if (topLeftPosition.y < correctionTopLeft.y) {
        correctionTopLeft.y = topLeftPosition.y;
      }

      final bottomRightPosition = size + component.size;
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
  FutureOr<void>? add(Component component) async {
    if (primaryHitboxCollisionType == null) {
      if (component is HasGridSupport) {
        primaryHitboxCollisionType = component.boundingBox.runtimeType;
      } else {
        primaryHitboxCollisionType = component.runtimeType;
      }
    }
    if (isRenewable) {
      super.add(component);
    } else {
      onChildrenChanged(component, ChildrenChangeType.added);
    }
  }

  @override
  void remove(Component component, {bool internalCall = false}) {
    if (isRenewable) {
      super.remove(component);
    } else {
      onChildrenChanged(component, ChildrenChangeType.removed);
    }
  }

  @override
  void onChildrenChanged(Component child, ChildrenChangeType type) {
    switch (type) {
      case ChildrenChangeType.added:
        updateCorrections(child);

        if (isRenewable) {
          if (child is HasGridSupport) {
            child.transform.addListener(onChildrenUpdate);
            _listenerChildrenUpdate[child] = onChildrenUpdate;
          }
          if (child is! GroupHitbox) {
            scheduleLayerUpdate(child, ChildrenChangeType.added);
          }
          final future = child.loaded;
          _pendingComponents.add(future);
        } else {
          nonRenewableComponents.add(child);
          if (child is HasGridSupport) {
            child.currentCell = null;
          }
          if (!child.isLoaded) {
            final future = child.onLoad();
            if (future is Future) {
              _pendingComponents.add(future);
            }
          }
        }
        break;
      case ChildrenChangeType.removed:
        if (isRenewable) {
          final callback = _listenerChildrenUpdate.remove(child);
          if (callback != null && child is HasGridSupport) {
            child.transform.removeListener(callback);
          }

          if (child is! GroupHitbox) {
            scheduleLayerUpdate(child, ChildrenChangeType.removed);
          }
        } else {
          nonRenewableComponents.remove(child);
        }
        break;
    }
  }

  Future<void> waitForComponents() => Future.wait<void>(_pendingComponents);

  @override
  void updateTree(double dt) {
    updateLayer(dt);
  }

  Future<void>? _updateLayerFuture;

  Future<void> updateLayer([double dt = 0.001]) {
    if (isUpdateNeeded) {
      if (_updateLayerFuture != null) {
        return Future<void>.value();
      }
      if (isRenewable) {
        super.updateTree(dt);
        _updateLayerFuture = waitForComponents().whenComplete(() async {
          if (isRemovedLayer) {
            return;
          }
          game.processLifecycleEvents();
          if (optimizeCollisions) {
            collisionOptimizer.optimize();
            game.processLifecycleEvents();
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
      !isMounted ||
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
        if (element is GroupHitbox) {
          decorator.applyChain(
            element.renderDebugMode,
            canvas,
          );
        } else if (element is HasGridSupport) {
          decorator.applyChain(
            (canvas) {
              element.decorator.applyChain(
                (canvas) {
                  element.boundingBox.decorator
                      .applyChain(element.boundingBox.renderDebugMode, canvas);
                },
                canvas,
              );
            },
            canvas,
          );
        }
      }
    }
  }

  bool _isUpdateProhibited() {
    final cell = currentCell;
    if (cell == null) {
      return true;
    }

    if (parent == null ||
        isRemoving ||
        isRemoved ||
        cell.isRemoving ||
        !cell.isCellBuildFinished) {
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

  void scheduleLayerUpdate(Component child, ChildrenChangeType type) {
    if (_isUpdateProhibited()) {
      return;
    }

    if (child is UpdateOnDemand) {
      child.isUpdateNeeded = true;
    }
    isUpdateNeeded = true;
  }
}
