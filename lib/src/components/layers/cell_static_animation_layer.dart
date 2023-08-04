import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/image_composition.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class StaticAnimationLayerCacheEntry {
  StaticAnimationLayerCacheEntry(this.animationComponent);

  SpriteAnimationGlobalComponent animationComponent;
  int usageCount = 1;
}

class CellStaticAnimationLayer extends CellLayer {
  CellStaticAnimationLayer(super.cell, {super.name, super.isRenewable});

  SpriteAnimationGlobalComponent? animationComponent;

  static final _compiledLayersCache = <int, StaticAnimationLayerCacheEntry>{};

  @override
  void render(Canvas canvas) {
    animationComponent?.renderTree(canvas);
    if (debugMode) {
      renderDebugMode(canvas);
      for (final child in children) {
        if (child.debugMode) {
          child.renderTree(canvas);
        }
      }
    }
  }

  @override
  FutureOr compileToSingleLayer(Iterable<Component> children) {
    final animatedChildren = children.whereType<SpriteAnimationComponent>();
    if (animatedChildren.isEmpty) {
      removeFromParent();
      return null;
    }

    final animation = animatedChildren.first.animation;
    final ticker = animation?.createTicker();
    if (animation == null || ticker == null) {
      return null;
    }

    animationComponent?.playing = false;
    animationComponent?.removeFromParent();

    final newSprites = <Sprite>[];

    while (ticker.currentIndex < animation.frames.length) {
      final sprite = ticker.getSprite();
      final composition = ImageComposition();
      for (final component in animatedChildren) {
        final correctedPosition = component.position + (correctionTopLeft * -1);
        composition.add(sprite.image, correctedPosition, source: sprite.src);
      }
      final composedImage = composition.composeSync();
      newSprites.add(Sprite(composedImage));
      ticker.currentIndex++;
    }
    final spriteAnimation = SpriteAnimation.variableSpriteList(
      newSprites,
      stepTimes: animation.getVariableStepTimes(),
    );
    animationComponent = SpriteAnimationGlobalComponent(
      animation: spriteAnimation,
      position: correctionTopLeft,
      size: newSprites.first.image.size,
      animationType: name,
      tickersProvider: game.tickersManager,
    );
    if (cacheKey.key != null) {
      _compiledLayersCache[cacheKey.key!] =
          StaticAnimationLayerCacheEntry(animationComponent!);
    }
  }

  @override
  void onResume(double dtElapsedWhileSuspended) {
    // isUpdateNeeded = true;
    super.onResume(dtElapsedWhileSuspended);
  }

  @override
  void onRemove() {
    final cachedImage = _compiledLayersCache[cacheKey.key];
    if (cachedImage != null) {
      cachedImage.usageCount--;
      if (cachedImage.usageCount <= 0) {
        _disposeAnimationComponent(cachedImage.animationComponent);
        _compiledLayersCache.remove(cacheKey.key);
      }
      animationComponent = null;
    } else if (animationComponent != null) {
      _disposeAnimationComponent(animationComponent!);
      animationComponent = null;
    }
    super.onRemove();
  }

  void _disposeAnimationComponent(
    SpriteAnimationGlobalComponent animationComponent,
  ) {
    final frames = animationComponent.animation?.frames;
    if (frames != null) {
      try {
        for (final element in frames) {
          element.sprite.image.dispose();
        }
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
    animationComponent.onRemove();
  }

  @override
  bool onCheckCache(int key) {
    final cache = _compiledLayersCache[key];
    if (cache == null) {
      return false;
    }
    animationComponent = cache.animationComponent;
    cache.usageCount++;
    print('${name}: ${cache.usageCount}');

    return true;
  }

  static void clearCache() => _compiledLayersCache.clear();
}

extension _VariableStepTimes on SpriteAnimation {
  List<double> getVariableStepTimes() {
    final times = <double>[];
    for (final frame in frames) {
      times.add(frame.stepTime);
    }
    return times;
  }
}
