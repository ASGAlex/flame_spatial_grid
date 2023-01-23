import 'dart:async';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/image_composition.dart';
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

  RectangleHitbox? getCollisionRect() {
    final group = tile.objectGroup;
    final type = group?.type;
    if (type == LayerType.objectGroup && group is ObjectGroup) {
      if (group.objects.isNotEmpty) {
        final obj = group.objects.first;
        return RectangleHitbox(
          size: Vector2(obj.width, obj.height),
          position: Vector2(obj.x, obj.y),
        );
      }
    }
    return null;
  }

  FutureOr<Sprite> getSprite() {
    final sprite = cache?.sprite;
    if (sprite != null) {
      return sprite;
    } else {
      return tile.getSprite(tileset);
    }
  }

  FutureOr<SpriteAnimation?> getSpriteAnimation() {
    final animation = cache?.spriteAnimation;
    if (animation != null) {
      return animation;
    } else {
      return tile.getSpriteAnimation(tileset);
    }
  }
}

/// This class represents the tile's data and the cell's context in which this
/// tile was built
/// [position] and [size] represents tile's global position on the game field
/// and it's dimensions.
/// If this context contains information about tiled object, [tiledObject] will
/// be not null.
/// If the context contains information about tile, the [tileDataProvider]
/// will be not null.
/// Use these properties to build custom components for map's tiles or objects.
///
///
class CellBuilderContext {
  CellBuilderContext({
    this.tileDataProvider,
    this.tiledObject,
    required this.position,
    required this.size,
    required this.cellRect,
    required this.spatialGrid,
    required this.layerInfo,
  });

  final SpatialGrid spatialGrid;
  Rect cellRect;

  ///Tile's position in the global game's coordinates space
  Vector2 position;

  ///Tiles width and height
  Vector2 size;

  /// Tile's most wanted information: the sprite or animation, collision rect
  final TileDataProvider? tileDataProvider;

  /// Tiled object's information, if object was processed instead a tile
  final TiledObject? tiledObject;
  int? priorityOverride;
  final LayerInfo layerInfo;

  /// The cell in which the tile should be placed
  Cell? get cell => spatialGrid.cells[cellRect];

  ///  If the tile should be removed in the next map load operation. Useful in
  ///  cause you implementing a destructible game environment and want to
  ///  preserve you  changes between cells unload and restoration
  bool remove = false;
}

class LayerInfo {
  LayerInfo(this.name, this.priority);

  final String name;
  final int priority;
}
