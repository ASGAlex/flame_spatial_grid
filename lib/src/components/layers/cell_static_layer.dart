import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class ImageCacheEntry {
  ImageCacheEntry(this.image);

  final Image image;
  int usageCount = 1;
}

class CellStaticLayer extends CellLayer {
  CellStaticLayer(
    super.cell, {
    super.name,
    super.componentsStorageMode,
  }) {
    paint.isAntiAlias = false;
    paint.filterQuality = FilterQuality.none;
  }

  static final _compiledLayersCache = <int, ImageCacheEntry>{};

  final _layerCacheKey = LayerCacheKey();

  @override
  LayerCacheKey get cacheKey => _layerCacheKey;

  Picture? layerPicture;
  Image? layerImage;

  static const secondsBetweenImageUpdate = 5;
  int _millisecondsBetweenImageUpdate = 0;
  bool _renderAsImage = false;

  @override
  void render(Canvas canvas) {
    switch (renderMode) {
      case LayerRenderMode.component:
        if (componentsStorageMode ==
            LayerComponentsStorageMode.internalLayerSet) {
          for (final c in alternativeComponentSet) {
            c.renderTree(canvas);
          }
        } else {
          for (final c in children) {
            c.renderTree(canvas);
          }
        }
        break;
      case LayerRenderMode.picture:
        if (layerPicture != null) {
          canvas.drawPicture(layerPicture!);
        }
        break;
      case LayerRenderMode.image:
        if (layerImage != null) {
          canvas.drawImage(
            layerImage!,
            correctionTopLeft.toOffset(),
            paint,
          );
        }
        break;
      case LayerRenderMode.auto:
        if (_renderAsImage && layerImage != null) {
          canvas.drawImage(
            layerImage!,
            correctionTopLeft.toOffset(),
            paint,
          );
        } else if (layerPicture != null) {
          canvas.drawPicture(layerPicture!);
          if (_millisecondsBetweenImageUpdate == 0) {
            _millisecondsBetweenImageUpdate =
                DateTime.now().millisecondsSinceEpoch;
          } else {
            final msNew = DateTime.now().millisecondsSinceEpoch;
            if ((msNew - _millisecondsBetweenImageUpdate) >=
                secondsBetweenImageUpdate * 1000) {
              _renderPictureToImage();
              _millisecondsBetweenImageUpdate = 0;
            }
          }
        }
        break;
    }
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
  bool onCheckCache(int key) {
    if (renderMode != LayerRenderMode.image) {
      return false;
    }
    final cache = _compiledLayersCache[key];
    if (cache == null) {
      return false;
    }
    layerImage = cache.image;
    cache.usageCount++;
    return true;
  }

  @override
  void compileToSingleLayer(Iterable<Component> components) {
    final renderingChildren = components.whereType<PositionComponent>();
    // if (renderingChildren.isEmpty) {
    //   return;
    // }

    final cell = currentCell;
    if (cell == null) {
      return null;
    }

    _millisecondsBetweenImageUpdate = 0;
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
      // layerImage?.dispose();
      layerImage = newPicture.toImageSync(
        layerCalculatedSize.width.toInt(),
        layerCalculatedSize.height.toInt(),
      );
      if (cacheKey.key != null) {
        _compiledLayersCache[cacheKey.key!] = ImageCacheEntry(layerImage!);
      }
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
      final cachedImage = _compiledLayersCache[cacheKey.key];
      if (cachedImage != null) {
        cachedImage.usageCount--;
        if (cachedImage.usageCount <= 0) {
          // cachedImage.image.dispose();
          _compiledLayersCache.remove(cacheKey.key);
        }
      } else {
        // layerImage?.dispose();
        layerImage = null;
      }
      // layerPicture?.dispose();
      layerPicture = null;

      // ignore: avoid_catches_without_on_clauses, empty_catches
    } catch (e) {}
    super.onRemove();
  }

  static void clearCache() => _compiledLayersCache.clear();
}
