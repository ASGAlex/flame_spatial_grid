import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/rendering.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class CellTrailLayer extends CellStaticLayer {
  final newComponents = <Component>[];

  CellTrailLayer(super.cell, {super.name, FadeOutConfig? fadeOutConfig}) {
    this.fadeOutConfig = fadeOutConfig ?? FadeOutConfig();
  }

  bool get isFadeOut => fadeOutConfig.isFadeOut;

  late FadeOutConfig fadeOutConfig;

  double _fadeOutDt = 0;
  double _operationsCount = 0;

  bool _imageRenderInProgress = false;

  bool get doFadeOut =>
      _fadeOutDt * 1000000 >= fadeOutConfig.fadeOutTimeout.inMicroseconds;

  @override
  bool get isUpdateNeeded => true;

  @override
  Future<void>? add(Component component) {
    newComponents.add(component);
    updateCorrections(component);
    return null;
  }

  @override
  void remove(Component component) {}

  @override
  Future compileToSingleLayer() async {
    final cell = currentCell;
    if (cell == null) return;

    if (newComponents.isEmpty && !doFadeOut) {
      return;
    }
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    if (doFadeOut) {
      fadeOutConfig.decorator.applyChain(_drawOldPicture, canvas);
      _fadeOutDt = 0;
    } else {
      _drawOldPicture(canvas);
    }

    for (final component in newComponents) {
      if (component is! HasGridSupport) continue;
      component.decorator.applyChain(component.render, canvas);
    }
    newComponents.clear();
    _operationsCount++;
    layerPicture = recorder.endRecording();
    if (_operationsCount >= fadeOutConfig.operationsLimitToSavePicture &&
        _imageRenderInProgress == false) {
      _imageRenderInProgress = true;
      layerPicture
          ?.toImage(layerCalculatedSize.width.toInt(),
              layerCalculatedSize.height.toInt())
          .then((newImage) {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(newImage, const Offset(0, 0), Paint());
        layerPicture = recorder.endRecording();
        _operationsCount = 0;

        _imageRenderInProgress = false;
      });
    } else {
      _imageRenderInProgress = false;
    }
  }

  _drawOldPicture(Canvas canvas) {
    if (layerPicture != null) {
      canvas.drawPicture(layerPicture!);
    }
  }

  @override
  void update(double dt) {
    _fadeOutDt += dt;
    super.update(dt);
  }
}

class FadeOutConfig {
  FadeOutConfig(
      {double transparencyPerStep = 0,
      this.fadeOutTimeout = Duration.zero,
      this.operationsLimitToSavePicture = 50}) {
    this.transparencyPerStep = transparencyPerStep;
  }

  Duration fadeOutTimeout;
  double _transparencyPerStep = 1;

  double get transparencyPerStep => _transparencyPerStep;

  set transparencyPerStep(double value) {
    assert(
        value >= 0 && value <= 1, 'Transparency must be between 0.0 and 1.0');
    _transparencyPerStep = value;
    _fadeOutDecorator.opacity = 1 - value;
  }

  double operationsLimitToSavePicture;

  bool get isFadeOut =>
      transparencyPerStep > 0 && fadeOutTimeout != Duration.zero;

  final _fadeOutDecorator = _FadeOutDecorator();

  Decorator get decorator => _fadeOutDecorator;
}

class _FadeOutDecorator extends Decorator {
  final _paint = Paint();

  double _opacity = 1;

  set opacity(double value) {
    _opacity = value;
    _paint.color = _paint.color.withOpacity(value);
  }

  double get opacity => _opacity;

  @override
  void apply(void Function(Canvas) draw, Canvas canvas) {
    canvas.saveLayer(null, _paint);
    draw(canvas);
    canvas.restore();
  }
}
