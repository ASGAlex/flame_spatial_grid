import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/rendering.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class _FalseCacheKey extends LayerCacheKey {
  @override
  int? get key => null;

  @override
  void add(Component component) {}

  @override
  void invalidate() {}
}

class CellTrailLayer extends CellStaticLayer {
  CellTrailLayer(
    super.cell, {
    super.name,
    FadeOutConfig? fadeOutConfig,
  }) : super(
          componentsStorageMode: LayerComponentsStorageMode.removeAfterCompile,
        ) {
    this.fadeOutConfig = fadeOutConfig ?? FadeOutConfig();
  }

  final _falseCacheKey = _FalseCacheKey();

  @override
  LayerCacheKey get cacheKey => _falseCacheKey;

  bool get isFadeOut => fadeOutConfig.isFadeOut;

  /// This opacity level is barely visible so there is no reason to keep image
  /// in memory
  bool get noTrail => _calculatedOpacity < 0.01;

  late FadeOutConfig fadeOutConfig;

  double _calculatedOpacity = 1;
  double _fadeOutDt = 0;
  double _operationsCount = 0;

  bool _imageRenderInProgress = false;

  bool get doFadeOut =>
      fadeOutConfig.isFadeOut &&
      _fadeOutDt * 1000000 >= fadeOutConfig.fadeOutTimeout.inMicroseconds;

  @override
  void remove(Component component, {bool internalCall = false}) {}

  @override
  FutureOr<void>? add(Component component) {
    if (component is HasTrailSupport) {
      component.addedToTrailLayer = true;
    }
    return super.add(component);
  }

  @override
  void compileToSingleLayer(Iterable<Component> components) {
    if (isRemovedLayer) {
      return;
    }
    final cell = currentCell;
    if (cell == null) {
      return;
    }

    if (noTrail && nonRenewableComponents.isEmpty) {
      isUpdateNeeded = false;
      return;
    }
    if (_imageRenderInProgress) {
      return;
    }
    _imageRenderInProgress = true;
    _updateLayerPictureWithFade();
    final newComponentsPicture = _drawNewComponents();

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    if (layerPicture != null) {
      canvas.drawPicture(layerPicture!);
    }
    canvas.drawPicture(newComponentsPicture);
    newComponentsPicture.dispose();

    layerPicture?.dispose();
    layerPicture = recorder.endRecording();
    if (_operationsCount >= fadeOutConfig.operationsLimitToSavePicture) {
      final imageSize = layerCalculatedSize;
      var recorder = PictureRecorder();
      var canvas = Canvas(recorder);
      final decorator = Transform2DDecorator();
      decorator.transform2d.position = correctionTopLeft * -1;
      decorator.applyChain(
        (canvas) {
          canvas.drawPicture(layerPicture!);
        },
        canvas,
      );
      final newPicture = recorder.endRecording();
      final newImage = newPicture.toImageSync(
        imageSize.width.toInt(),
        imageSize.height.toInt(),
      );
      newPicture.dispose();

      recorder = PictureRecorder();
      canvas = Canvas(recorder);
      canvas.drawImage(newImage, correctionTopLeft.toOffset(), paint);
      layerPicture!.dispose();
      layerPicture = recorder.endRecording();
      newImage.dispose();
      if (renderMode == LayerRenderMode.image) {
        layerImage = layerPicture!.toImageSync(
          imageSize.width.toInt() + correctionTopLeft.x.ceil(),
          imageSize.height.toInt() + correctionTopLeft.y.ceil(),
        );
      }
      _operationsCount = 0;
    }
    _imageRenderInProgress = false;
  }

  void _updateLayerPictureWithFade() {
    if (!doFadeOut) {
      return;
    }
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final fadeOutDecorator =
        fadeOutConfig.createDecorator(_fadeOutDt) as _FadeOutDecorator;
    _calculatedOpacity = _calculatedOpacity * fadeOutDecorator.opacity;

    fadeOutDecorator.applyChain(_drawOldPicture, canvas);

    _fadeOutDt = 0;
    layerPicture = recorder.endRecording();
  }

  Picture _drawNewComponents() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    if (nonRenewableComponents.isNotEmpty) {
      for (final component in nonRenewableComponents) {
        if (component is! PositionComponent || component is BoundingHitbox) {
          component.removeFromParent();
          continue;
        }
        if (component is HasTrailSupport) {
          component.renderCalledFromTrailLayer = true;
          component.decorator.applyChain(component.render, canvas);
          component.renderCalledFromTrailLayer = false;
        } else {
          component.decorator.applyChain(component.render, canvas);
        }
        component.removeFromParent();
      }
      _calculatedOpacity = 1;
    }
    nonRenewableComponents.clear();
    _operationsCount++;
    return recorder.endRecording();
  }

  @override
  void render(Canvas canvas) {
    if (layerPicture != null && !noTrail) {
      canvas.drawPicture(layerPicture!);
    }
    if (debugMode) {
      _renderDebugCell(canvas);
    }
  }

  void _renderDebugCell(Canvas canvas) {
    final cell = currentCell;
    if (cell == null) {
      return;
    }
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(
      rect,
      Paint()..color = const Color.fromRGBO(255, 255, 255, 0.2),
    );
  }

  void _drawOldPicture(Canvas canvas) {
    if (layerPicture != null) {
      canvas.drawPicture(layerPicture!);
    }
  }

  @override
  void updateTree(double dt) {
    if (nonRenewableComponents.isNotEmpty) {
      isUpdateNeeded = true;
      updateLayer(dt);
      return;
    }

    if (noTrail) {
      if (layerPicture != null) {
        layerPicture!.dispose();
        layerPicture = null;
      }
      if (layerImage != null) {
        layerImage!.dispose();
        layerImage = null;
      }
      return;
    }

    if (fadeOutConfig.isFadeOut) {
      _fadeOutDt += dt;
      isUpdateNeeded = true;
      if (doFadeOut) {
        updateLayer(dt);
      }
    }
  }

  @override
  void onResume(double dtElapsedWhileSuspended) {
    _fadeOutDt += dtElapsedWhileSuspended;
    isUpdateNeeded = true;
  }

  @override
  bool onCheckCache(int key) => false;
}

class FadeOutConfig {
  FadeOutConfig({
    double transparencyPerStep = 0,
    this.fadeOutTimeout = Duration.zero,
    this.operationsLimitToSavePicture = 3,
  }) {
    this.transparencyPerStep = transparencyPerStep;
  }

  Duration fadeOutTimeout;
  double _transparencyPerStep = 1;

  double get transparencyPerStep => _transparencyPerStep;

  set transparencyPerStep(double value) {
    assert(
      value >= 0 && value <= 1,
      'Transparency must be between 0.0 and 1.0',
    );
    _transparencyPerStep = value;
  }

  double operationsLimitToSavePicture;

  bool get isFadeOut =>
      transparencyPerStep > 0 && fadeOutTimeout != Duration.zero;

  Decorator createDecorator(double dt) {
    final steps = (dt * 1000000) / fadeOutTimeout.inMicroseconds;
    final opacity = 1 - transparencyPerStep * steps;
    return _FadeOutDecorator(opacity, steps);
  }
}

class _FadeOutDecorator extends Decorator {
  _FadeOutDecorator(double opacity, this.steps) {
    this.opacity = opacity;
    _paint.isAntiAlias = false;
    _paint.filterQuality = FilterQuality.none;
  }

  final _paint = Paint();

  double _opacity = 1;
  final double steps;

  set opacity(double value) {
    if (value <= 0) {
      _opacity = 0;
    } else {
      _opacity = value;
    }
    _paint.color = _paint.color.withOpacity(_opacity);
  }

  double get opacity => _opacity;

  @override
  void apply(void Function(Canvas) draw, Canvas canvas) {
    canvas.saveLayer(null, _paint);
    draw(canvas);
    canvas.restore();
  }
}
