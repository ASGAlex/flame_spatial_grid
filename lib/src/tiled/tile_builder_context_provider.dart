import 'dart:collection';
import 'dart:ui';

import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class TileBuilderContextProvider<T> {
  TileBuilderContextProvider({required this.parent});

  /// It should be [HasSpatialGridFramework] instance or [TiledMapLoader]
  /// instance
  final T parent;

  final _contextByCellRect = HashMap<Rect, HashSet<TileBuilderContext>>();

  HashSet<TileBuilderContext>? getContextListForCell(Cell cell) =>
      getContextListForCellRect(cell.rect);

  HashSet<TileBuilderContext>? getContextListForCellRect(Rect rect) =>
      _contextByCellRect[rect];

  void addContext(TileBuilderContext context) {
    var list = HashSet<TileBuilderContext>();
    list = _contextByCellRect[context.cellRect] ??= list;
    list.add(context);
  }

  void clearContextStorage() => _contextByCellRect.clear();
}
