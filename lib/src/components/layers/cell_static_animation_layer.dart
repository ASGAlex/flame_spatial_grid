import 'package:flame/components.dart';
import 'package:flame/image_composition.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class CellStaticAnimationLayer extends CellLayer {
  CellStaticAnimationLayer(super.cell, [super.mapLoader]);

  SpriteAnimationComponent? animationComponent;
  SpriteAnimation? animation;

  @override
  Future<void>? add(Component component) {
    if (component is SpriteAnimationComponent) {
      animation ??= component.animation;
    }
    return super.add(component);
  }

  @override
  void updateTree(double dt) {
    animationComponent?.update(dt);
    super.updateTree(dt);
  }

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
  Future<void> compileToSingleLayer() async {
    final anim = animation?.clone();
    if (anim == null) {
      return;
    }

    List<Sprite> newSprites = [];

    while (anim.currentIndex < anim.frames.length) {
      final sprite = anim.getSprite();
      final composition = ImageComposition();
      for (final component in children.whereType<SpriteAnimationComponent>()) {
        final correctedPosition = component.position + (correctionTopLeft * -1);
        composition.add(sprite.image, correctedPosition, source: sprite.src);
      }
      var composedImage = await composition.compose();
      newSprites.add(Sprite(composedImage));
      anim.currentIndex++;
    }
    final spriteAnimation = SpriteAnimation.variableSpriteList(newSprites,
        stepTimes: anim.getVariableStepTimes());
    animationComponent = SpriteAnimationComponent(
        animation: spriteAnimation,
        position: correctionTopLeft,
        size: newSprites.first.image.size);
  }

  @override
  void onResume(double dtElapsedWhileSuspended) {
    isUpdateNeeded = true;
    super.onResume(dtElapsedWhileSuspended);
  }

  @override
  void onRemove() {
    final frames = animationComponent?.animation?.frames;
    if (frames != null) {
      for (var element in frames) {
        element.sprite.image.dispose();
      }
    }
    animationComponent = null;
    mapLoader?.animationLayers.remove(currentCell);
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
