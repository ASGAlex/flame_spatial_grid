import 'dart:async';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_tiled/flame_tiled.dart';

/// Proxy class, simplifies access to tile's individual data
///
/// Use [getSprite] to get [Sprite] object.
/// Use [getSpriteAnimation] to get [SpriteAnimation] object of the tile.
/// Use [getCollisionRect] to load [RectangleHitbox] if it had been specified
/// in Tiled
///
class TileDataProvider {
  TileDataProvider(this.tile, this.tileset, [this.cache]);

  Tile tile;
  Tileset tileset;
  TileCache? cache;

  Rect? getCollisionRect() {
    if (cache == null) {
      return tile.getCollisionRect();
    } else {
      return cache!.getCollisionRect();
    }
  }

  Future<Sprite> getSprite() {
    final sprite = cache?.sprite;
    if (sprite != null) {
      return Future.value(sprite);
    } else {
      return tile.getSprite(tileset);
    }
  }

  Future<SpriteAnimation?> getSpriteAnimation() {
    final animation = cache?.spriteAnimation;
    if (animation != null) {
      return Future.value(animation);
    } else {
      return tile.getSpriteAnimation(tileset);
    }
  }
}
