import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/rendering.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';

class CellStaticLayer extends CellLayer {
  CellStaticLayer(super.cell) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    layerPicture = recorder.endRecording();
  }

  late Picture layerPicture;
  Image? layerImage;

  bool renderAsImage = true;

  @override
  void render(Canvas canvas) {
    if (renderAsImage && layerImage != null) {
      canvas.drawImage(layerImage!, correctionTopLeft.toOffset(), Paint());
    } else {
      canvas.drawPicture(layerPicture);
    }
  }

  @override
  void compileToSingleLayer() async {
    final cell = currentCell;
    if (cell == null) return;

    var recorder = PictureRecorder();
    var canvas = Canvas(recorder);
    final decorator = Transform2DDecorator();
    decorator.transform2d.position = (correctionTopLeft * -1);
    for (var component in children) {
      if (component is! ClusterizedComponent) continue;
      final originalVisibility = component.isVisible;
      component.isVisible = true;
      decorator.applyChain(component.renderTree, canvas);
      component.isVisible = originalVisibility;
    }
    layerPicture = recorder.endRecording();
    if (renderAsImage) {
      layerImage = await layerPicture.toImageSafe(
          layerCalculatedSize.width.toInt(),
          layerCalculatedSize.height.toInt());
    }
  }
}
