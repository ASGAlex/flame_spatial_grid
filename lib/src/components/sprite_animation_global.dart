import 'dart:collection';

import 'package:flame/components.dart';

class SpriteAnimationGlobalController {
  factory SpriteAnimationGlobalController.instance() =>
      _instance ??= SpriteAnimationGlobalController._();

  static SpriteAnimationGlobalController? _instance;

  static void dispose() {
    final animations = _instance?._animations;
    if (animations != null) {
      for (final entry in animations.entries) {
        for (final component in entry.value.trackedComponents) {
          component.removeFromParent();
        }
        entry.value.trackedComponents.clear();
      }
      animations.clear();
    }
    _instance = null;
  }

  SpriteAnimationGlobalController._();

  void trackComponent(SpriteAnimationGlobalComponent component) {
    final componentAnimation = component.animation;
    if (componentAnimation == null) {
      throw 'No component animation specified.';
    }
    var animationsOfType = _animations[component.animationType];
    if (animationsOfType == null) {
      final globalAnimation = componentAnimation.clone();
      _animations[component.animationType] =
          animationsOfType = GlobalAnimationElement(globalAnimation);
    } else {
      animationsOfType.trackedComponents.add(component);
    }
  }

  bool playing = true;

  final _animations = HashMap<String, GlobalAnimationElement>();

  void update(double dt) {
    for (final element in _animations.values) {
      element.globalAnimation.update(dt);
      for (final tracked in element.trackedComponents) {
        final animation = tracked.animation;
        if (animation == null) {
          continue;
        }
        animation.clock = element.globalAnimation.clock;
        animation.elapsed = element.globalAnimation.elapsed;
        animation.currentIndex = element.globalAnimation.currentIndex;
      }
    }
  }
}

class GlobalAnimationElement {
  GlobalAnimationElement(this.globalAnimation);

  final SpriteAnimation globalAnimation;
  final trackedComponents = HashSet<SpriteAnimationComponent>();
}

class SpriteAnimationGlobalComponent extends SpriteAnimationComponent {
  SpriteAnimationGlobalComponent({
    required this.animationType,
    super.animation,
    super.removeOnFinish,
    super.playing,
    super.paint,
    super.position,
    super.size,
    super.scale,
    super.angle,
    super.nativeAngle,
    super.anchor,
    super.children,
    super.priority,
  }) {
    SpriteAnimationGlobalController.instance().trackComponent(this);
  }

  final String animationType;

  @override
  void onRemove() {
    SpriteAnimationGlobalController.instance()
        ._animations[animationType]
        ?.trackedComponents
        .remove(this);
    super.onRemove();
  }

  @override
  // ignore: must_call_super
  Future<void> update(double dt) => throw 'Should never been called';
}
