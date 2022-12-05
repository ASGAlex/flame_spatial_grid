import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';

class CellStaticLayer extends PositionComponent
    with ClusterizedComponent, UpdateOnDemand, ListenerChildrenUpdate {
  CellStaticLayer(Cell cell)
      : super(
            position: cell.rect.topLeft.toVector2(),
            size: cell.rect.size.toVector2()) {
    currentCell = cell;
    cell.components.add(this);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    layerPicture = recorder.endRecording();
  }

  bool _needRepaint = true;

  late Picture layerPicture;

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
    canvas.drawPicture(layerPicture);
  }

  void _renderToPicture() {
    final cell = currentCell;
    if (cell == null) return;

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    for (var component in children) {
      component.renderTree(canvas);
    }
    layerPicture = recorder.endRecording();
  }

  @override
  void onChildrenUpdate() {
    _needRepaint = true;
  }
}

mixin ListenerChildrenUpdate on PositionComponent {
  final _listenerChildrenUpdate = <Component, VoidCallback>{};

  void onChildrenUpdate();

  @override
  Future<void>? add(Component component) {
    if (component is ClusterizedComponent) {
      // ignore: no_leading_underscores_for_local_identifiers
      _onChildrenUpdate() {
        if (component.isMounted) {
          onChildrenUpdate();
        }
      }

      if (component is RepaintOnDemand) {
        component.repaintNotifier.addListener(_onChildrenUpdate);
      } else {
        component.transform.addListener(_onChildrenUpdate);
      }
      _listenerChildrenUpdate[component] = _onChildrenUpdate;
    }
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
    super.remove(component);
  }
}
