import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

mixin RestorableStateMixin<T> on HasGridSupport {
  T? get userData;

  TileBuilderContext? context;
  TileCache? tileCache;

  @override
  void onSpatialGridInitialized() {
    final cell = currentCell;
    if (context == null && cell != null) {
      TileDataProvider? tileDataProvider;
      if (tileCache != null) {
        tileDataProvider =
            TileDataProvider(tileCache!.tile, tileCache!.tileset, tileCache);
      }
      context = TileBuilderContext<T>(
        absolutePosition: Anchor.center.toOtherAnchorPosition(
          boundingBox.aabbCenter,
          anchor,
          size,
        ),
        userData: userData,
        tileDataProvider: tileDataProvider,
        size: size,
        cellRect: cell.rect,
        contextProvider: cell.spatialGrid.game.tileBuilderContextProvider,
        layerInfo: LayerInfo('game', 0),
      );
      sgGame.tileBuilderContextProvider.addContext(context!);
    }
  }

  void updateContext() {
    final cell = currentCell;
    if (cell == null) {
      throw 'Can not update context without cell';
    }
    final ctx = context;
    if (ctx == null || ctx.removed) {
      return;
    }
    ctx.size.setFrom(size);
    ctx.absolutePosition.setFrom(
      Anchor.center.toOtherAnchorPosition(
        boundingBox.aabbCenter,
        anchor,
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
