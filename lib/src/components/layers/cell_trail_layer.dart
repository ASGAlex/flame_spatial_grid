import 'dart:collection';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/palette.dart';
import 'package:flame/rendering.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class CellTrailLayer extends CellStaticLayer {
  static final _instances = HashMap<Cell, CellTrailLayer>();

  static updateTrailsCounter(double dt) {
    var c = 0;
    for (final layer in _instances.values) {
      if (!layer.isVisible) {
        layer._dtElapsedWhileInvisible += dt;
        continue;
      }
      c++;
      if (layer.newComponents.isNotEmpty) {
        layer.isUpdateNeeded = true;
      }
      final fadeOutStep = layer._fadeOutStep;
      if (fadeOutStep == null) continue;
      final fadeOutTimeout = layer.fadeOutTimeout?.inMicroseconds;
      if (fadeOutTimeout == null) continue;
      if (layer._dtElapsedWhileInvisible != 0) {
        layer._dtSumBetweenFadeOut += (dt + layer._dtElapsedWhileInvisible);
        layer._dtElapsedWhileInvisible = 0;
      } else {
        layer._dtSumBetweenFadeOut += dt;
      }
      if (layer._dtSumBetweenFadeOut * 1000000 >= fadeOutTimeout) {
        layer._doFadeOutSteps =
            (layer._dtSumBetweenFadeOut * 1000000) / fadeOutTimeout;
        layer._dtSumBetweenFadeOut = 0;
        layer._doFadeOut = true;
        if (!layer.isUpdateNeeded) {
          layer.isUpdateNeeded = true;
        }
      }
    }
    // print(c);
  }

  static CellTrailLayer? getLayerForCell(Cell cell) => _instances[cell];

  CellTrailLayer(super.cell, {double? fadeOutStep, this.fadeOutTimeout}) {
    this.fadeOutStep = fadeOutStep;
  }

  var componentsSaveToImageTreshold = 20;
  var _componentsCounter = 0;
  Duration? fadeOutTimeout;
  double _dtSumBetweenFadeOut = 0;
  double? _fadeOutStep;
  double _doFadeOutSteps = 0;

  double? get fadeOutStep => _fadeOutStep;

  bool _renderInProgress = false;
  bool _doFadeOut = false;

  final newComponents = <Component>[];

  set fadeOutStep(double? value) {
    _fadeOutStep = value;
    if (value != null) {
      paint.isAntiAlias = false;
      paint.color = paint.color.withOpacity(value);
    }
  }

  double _dtElapsedWhileInvisible = 0;

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

  @override
  bool get renderAsImage => false;

  Picture? _drawNewComponents() {
    if (newComponents.isEmpty) return null;
    var recorder = PictureRecorder();
    var canvas = Canvas(recorder);

    final transparentPaint = BasicPalette.transparent.paint();
    canvas.drawPaint(transparentPaint);
    final decorator = Transform2DDecorator();
    decorator.transform2d.position = (correctionTopLeft * -1);
    for (final component in newComponents) {
      if (component is! HasGridSupport) continue;
      decorator.applyChain((canvas) {
        component.decorator.applyChain(component.render, canvas);
      }, canvas);
    }
    _componentsCounter += newComponents.length;
    newComponents.clear();
    final picture = recorder.endRecording();
    return picture;
  }

  @override
  Future compileToSingleLayer() async {
    if (!isVisible) {
      return;
    }
    final cell = currentCell;
    if (cell == null) return;

    if (_renderInProgress) return;
    if (layerPicture == null) return;
    _renderInProgress = true;

    final pictureUpdate = _drawNewComponents();

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    final transparentPaint = BasicPalette.transparent.paint();
    canvas.drawPaint(transparentPaint);

    var oldPictureNotRendered = true;
    if (_doFadeOut) {
      var selectedPaint;
      final fos = fadeOutStep;
      if (_doFadeOutSteps > 1 && fos != null) {
        selectedPaint = BasicPalette.white.paint()..isAntiAlias = false;
        selectedPaint.color =
            selectedPaint.color.withOpacity(fos / _doFadeOutSteps);
        _doFadeOutSteps = 0;
      } else {
        selectedPaint = paint;
      }
      canvas.saveLayer(null, selectedPaint);
      canvas.drawPaint(transparentPaint);
      canvas.drawPicture(layerPicture!);
      canvas.restore();
      _doFadeOut = false;
      oldPictureNotRendered = false;
    }

    if (pictureUpdate != null) {
      if (oldPictureNotRendered) {
        canvas.drawPicture(layerPicture!);
      }
      canvas.drawPicture(pictureUpdate);
    }

    layerPicture = recorder.endRecording();
    pictureUpdate?.dispose();

    if (_componentsCounter >= componentsSaveToImageTreshold ||
        !oldPictureNotRendered) {
      _componentsCounter = 0;
      layerPicture
          ?.toImageSafe(layerCalculatedSize.width.toInt() + 10,
              layerCalculatedSize.height.toInt() + 10)
          .then((updatedImage) {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);

        final transparentPaint = BasicPalette.transparent.paint();
        canvas.drawPaint(transparentPaint);
        canvas.drawImage(updatedImage, const Offset(0, 0), Paint());
        layerPicture = recorder.endRecording();
        _renderInProgress = false;
      });
    } else {
      _renderInProgress = false;
    }
  }

  @override
  Future<void>? add(Component component) {
    newComponents.add(component);
    return null;
  }

  @override
  void remove(Component component) {}
}
