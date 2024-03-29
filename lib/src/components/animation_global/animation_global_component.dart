import 'package:flame/components.dart';
import 'package:flame/image_composition.dart';
import 'package:flame/sprite.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class SpriteAnimationGlobalComponent extends SpriteAnimationComponent {
  SpriteAnimationGlobalComponent({
    required SpriteAnimation animation,
    super.position,
    super.size,
    required this.animationType,
    required TickersManager tickersProvider,
  })  : animationLocal = animation,
        super(
          animation: AnimationGlobal(
            animation,
            animationType,
            tickersProvider,
          ),
        );

  final SpriteAnimation animationLocal;
  final String animationType;

  @override
  // ignore: must_call_super
  void render(Canvas canvas) {
    try {
      (animationTicker! as SpriteAnimationTickerGlobal)
          .getSpriteOfAnimation(animationLocal)
          .render(
            canvas,
            size: size,
            overridePaint: paint,
          );
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }
}

class AnimationGlobal extends SpriteAnimation {
  AnimationGlobal(
    SpriteAnimation animation,
    this.animationType,
    this.tickersProvider,
  ) : super(
          animation.frames,
          loop: animation.loop,
        );

  final String animationType;
  final TickersManager tickersProvider;

  @override
  SpriteAnimationTicker createTicker() {
    return tickersProvider.getTicker(animationType, this);
  }
}
