import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame/rendering.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/collision_optimizer.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

enum LayerRenderMode {
  component,
  picture,
  image,
  auto,
}

enum LayerComponentsStorageMode {
  defaultComponentTree,
  internalLayerSet,
  removeAfterCompile,
}

mixin LayerCacheKeyProvider on PositionComponent {
  String getComponentUniqueString() => '(${position.x},${position.y})'
      '${this is TileComponent ? (this as TileComponent).tileCache.tile.type ?? runtimeType : runtimeType}'
      '(${size.x},${size.y})';
}

class LayerCacheKey {
  final _data = <String>{};

  void add(Component component) {
    if (component is PositionComponent) {
      _data.add(_componentToString(component));
      _key = null;
    }
  }

  void invalidate() {
    _key = null;
    _data.clear();
  }

  String _componentToString(PositionComponent component) {
    if (component is LayerCacheKeyProvider) {
      return component.getComponentUniqueString();
    } else {
      return '(${component.position.x},${component.position.y})'
          '${component is TileComponent ? component.tileCache.tile.type ?? component.runtimeType : component.runtimeType}'
          '(${component.size.x},${component.size.y})';
    }
  }

  int? _key;

  int? get key => _key ?? _computeKey();

  int? _computeKey() {
    if (_data.isEmpty) {
      return null;
    }
    _key = Object.hashAllUnordered(_data);
    _data.clear();
    return _key;
  }
}

abstract class CellLayer extends PositionComponent
    with
        HasGridSupport,
        UpdateOnDemand,
        HasGameReference<HasSpatialGridFramework> {
  CellLayer(
    Cell cell, {
    this.name = '',
    LayerComponentsStorageMode? componentsStorageMode,
  })  : componentsStorageMode = componentsStorageMode ??
            LayerComponentsStorageMode.defaultComponentTree,
        super(
          position: cell.rect.topLeft.toVector2(),
          size: cell.rect.size.toVector2(),
        ) {
    currentCell = cell;
    collisionOptimizer = CollisionOptimizer(this);
    checkOutOfCellBounds = false;
  }

  bool optimizeCollisions = false;
  LayerRenderMode renderMode = LayerRenderMode.auto;

  final correctionDecorator = Transform2DDecorator();

  Type? primaryHitboxCollisionType;

  final LayerComponentsStorageMode componentsStorageMode;

  @internal
  final alternativeComponentSet = <Component>{};

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

  LayerCacheKey get cacheKey;

  @protected
  FutureOr compileToSingleLayer(Iterable<Component> components);

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
      correctionDecorator.transform2d.position = correctionTopLeft * -1;
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
    if (componentsStorageMode ==
        LayerComponentsStorageMode.defaultComponentTree) {
      super.add(component);
    } else {
      onChildrenChanged(component, ChildrenChangeType.added);
    }
  }

  @override
  void remove(Component component, {bool internalCall = false}) {
    if (componentsStorageMode ==
        LayerComponentsStorageMode.defaultComponentTree) {
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
        if (child is! BoundingHitbox) {
          cacheKey.add(child);
        }
        if (child is LayerChildComponent) {
          child._parentLayer = this;
        }

        switch (componentsStorageMode) {
          case LayerComponentsStorageMode.defaultComponentTree:
            if (child is HasGridSupport) {
              child.transform.addListener(onChildrenUpdate);
              _listenerChildrenUpdate[child] = onChildrenUpdate;
            }
            final future = child.loaded;
            _pendingComponents.add(future);
            break;
          case LayerComponentsStorageMode.internalLayerSet:
            if (!child.isLoaded) {
              final future = child.onLoad();
              if (future is Future) {
                _pendingComponents.add(future);
              }
            }
            alternativeComponentSet.add(child);
            break;
          case LayerComponentsStorageMode.removeAfterCompile:
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
            break;
        }

        if (child is! GroupHitbox) {
          scheduleLayerUpdate(child, ChildrenChangeType.added);
        }

        break;
      case ChildrenChangeType.removed:
        cacheKey.invalidate();

        switch (componentsStorageMode) {
          case LayerComponentsStorageMode.defaultComponentTree:
            final callback = _listenerChildrenUpdate.remove(child);
            if (callback != null && child is HasGridSupport) {
              child.transform.removeListener(callback);
            }
            if (child is! GroupHitbox) {
              scheduleLayerUpdate(child, ChildrenChangeType.removed);
            }
            break;
          case LayerComponentsStorageMode.internalLayerSet:
            alternativeComponentSet.remove(child);
            child.onRemove();
            if (child is! GroupHitbox) {
              scheduleLayerUpdate(child, ChildrenChangeType.removed);
            }
            break;

          case LayerComponentsStorageMode.removeAfterCompile:
            nonRenewableComponents.remove(child);
            break;
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
      if (cacheKey.key != null && onCheckCache(cacheKey.key!)) {
        isUpdateNeeded = false;
        return Future<void>.value();
      }

      switch (componentsStorageMode) {
        case LayerComponentsStorageMode.defaultComponentTree:
          _updateTreePart(dt);
          _updateLayerFuture = waitForComponents().whenComplete(() async {
            if (isRemovedLayer) {
              return;
            }
            game.processLifecycleEvents();
            if (optimizeCollisions) {
              collisionOptimizer.optimize();
              game.processLifecycleEvents();
            }
            if (renderMode != LayerRenderMode.component) {
              await compileToSingleLayer(children);
            }
            _pendingComponents.clear();
            _updateLayerFuture = null;
          });
          break;
        case LayerComponentsStorageMode.internalLayerSet:
          _updateLayerFuture = waitForComponents().whenComplete(() async {
            if (isRemovedLayer) {
              return;
            }
            if (renderMode != LayerRenderMode.component) {
              await compileToSingleLayer(alternativeComponentSet);
            }
            _pendingComponents.clear();
            _updateLayerFuture = null;
          });
          break;
        case LayerComponentsStorageMode.removeAfterCompile:
          final futures =
              List<Future>.from(_pendingComponents, growable: false);
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
          break;
      }
      isUpdateNeeded = false;
    }

    return _updateLayerFuture ?? Future<void>.value();
  }

  void _updateTreePart(double dt) {
    children
        .query<ComponentWithUpdate>()
        .forEach((element) => element.updateTree(dt));
  }

  bool onCheckCache(int key);

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

  @override
  set isUpdateNeeded(bool update) {
    if (update == true && parent is LayersRootComponent) {
      (parent! as LayersRootComponent).isUpdateNeeded = true;
    }
    super.isUpdateNeeded = update;
  }
}

mixin LayerChildComponent on Component {
  CellLayer? _parentLayer;

  @override
  void removeFromParent() {
    if (parent == null) {
      _parentLayer?.remove(this);
    } else {
      super.removeFromParent();
    }
  }

  CellLayer? get parentLayer => _parentLayer;
}
