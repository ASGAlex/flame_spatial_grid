import 'dart:collection';

import 'package:flame/extensions.dart';

import 'clusterized_component.dart';
import 'clusterizer.dart';

enum _CellCreationContext { left, top, right, bottom }

enum CellState { active, inactive, suspended }

class Cell {
  Cell({required this.clusterizer, required this.rect}) {
    center = rect.center.toVector2();
    clusterizer.cells[rect] = this;
    clusterizer.cellBuilder?.build(this);
    // print(clusterizer.cells.length);
  }

  final Clusterizer clusterizer;
  final Rect rect;
  late final Vector2 center;
  final components = HashSet<ClusterizedComponent>();
  CellState state = CellState.active;

  Cell? rawLeft;
  Cell? rawRight;
  Cell? rawTop;
  Cell? rawBottom;

  final _cachedRects = <_CellCreationContext, Rect>{};

  Cell get left => rawLeft ??= _createCell(_CellCreationContext.left);

  Cell get right => rawRight ??= _createCell(_CellCreationContext.right);

  Cell get top => rawTop ??= _createCell(_CellCreationContext.top);

  Cell get bottom => rawBottom ??= _createCell(_CellCreationContext.bottom);

  Cell _createCell(_CellCreationContext direction, [bool recursive = true]) {
    var newCell = _checkCell(direction);
    newCell ??= Cell(
        clusterizer: clusterizer, rect: _createRectForDirection(direction));

    switch (direction) {
      case _CellCreationContext.left:
        if (recursive) {
          newCell._createCell(_CellCreationContext.top, false);
          newCell._createCell(_CellCreationContext.bottom, false);
        } else {
          newCell.rawTop ??= newCell._checkCell(_CellCreationContext.top);
          newCell.rawBottom ??= newCell._checkCell(_CellCreationContext.bottom);
        }
        newCell.rawLeft ??= newCell._checkCell(_CellCreationContext.left);
        newCell.rawRight = this;
        break;
      case _CellCreationContext.top:
        if (recursive) {
          newCell._createCell(_CellCreationContext.left, false);
          newCell._createCell(_CellCreationContext.right, false);
        } else {
          newCell.rawLeft ??= newCell._checkCell(_CellCreationContext.left);
          newCell.rawRight ??= newCell._checkCell(_CellCreationContext.right);
        }
        newCell.rawTop ??= newCell._checkCell(_CellCreationContext.top);
        newCell.rawBottom = this;
        break;
      case _CellCreationContext.right:
        if (recursive) {
          newCell._createCell(_CellCreationContext.top, false);
          newCell._createCell(_CellCreationContext.bottom, false);
        } else {
          newCell.rawTop ??= newCell._checkCell(_CellCreationContext.top);
          newCell.rawBottom ??= newCell._checkCell(_CellCreationContext.bottom);
        }
        newCell.rawRight ??= newCell._checkCell(_CellCreationContext.right);
        newCell.rawLeft = this;
        break;
      case _CellCreationContext.bottom:
        if (recursive) {
          newCell._createCell(_CellCreationContext.left, false);
          newCell._createCell(_CellCreationContext.right, false);
        } else {
          newCell.rawLeft ??= newCell._checkCell(_CellCreationContext.left);
          newCell.rawRight ??= newCell._checkCell(_CellCreationContext.right);
        }
        newCell.rawBottom ??= newCell._checkCell(_CellCreationContext.bottom);
        newCell.rawTop = this;
        break;
    }

    return newCell;
  }

  Rect _createRectForDirection(_CellCreationContext creationContext) {
    var newRect = _cachedRects[creationContext];
    if (newRect == null) {
      final width = clusterizer.blockSize.width;
      final height = clusterizer.blockSize.height;
      switch (creationContext) {
        case _CellCreationContext.left:
          newRect = Rect.fromLTWH(rect.left - width, rect.top, width, height);
          break;
        case _CellCreationContext.top:
          newRect = Rect.fromLTWH(rect.left, rect.top - height, width, height);
          break;
        case _CellCreationContext.right:
          newRect = Rect.fromLTWH(rect.right, rect.top, width, height);
          break;
        case _CellCreationContext.bottom:
          newRect = Rect.fromLTWH(rect.left, rect.bottom, width, height);
          break;
      }
      _cachedRects[creationContext] = newRect;
    }
    return newRect;
  }

  Cell? _checkCell(_CellCreationContext direction) =>
      clusterizer.cells[_createRectForDirection(direction)];

  List<Cell> get neighbours {
    final list = <Cell>[];
    if (rawLeft != null) {
      list.add(rawLeft!);
      final leftTop = rawLeft!.rawTop;
      if (leftTop != null) {
        list.add(leftTop);
      }
      final leftBottom = rawLeft!.rawBottom;
      if (leftBottom != null) {
        list.add(leftBottom);
      }
    }
    if (rawRight != null) {
      list.add(rawRight!);

      final rightTop = rawRight!.rawTop;
      if (rightTop != null) {
        list.add(rightTop);
      }
      final rightBottom = rawRight!.rawBottom;
      if (rightBottom != null) {
        list.add(rightBottom);
      }
    }
    if (rawTop != null) {
      list.add(rawTop!);
    }
    if (rawBottom != null) {
      list.add(rawBottom!);
    }
    return list;
  }

  List<Cell> get neighboursAndMe => neighbours..add(this);

  dispose() {
    components.clear();
    rawLeft = rawRight = rawTop = rawBottom = null;
  }
}
