import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

mixin RestorableStateMixin on HasGridSupport {
  TileBuilderContext? get context;

  void updateContext() {
    final cell = currentCell;
    if (cell == null) {
      throw 'Can not update context without cell';
    }
    final ctx = context;
    if (ctx == null || ctx.remove) {
      return;
    }
    ctx.size.setFrom(size);
    ctx.absolutePosition.setFrom(
      anchor.toOtherAnchorPosition(
        position,
        Anchor.topLeft,
        size,
      ),
    );
    ctx.cellRect = cell.rect;
  }

  @override
  void onRemove() {
    updateContext();
    super.onRemove();
  }
}
