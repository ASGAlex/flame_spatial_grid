import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class CellStaticLayer extends CellLayer {
  CellStaticLayer(super.cell, {super.name, super.isRenewable}) {
    paint.isAntiAlias = false;
    paint.filterQuality = FilterQuality.none;
  }

  final paint = Paint();
  Picture? layerPicture;
  Image? layerImage;

  static const secondsBetweenImageUpdate = 5;
  double _dtBetweenImageUpdate = 0;
  bool _renderAsImage = false;

  @override
  void render(Canvas canvas) {
    switch (renderMode) {
      case LayerRenderMode.component:
        for (final c in children) {
          c.renderTree(canvas);
        }
        break;
      case LayerRenderMode.picture:
        if (layerPicture != null) {
          canvas.drawPicture(layerPicture!);
        }
        break;
      case LayerRenderMode.image:
        if (layerImage != null) {
          canvas.drawImage(layerImage!, correctionTopLeft.toOffset(), paint);
        }
        break;
      case LayerRenderMode.auto:
        if (_renderAsImage && layerImage != null) {
          canvas.drawImage(layerImage!, correctionTopLeft.toOffset(), paint);
        } else if (layerPicture != null) {
          canvas.drawPicture(layerPicture!);
        }
        break;
    }
  }

  @override
  Future<void> updateLayer([double dt = 0.001]) {
    if (renderMode == LayerRenderMode.auto && !isUpdateNeeded) {
      if (!_renderAsImage &&
          _dtBetweenImageUpdate >= secondsBetweenImageUpdate) {
        _renderPictureToImage();
      } else {
        _dtBetweenImageUpdate++;
      }
    }
    return super.updateLayer(dt);
  }

  void _renderPictureToImage() {
    if (layerPicture != null) {
      _renderAsImage = true;
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      correctionDecorator.applyChain(
        (canvas) {
          canvas.drawPicture(layerPicture!);
        },
        canvas,
      );
      layerImage = recorder.endRecording().toImageSync(
            layerCalculatedSize.width.toInt(),
            layerCalculatedSize.height.toInt(),
          );
    }
  }

  @override
  FutureOr compileToSingleLayer(Iterable<Component> children) {
    final renderingChildren = children.whereType<HasGridSupport>();
    if (renderingChildren.isEmpty) {
      return null;
    }

    final cell = currentCell;
    if (cell == null) {
      return null;
    }

    _dtBetweenImageUpdate = 0;
    _renderAsImage = false;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    if (renderMode == LayerRenderMode.image) {
      for (final component in renderingChildren) {
        correctionDecorator.applyChain(
          (canvas) {
            component.decorator.applyChain(component.render, canvas);
          },
          canvas,
        );
      }
      final newPicture = recorder.endRecording();
      layerImage?.dispose();
      layerImage = newPicture.toImageSync(
        layerCalculatedSize.width.toInt(),
        layerCalculatedSize.height.toInt(),
      );
      newPicture.dispose();
    } else if (renderMode == LayerRenderMode.picture ||
        renderMode == LayerRenderMode.auto) {
      for (final component in renderingChildren) {
        component.decorator.applyChain(component.render, canvas);
      }
      layerPicture?.dispose();
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
