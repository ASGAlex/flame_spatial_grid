import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame/rendering.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';
import 'package:flame_clusterizer/src/collisions/collision_optimizer.dart';

class CellStaticLayer extends PositionComponent
    with
        ClusterizedComponent,
        UpdateOnDemand,
        ListenerChildrenUpdate,
        HasGameReference<HasClusterizedCollisionDetection> {
  CellStaticLayer(Cell cell)
      : super(
            position: cell.rect.topLeft.toVector2(),
            size: cell.rect.size.toVector2()) {
    currentCell = cell;
    _collisionOptimizer = CollisionOptimizer(this);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    layerPicture = recorder.endRecording();
  }

  bool _needRepaint = true;

  late Picture layerPicture;
  Image? layerImage;

  bool renderAsImage = true;
  bool optimizeCollisions = false;
  late final CollisionOptimizer _collisionOptimizer;

  final _correctionTopLeft = Vector2.zero();
  final _correctionBottomRight = Vector2.zero();

  @override
  Future<void>? add(Component component) {
    if (component is PositionComponent) {
      if (component.position.x < _correctionTopLeft.x) {
        _correctionTopLeft.x = component.position.x;
      }
      if (component.position.y < _correctionTopLeft.y) {
        _correctionTopLeft.y = component.position.y;
      }

      final bottomRightPosition = component.position + component.size;
      if (bottomRightPosition.x > _correctionBottomRight.x) {
        _correctionBottomRight.x = bottomRightPosition.x;
      }
      if (bottomRightPosition.y > _correctionBottomRight.y) {
        _correctionBottomRight.y = bottomRightPosition.y;
      }
    }
    return super.add(component);
  }

  @override
  void renderTree(Canvas canvas) {
    isVisible = (currentCell?.state == CellState.active ? true : false);
    if (isVisible) {
      decorator.applyChain(render, canvas);
    }
  }

  @override
  void render(Canvas canvas) {
    if (_needRepaint) {
      _renderToPicture();
      _needRepaint = false;
    }
    if (renderAsImage && layerImage != null) {
      canvas.drawImage(layerImage!, _correctionTopLeft.toOffset(), Paint());
    } else {
      canvas.drawPicture(layerPicture);
    }
  }

  void _renderToPicture() async {
    final cell = currentCell;
    if (cell == null) return;

    var recorder = PictureRecorder();
    var canvas = Canvas(recorder);
    final decorator = Transform2DDecorator();
    decorator.transform2d.position = (_correctionTopLeft * -1);
    for (var component in children) {
      if (component is! PositionComponent) continue;
      // final correctedPosition = component.position + (_correction * -1);
      decorator.applyChain(component.renderTree, canvas);
      // component.renderTree(canvas);
    }
    layerPicture = recorder.endRecording();
    if (renderAsImage) {
      var width = cell.rect.width.toInt();
      var height = cell.rect.height.toInt();
      if (_correctionBottomRight != Vector2.zero()) {
        final diff = _correctionBottomRight - _correctionTopLeft;
        width = diff.x.ceil();
        height = diff.y.ceil();
      }
      layerImage = await layerPicture.toImageSafe(width, height);
    }
  }

  @override
  void onChildrenUpdate() {
    _needRepaint = true;
  }

  @override
  void updateTree(double dt) {
    if (isUpdateNeeded) {
      super.updateTree(dt);
      if (optimizeCollisions) {
        _collisionOptimizer.optimize();
        isUpdateNeeded = true;
      }
      super.updateTree(dt);
    }
  }

  @override
  void update(double dt) {
    onChildrenUpdate();
  }
}

mixin ListenerChildrenUpdate on PositionComponent {
  final _listenerChildrenUpdate = <Component, VoidCallback>{};

  void onChildrenUpdate();

  @override
  Future<void>? add(Component component) {
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
    if (this is UpdateOnDemand) {
      (this as UpdateOnDemand).isUpdateNeeded = true;
    }
  }
}
