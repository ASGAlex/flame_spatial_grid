import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

/// This class is a storage of tile's data from tileset.
/// Use [TiledMapLoader.getPreloadedTileData] to get instance of this class.
/// Also read about [TiledMapLoader.preloadTileSets]
@immutable
class TileCache {
  const TileCache({this.sprite, this.spriteAnimation});

  final Sprite? sprite;
  final SpriteAnimation? spriteAnimation;
}
