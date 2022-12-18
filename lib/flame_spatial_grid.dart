/// Features:
///
/// Merge a layer of tiled map into component to render as single image.
/// See [ImageBatchCompiler].
///
/// Map each tile to dart class or process function using "Type" parameter as key
/// See [TiledComponent].
///
/// Extract animation from tiles, allows to render maps with animated tiles.
/// Use [TiledComponent] and it's utility functions.
///
/// Merge animated tiles of same type into one big SpriteAnimation component.
/// Use combination of [TiledComponent] and [AnimationBatchCompiler]
///
///

library flame_spatial_grid;

export 'src/collisions/broadphase.dart';
export 'src/collisions/collision_detection.dart';
export 'src/collisions/has_spatial_grid_framework.dart';
export 'src/components/debug_component.dart';
export 'src/components/has_grid_support.dart';
export 'src/components/layers/cell_layer.dart';
export 'src/components/layers/cell_static_animation_layer.dart';
export 'src/components/layers/cell_static_layer.dart';
export 'src/components/on_demand_actions.dart';
export 'src/components/tile_component.dart';
export 'src/core/cell.dart';
export 'src/core/spatial_grid.dart';
export 'src/tiled/map_loader.dart';
export 'src/tiled/sprite_loader.dart';
export 'src/tiled/tile_data_provider.dart';
