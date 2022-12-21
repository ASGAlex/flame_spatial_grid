import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/rendering.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class CellStaticLayer extends CellLayer {
  CellStaticLayer(super.cell, [super.mapLoader]) {
    layerPicture = _getEmptyPicture();
  }

  Picture? layerPicture;
  Image? layerImage;

  bool renderAsImage = true;

  Picture _getEmptyPicture() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    return recorder.endRecording();
  }

  @override
  void render(Canvas canvas) {
    if (renderAsImage && layerImage != null) {
      canvas.drawImage(layerImage!, correctionTopLeft.toOffset(), Paint());
    } else {
      if (layerPicture != null) {
        canvas.drawPicture(layerPicture!);
      }
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
    for (final component in children) {
      if (component is! HasGridSupport) continue;
      decorator.applyChain((canvas) {
        component.decorator.applyChain(component.render, canvas);
      }, canvas);
    }
    layerPicture = recorder.endRecording();
    if (renderAsImage) {
      layerImage = await layerPicture?.toImageSafe(
          layerCalculatedSize.width.toInt(),
          layerCalculatedSize.height.toInt());
    }
  }

  @override
  void onResume(double dtElapsedWhileSuspended) {
    isUpdateNeeded = true;
    super.onResume(dtElapsedWhileSuspended);
  }

  @override
  void onRemove() {
    try {
      layerImage?.dispose();
      layerPicture?.dispose();
    } catch (e) {}
    layerImage = null;
    layerPicture = null;
    mapLoader?.staticLayers.remove(currentCell);
    super.onRemove();
  }
}
