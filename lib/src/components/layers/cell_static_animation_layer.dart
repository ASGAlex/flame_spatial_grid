import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/image_composition.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/components/layers/image_composition.dart';

class CellStaticAnimationLayer extends CellLayer {
  CellStaticAnimationLayer(super.cell, {super.name, super.isRenewable});

  SpriteAnimationGlobalComponent? animationComponent;

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
    final animatedChildren =
        children.whereType<SpriteAnimationComponent>().toList(growable: false);
    if (animatedChildren.isEmpty) {
      removeFromParent();
      return null;
    }

    final animation = animatedChildren.first.animation?.clone();
    if (animation == null) {
      return null;
    }

    animationComponent?.playing = false;
    animationComponent?.removeFromParent();

    final newSprites = <Sprite>[];

    while (animation.currentIndex < animation.frames.length) {
      final sprite = animation.getSprite();
      final composition = ImageCompositionExt();
      for (final component in animatedChildren) {
        final correctedPosition = component.position + (correctionTopLeft * -1);
        composition.add(sprite.image, correctedPosition, source: sprite.src);
      }
      final composedImage = composition.compose();
      newSprites.add(Sprite(composedImage));
      animation.currentIndex++;
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
    );
  }

  @override
  void onResume(double dtElapsedWhileSuspended) {
    // isUpdateNeeded = true;
    super.onResume(dtElapsedWhileSuspended);
  }

  @override
  void onRemove() {
    final frames = animationComponent?.animation?.frames;
    if (frames != null) {
      for (final element in frames) {
        element.sprite.image.dispose();
      }
    }
    animationComponent?.onRemove();
    animationComponent = null;
    super.onRemove();
  }
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
