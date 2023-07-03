import 'dart:collection';

import 'package:flame/flame.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/tiled/tileset_parser.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flame_tiled/src/tile_atlas.dart';
import 'package:meta/meta.dart';

class TilesetManager {
  static final _preloadedTileSet =
      HashMap<String, HashMap<String, TileCache>>();

  /// Use this function in tile builder to access tile's [Sprite]
  /// or [SpriteAnimation].
  TileCache? getTile(String tileSetName, String tileType) =>
      _preloadedTileSet[tileSetName]?[tileType];

  Future<void> loadTileset(String fileName) async {
    final tileSet = await TilesetParser.fromFile(fileName);
    return _populateCache(tileSet);
  }

  Future<void> _populateCache(Tileset tileSet) async {
    final tilesetName = tileSet.name;
    if (tilesetName == null) {
      return;
    }
    final tilesetCache =
        _preloadedTileSet[tilesetName] ?? HashMap<String, TileCache>();
    if (tilesetCache.isNotEmpty) {
      return;
    }
    for (final tile in tileSet.tiles) {
      final tileTypeName = tile.type;
      if (tileTypeName == null) {
        continue;
      }
      tilesetCache[tileTypeName] = TileCache(
        sprite: await tile.getSprite(tileSet),
        spriteAnimation: await tile.getSpriteAnimation(tileSet),
        properties: tile.properties,
        tileset: tileSet,
        tile: tile,
      );
    }
    _preloadedTileSet[tilesetName] = tilesetCache;
  }

  @internal
  Future<List<void>> addFromMap(TiledMap map) {
    final futures = <Future>[];
    for (final tileSet in map.tilesets) {
      futures.add(_populateCache(tileSet));
    }
    return Future.wait<void>(futures);
  }

  static void dispose() {
    Flame.images.clearCache();
    TiledAtlas.clearCache();
    for (final map in _preloadedTileSet.values) {
      for (final cache in map.values) {
        cache.dispose();
      }
      map.clear();
    }
    _preloadedTileSet.clear();
  }
}
