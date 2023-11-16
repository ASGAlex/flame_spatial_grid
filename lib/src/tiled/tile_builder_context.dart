import 'package:flame/image_composition.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_tiled/flame_tiled.dart';

/// This class represents the tile's data and the cell's context in which this
/// tile was built
/// [absolutePosition] and [size] represents tile's global position on the game
/// field and it's dimensions.
/// If this context contains information about tiled object, [tiledObject] will
/// be not null.
/// If the context contains information about tile, the [tileDataProvider]
/// will be not null.
/// Use these properties to build custom components for map's tiles or objects.
///
///
class TileBuilderContext<T> {
  TileBuilderContext({
    this.tileDataProvider,
    this.tiledObject,
    this.userData,
    required this.absolutePosition,
    required this.size,
    required this.cellRect,
    required this.contextProvider,
    required this.layerInfo,
  });

  TileBuilderContextProvider contextProvider;
  T? userData;

  Rect cellRect;

  ///Tile's position in the global game's coordinates space
  Vector2 absolutePosition;

  ///Tiles width and height
  Vector2 size;

  /// Tile's most wanted information: the sprite or animation, collision rect
  final TileDataProvider? tileDataProvider;

  String get tileTypeName => tileDataProvider?.tile.type ?? '';

  /// Tiled object's information, if object was processed instead a tile
  final TiledObject? tiledObject;
  int? priorityOverride;
  final LayerInfo layerInfo;

  /// The cell in which the tile should be placed
  Cell? get cell {
    final providerOwner = contextProvider.parent;
    if (providerOwner is TiledMapLoader) {
      return providerOwner.game.spatialGrid.cells[cellRect];
    } else if (providerOwner is HasSpatialGridFramework) {
      return providerOwner.spatialGrid.cells[cellRect];
    }
    return null;
  }

  ///  If the tile should be removed in the next map load operation. Useful in
  ///  cause you implementing a destructible game environment and want to
  ///  preserve you  changes between cells unload and restoration
  bool get removed => _removed;
  bool _removed = false;

  void remove() {
    if (cell != null) {
      final contextList = contextProvider.getContextListForCell(cell!);
      contextList?.remove(this);
      _removed = true;
    }
  }
}

class LayerInfo {
  LayerInfo(this.name, this.priority);

  final String name;
  final int priority;
}
