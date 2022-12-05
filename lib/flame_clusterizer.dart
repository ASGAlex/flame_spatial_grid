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

library flame_clusterizer;

export 'src/collisions/clusterized_broadphase.dart';
export 'src/collisions/clusterized_collision_detection.dart';
export 'src/collisions/has_clusterized_collision_detection.dart';
export 'src/components/cell_static_animation_layer.dart';
export 'src/components/cell_static_layer.dart';
export 'src/components/clusterized_component.dart';
export 'src/components/debug_component.dart';
export 'src/components/on_demand_actions.dart';
export 'src/core/cell.dart';
export 'src/core/cell_builder.dart';
export 'src/core/clusterizer.dart';
