import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/palette.dart';
import 'package:flame/rendering.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class CellStaticLayer extends CellLayer {
  CellStaticLayer(super.cell, [super.name]) {
    layerPicture = _getEmptyPicture();
    paint.isAntiAlias = false;
  }

  final paint = Paint();
  Picture? layerPicture;
  Image? layerImage;

  bool renderAsImage = true;

  Picture _getEmptyPicture() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final transparentPaint = BasicPalette.transparent.paint();
    canvas.drawPaint(transparentPaint);
    return recorder.endRecording();
  }

  @override
  void render(Canvas canvas) {
    if (renderAsImage && layerImage != null) {
      canvas.drawImage(layerImage!, correctionTopLeft.toOffset(), paint);
    } else {
      if (layerPicture != null) {
        canvas.drawPicture(layerPicture!);
      }
    }
  }

  @override
  Future compileToSingleLayer() async {
    final cell = currentCell;
    if (cell == null) return;

    var recorder = PictureRecorder();
    var canvas = Canvas(recorder);
    if (renderAsImage) {
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
    } else {
      for (final component in children) {
        if (component is! HasGridSupport) continue;
        component.decorator.applyChain(component.render, canvas);
      }
      layerPicture = recorder.endRecording();
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
    mapLoader?.layers.remove(currentCell);
    super.onRemove();
  }
}
