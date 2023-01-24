import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class TileComponent extends SpriteComponent
    with HasGridSupport, UpdateOnDemand
    implements SpriteAnimationComponent {
  static Future<TileComponent> fromProvider(TileDataProvider provider) async {
    final cache = TileCache(
      sprite: await provider.getSprite(),
      spriteAnimation: await provider.getSpriteAnimation(),
    );
    return TileComponent(cache);
  }

  TileComponent(this.tileCache) {
    paint.isAntiAlias = false;
    paint.filterQuality = FilterQuality.none;
  }

  final TileCache tileCache;

  @override
  Sprite? get sprite => tileCache.sprite;

  @override
  SpriteAnimation? get animation => tileCache.spriteAnimation;

  @override
  bool playing = true;

  @override
  bool removeOnFinish = false;

  @override
  set animation(SpriteAnimation? animation) {}
}
