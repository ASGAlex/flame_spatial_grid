import 'dart:collection';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/rendering.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class CellTrailLayer extends CellStaticLayer {
  final newComponents = <Component>[];
  static final _instances = HashMap<Cell, CellTrailLayer>();

  static CellTrailLayer? getLayerForCell(Cell cell) => _instances[cell];

  CellTrailLayer(super.cell,
      {double fadeOutOpacity = 1, this.fadeOutTimeout = Duration.zero}) {
    _fadeOutDecorator.opacity = fadeOutOpacity;
  }

  bool get isFadeOut => fadeOutOpacity < 1 && fadeOutTimeout != Duration.zero;

  double get fadeOutOpacity => _fadeOutDecorator.opacity;

  set fadeOutOpacity(value) {
    _fadeOutDecorator.opacity = value;
  }

  Duration fadeOutTimeout;
  double _fadeOutDt = 0;

  double _operationsLimitToSavePicture = 50;
  double _operationsCount = 0;

  bool _imageRrenderInProgress = false;

  bool get doFadeOut => _fadeOutDt * 1000000 >= fadeOutTimeout.inMicroseconds;

  final _fadeOutDecorator = _FadeOutDecorator();

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
      _fadeOutDecorator.applyChain(_drawOldPicture, canvas);
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
    if (_operationsCount >= _operationsLimitToSavePicture &&
        _imageRrenderInProgress == false) {
      _imageRrenderInProgress = true;
      layerPicture
          ?.toImage(layerCalculatedSize.width.toInt(),
              layerCalculatedSize.height.toInt())
          .then((newImage) {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(newImage, correctionTopLeft.toOffset(), Paint());
        layerPicture = recorder.endRecording();
        print('save: $_operationsCount');
        _operationsCount = 0;

        _imageRrenderInProgress = false;
      });
    } else {
      _imageRrenderInProgress = false;
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

  @override
  void onMount() {
    final cell = currentCell;
    if (cell != null) {
      _instances[cell] = this;
    }
    super.onMount();
  }

  @override
  void onRemove() {
    _instances.remove(this);
    super.onRemove();
  }
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
