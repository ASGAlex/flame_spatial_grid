import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/rendering.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class CellStaticLayer extends CellLayer {
  CellStaticLayer(super.cell, {super.name, super.isRenewable}) {
    paint.isAntiAlias = false;
    paint.filterQuality = FilterQuality.none;
  }

  final paint = Paint();
  Picture? layerPicture;
  Image? layerImage;

  bool renderAsImage = false;

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
  Future compileToSingleLayer(Iterable<Component> children) async {
    final renderingChildren =
        children.whereType<HasGridSupport>().toList(growable: false);
    if (renderingChildren.isEmpty) {
      removeFromParent();
      return;
    }

    final cell = currentCell;
    if (cell == null) {
      return;
    }

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    if (renderAsImage) {
      final decorator = Transform2DDecorator();
      decorator.transform2d.position = correctionTopLeft * -1;
      for (final component in renderingChildren) {
        decorator.applyChain(
          (canvas) {
            component.decorator.applyChain(component.render, canvas);
          },
          canvas,
        );
      }
      layerPicture = recorder.endRecording();
      layerImage = layerPicture?.toImageSync(
        layerCalculatedSize.width.toInt(),
        layerCalculatedSize.height.toInt(),
      );
      layerPicture?.dispose();
      layerPicture = null;
    } else {
      for (final component in renderingChildren) {
        component.decorator.applyChain(component.render, canvas);
      }
      layerPicture = recorder.endRecording();
    }
  }

  @override
  void onResume(double dtElapsedWhileSuspended) {
    // isUpdateNeeded = true;
    super.onResume(dtElapsedWhileSuspended);
  }

  @override
  void onRemove() {
    try {
      layerImage?.dispose();
      layerPicture?.dispose();
      // ignore: avoid_catches_without_on_clauses, empty_catches
    } catch (e) {}
    layerImage = null;
    layerPicture = null;
    super.onRemove();
  }
}
