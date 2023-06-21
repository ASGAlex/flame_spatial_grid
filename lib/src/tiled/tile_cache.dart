import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';
import 'package:tiled/tiled.dart';

/// This class is a storage of tile's data from tileset.
/// Use [TiledMapLoader.getPreloadedTileData] to get instance of this class.
/// Also read about [TiledMapLoader.preloadTileSets]
@immutable
class TileCache {
  const TileCache({
    this.sprite,
    this.spriteAnimation,
    required this.properties,
  });

  final Sprite? sprite;
  final SpriteAnimation? spriteAnimation;
  final CustomProperties properties;

  void dispose() {
    try {
      sprite?.image.dispose();
    } catch (_) {}

    final frames = spriteAnimation?.frames;
    if (frames != null) {
      for (final frame in frames) {
        try {
          frame.sprite.image.dispose();
        } catch (_) {}
      }
    }
  }
}
