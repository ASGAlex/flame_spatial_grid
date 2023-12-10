import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';
import 'package:tiled/tiled.dart';

/// This class is a storage of tile's data from tileset.
/// Use [TiledMapLoader.getPreloadedTileData] to get instance of this class.
/// Also read about [TiledMapLoader.preloadTileSets]
@immutable
class TileCache {
  TileCache({
    this.sprite,
    this.spriteAnimation,
    required this.properties,
    required this.tile,
    required this.tileset,
  }) : _collisionRect = tile.getCollisionRect();

  final Sprite? sprite;
  final SpriteAnimation? spriteAnimation;
  final CustomProperties properties;
  final Tile tile;
  final Tileset tileset;
  final Rect? _collisionRect;

  Rect? getCollisionRect() => _collisionRect;

  void dispose() {
    try {
      sprite?.image.dispose();
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}

    final frames = spriteAnimation?.frames;
    if (frames != null) {
      for (final frame in frames) {
        try {
          frame.sprite.image.dispose();
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {}
      }
    }
  }
}
