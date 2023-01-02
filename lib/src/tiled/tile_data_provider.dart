import 'dart:async';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/image_composition.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_tiled/flame_tiled.dart';

/// Utility class allows to process each map tile individually
/// Usage example:
/// ``` dart
/// final mapComponent = await TiledComponent.load('map.tmx', Vector2.all(16));
/// TileProcessor.processTileType(
///   tileMap: mapComponent.tileMap,
///   processorByType: <String, TileProcessorFunc>{
///     'water': ((tile, position, size) {
///       /// Create here a new object, save tile data or process it
///       /// a way your game logics need
///     }),
///   },
///   layersToLoad: [
///   'water',
/// ]);
/// ```
/// You can process individual computations for each tile inside [TileBuilderFunction].
/// Use [getSprite] to get [Sprite] object.
/// Use [getSpriteAnimation] to get [SpriteAnimation] object of the tile.
/// Use [getCollisionRect] to load [RectangleHitbox] if it had been specified in Tiled
///
/// You usually do not need to create the class manually. Call [TileDataProvider.processTileType], and
/// it will do the rest of work.
///
/// If you need to process another map, it might be useful to call [TileDataProvider.clearCache]
/// if new map's tiles are very different from previous one.
class TileDataProvider {
  TileDataProvider(this.tile, this.tileset);

  Tile tile;
  Tileset tileset;

  RectangleHitbox? getCollisionRect() {
    if (tile.objectGroup?.type == LayerType.objectGroup) {
      final grp = tile.objectGroup as ObjectGroup;
      if (grp.objects.isNotEmpty) {
        final obj = grp.objects.first;
        return RectangleHitbox(
            size: Vector2(obj.width, obj.height),
            position: Vector2(obj.x, obj.y));
      }
    }
    return null;
  }

  Future<Sprite> getSprite() => tile.getSprite(tileset);

  Future<SpriteAnimation?> getSpriteAnimation() =>
      tile.getSpriteAnimation(tileset);
}

class CellBuilderContext {
  CellBuilderContext(
      {this.tileDataProvider,
      this.tiledObject,
      required this.position,
      required this.size,
      required this.cellRect,
      required this.spatialGrid,
      required this.layerInfo});

  final SpatialGrid spatialGrid;
  final Rect cellRect;
  final Vector2 position;
  final Vector2 size;
  final TileDataProvider? tileDataProvider;
  final TiledObject? tiledObject;
  int? priorityOverride;
  final LayerInfo layerInfo;

  Cell? get cell => spatialGrid.cells[cellRect];

  bool remove = false;
}

class LayerInfo {
  LayerInfo(this.name, this.priority);

  final String name;
  final int priority;
}
