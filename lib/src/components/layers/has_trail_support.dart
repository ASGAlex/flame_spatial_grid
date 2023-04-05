import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

mixin HasTrailSupport on HasGridSupport {
  @internal
  bool addedToTrailLayer = false;
  @internal
  bool renderCalledFromTrailLayer = false;

  @override
  void render(Canvas canvas) {
    if (!addedToTrailLayer ||
        (addedToTrailLayer && renderCalledFromTrailLayer)) {
      super.render(canvas);
    }
  }
}
