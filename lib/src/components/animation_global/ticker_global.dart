import 'package:flame/sprite.dart';

class SpriteAnimationTickerGlobal extends SpriteAnimationTicker {
  SpriteAnimationTickerGlobal(super.spriteAnimation);

  Sprite getSpriteOfAnimation(SpriteAnimation animationLocal) =>
      animationLocal.frames[currentIndex].sprite;
}
