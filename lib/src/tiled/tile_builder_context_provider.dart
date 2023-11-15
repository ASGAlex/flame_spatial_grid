import 'dart:collection';
import 'dart:ui';

import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class TileBuilderContextProvider<T,C> {
  TileBuilderContextProvider({required this.parent});

  /// It should be [HasSpatialGridFramework] instance or [TiledMapLoader]
  /// instance
  final T parent;

  final _contextByCellRect = HashMap<Rect, HashSet<TileBuilderContext<C>>>();

  HashSet<TileBuilderContext<C>>? getContextListForCell(Cell cell) =>
      getContextListForCellRect(cell.rect);

  HashSet<TileBuilderContext<C>>? getContextListForCellRect(Rect rect) =>
      _contextByCellRect[rect];

  void addContext(TileBuilderContext<C> context) {
    var list = HashSet<TileBuilderContext<C>>();
    list = _contextByCellRect[context.cellRect] ??= list;
    list.add(context);
  }

  void clearContextStorage() => _contextByCellRect.clear();
}
