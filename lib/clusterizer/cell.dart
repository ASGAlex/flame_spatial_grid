import 'dart:collection';

import 'package:flame/extensions.dart';

import 'clusterized_component.dart';
import 'clusterizer.dart';

enum _CellCreationContext { left, top, right, bottom }

enum CellState { active, inactive, suspended }

class Cell {
  Cell({required this.clusterizer, required this.rect}) {
    clusterizer.cells[rect] = this;
    clusterizer.addListener(_onCellStateUpdated);
    // print(clusterizer.cells.length);
  }

  final Clusterizer clusterizer;
  final Rect rect;
  final components = HashSet<ClusterizedComponent>();
  CellState state = CellState.active;
  CellState _previousState = CellState.active;

  Cell? rawLeft;
  Cell? rawRight;
  Cell? rawTop;
  Cell? rawBottom;

  Cell get left {
    rawLeft ??= _createLeft();
    return rawLeft!;
  }

  Cell get right {
    rawRight ??= _createRight();
    return rawRight!;
  }

  Cell get top {
    rawTop ??= _createTop();
    return rawTop!;
  }

  Cell get bottom {
    rawBottom ??= _createBottom();
    return rawBottom!;
  }

  Cell _createLeft({bool recursive = true}) {
    const creationContext = _CellCreationContext.left;
    final newLeft = Cell(
        clusterizer: clusterizer,
        rect: _createRectForDirection(creationContext));
    newLeft.rawRight = this;

    if (recursive) {
      final upperLeft = rawTop?.rawLeft;
      if (upperLeft != null) {
        upperLeft.rawBottom = newLeft;
        newLeft.rawTop = upperLeft;
      } else {
        newLeft.rawTop = newLeft._createTop(recursive: false);
        rawTop?.rawLeft = newLeft.rawTop;
      }

      final lowerLeft = rawBottom?.rawLeft;
      if (lowerLeft != null) {
        lowerLeft.rawTop = newLeft;
        newLeft.rawBottom = lowerLeft;
      } else {
        newLeft.rawBottom = newLeft._createBottom(recursive: false);
        rawBottom?.rawLeft = newLeft.rawBottom;
      }
    }
    newLeft._fillPotentialNeighboards(creationContext);

    return newLeft;
  }

  Cell _createRight({bool recursive = true}) {
    const creationContext = _CellCreationContext.right;
    final newRight = Cell(
        clusterizer: clusterizer,
        rect: _createRectForDirection(creationContext));
    newRight.rawLeft = this;

    if (recursive) {
      final upperRight = rawTop?.rawRight;
      if (upperRight != null) {
        upperRight.rawBottom = newRight;
        newRight.rawTop = upperRight;
      } else {
        newRight.rawTop = newRight._createTop(recursive: false);
        rawTop?.rawRight = newRight.rawTop;
      }

      final lowerRight = rawRight?.rawBottom;
      if (lowerRight != null) {
        lowerRight.rawRight = newRight;
        newRight.rawBottom = lowerRight;
      } else {
        newRight.rawBottom = newRight._createBottom(recursive: false);
        rawBottom?.rawRight = newRight.rawBottom;
      }
    }
    newRight._fillPotentialNeighboards(creationContext);

    return newRight;
  }

  Cell _createTop({bool recursive = true}) {
    const creationContext = _CellCreationContext.top;
    final newTop = Cell(
        clusterizer: clusterizer,
        rect: _createRectForDirection(creationContext));
    newTop.rawBottom = this;

    if (recursive) {
      final leftTop = rawLeft?.rawTop;
      if (leftTop != null) {
        leftTop.rawRight = newTop;
        newTop.rawLeft = leftTop;
      } else {
        newTop.rawLeft = newTop._createLeft(recursive: false);
        rawLeft?.rawTop = newTop.rawLeft;
      }

      final rightTop = rawRight?.rawTop;
      if (rightTop != null) {
        rightTop.rawLeft = newTop;
        newTop.rawRight = rightTop;
      } else {
        newTop.rawRight = newTop._createRight(recursive: false);
        rawRight?.rawTop = newTop.rawRight;
      }
    }
    newTop._fillPotentialNeighboards(creationContext);

    return newTop;
  }

  Cell _createBottom({bool recursive = true}) {
    const creationContext = _CellCreationContext.bottom;
    final newBottom = Cell(
        clusterizer: clusterizer,
        rect: _createRectForDirection(creationContext));
    newBottom.rawTop = this;

    if (recursive) {
      final leftBottom = rawLeft?.rawBottom;
      if (leftBottom != null) {
        leftBottom.rawRight = newBottom;
        newBottom.rawLeft = leftBottom;
      } else {
        newBottom.rawLeft = newBottom._createLeft(recursive: false);
        rawLeft?.rawBottom = newBottom.rawLeft;
      }

      final rightBottom = rawRight?.rawBottom;
      if (rightBottom != null) {
        rightBottom.rawLeft = newBottom;
        newBottom.rawRight = rightBottom;
      } else {
        newBottom.rawRight = newBottom._createRight(recursive: false);
        rawRight?.rawBottom = newBottom.rawRight;
      }
    }
    newBottom._fillPotentialNeighboards(creationContext);

    return newBottom;
  }

  Rect _createRectForDirection(_CellCreationContext creationContext) {
    final width = clusterizer.blockSize.width;
    final height = clusterizer.blockSize.height;
    switch (creationContext) {
      case _CellCreationContext.left:
        return Rect.fromLTWH(rect.left - width, rect.top, width, height);
      case _CellCreationContext.top:
        return Rect.fromLTWH(rect.left, rect.top - height, width, height);
      case _CellCreationContext.right:
        return Rect.fromLTWH(rect.right, rect.top, width, height);
      case _CellCreationContext.bottom:
        return Rect.fromLTWH(rect.left, rect.bottom, width, height);
    }
  }

  void _fillPotentialNeighboards(_CellCreationContext creationContext) {
    final rectsToCheck = <_CellCreationContext, Rect>{};
    switch (creationContext) {
      case _CellCreationContext.left:
        rectsToCheck[_CellCreationContext.left] =
            _createRectForDirection(_CellCreationContext.left);
        rectsToCheck[_CellCreationContext.top] =
            _createRectForDirection(_CellCreationContext.top);
        rectsToCheck[_CellCreationContext.bottom] =
            _createRectForDirection(_CellCreationContext.bottom);
        break;
      case _CellCreationContext.top:
        rectsToCheck[_CellCreationContext.right] =
            _createRectForDirection(_CellCreationContext.right);
        rectsToCheck[_CellCreationContext.top] =
            _createRectForDirection(_CellCreationContext.top);
        rectsToCheck[_CellCreationContext.left] =
            _createRectForDirection(_CellCreationContext.left);
        break;
      case _CellCreationContext.right:
        rectsToCheck[_CellCreationContext.right] =
            _createRectForDirection(_CellCreationContext.right);
        rectsToCheck[_CellCreationContext.top] =
            _createRectForDirection(_CellCreationContext.top);
        rectsToCheck[_CellCreationContext.bottom] =
            _createRectForDirection(_CellCreationContext.bottom);
        break;
      case _CellCreationContext.bottom:
        rectsToCheck[_CellCreationContext.right] =
            _createRectForDirection(_CellCreationContext.right);
        rectsToCheck[_CellCreationContext.bottom] =
            _createRectForDirection(_CellCreationContext.bottom);
        rectsToCheck[_CellCreationContext.left] =
            _createRectForDirection(_CellCreationContext.left);
        break;
    }

    for (var element in rectsToCheck.entries) {
      final cell = clusterizer.cells[element.value];
      if (cell != null) {
        switch (element.key) {
          case _CellCreationContext.left:
            rawLeft = cell;
            cell.rawRight = this;
            break;
          case _CellCreationContext.top:
            rawTop = cell;
            cell.rawBottom = this;
            break;
          case _CellCreationContext.right:
            rawRight = cell;
            cell.rawLeft = this;
            break;
          case _CellCreationContext.bottom:
            rawBottom = cell;
            cell.rawTop = this;
            break;
        }
      }
    }
  }

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

  void _onCellStateUpdated() {
    if (state != _previousState) {
      for (var component in components) {
        component.isVisible = (state == CellState.active ? true : false);
        component.isSuspended = (state == CellState.suspended ? true : false);
      }
    }

    _previousState = state;
  }

  dispose() {
    clusterizer.removeListener(_onCellStateUpdated);
  }
}
