import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class SpatialGridBaseGame<W extends World> extends FlameGameEx<W>
    with HasSpatialGridFramework<W> {
  SpatialGridBaseGame({
    super.children,
    super.world,
    super.camera,
  });
}
