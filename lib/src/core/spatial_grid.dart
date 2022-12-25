import 'dart:collection';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

typedef CellBuilderFunction = Future<void> Function(
    Cell cell, Component rootComponent);

class SpatialGrid {
  SpatialGrid(
      {required this.blockSize,
      required this.trackedComponent,
      required this.game,
      bool lazyLoad = true,
      Size? activeRadius,
      required Size? unloadRadius}) {
    this.activeRadius = (activeRadius ?? const Size(2, 2));
    this.unloadRadius = (unloadRadius ?? const Size(5, 5));

    final cell = Cell(
        spatialGrid: this,
        suspended: lazyLoad,
        rect: Rect.fromCenter(
            center: trackedComponent.position.toOffset(),
            width: blockSize.width,
            height: blockSize.height));

    if (!lazyLoad) {
      setActiveCell(cell);
    }
    trackedComponent.currentCell = cell;
  }

  dispose() {
    for (final cell in cells.values) {
      cell.remove();
    }
    cells.clear();
  }

  final HasSpatialGridFramework game;

  final cells = HashMap<Rect, Cell>();
  Cell? _currentCell;

  @internal
  final cellsScheduledToBuild = HashSet<Cell>();

  final Size blockSize;
  final HasGridSupport trackedComponent;

  Size activeRadius = const Size(2, 2);
  Size unloadRadius = const Size(5, 5);

  void setActiveCell(Cell newActiveCell) {
    _currentCell = newActiveCell;
    updateCellsStateByRadius();
  }

  void updateCellsStateByRadius() {
    for (final cell in cells.values) {
      cell.tmpState = CellState.suspended;
    }

    final cellsToInactivate = _findCellsInRadius(unloadRadius);
    for (final cell in cellsToInactivate) {
      cell.tmpState = CellState.inactive;
    }

    final cellsToActivate = _findCellsInRadius(activeRadius, create: true);
    for (final cell in cellsToActivate) {
      cell.tmpState = CellState.active;
    }
    _currentCell?.tmpState = CellState.active;

    for (final cell in cells.values) {
      cell.state = cell.tmpState;
    }
  }

  CellState getCellState(Cell cell) {
    final distance = _cellDistanceFromActiveCell(cell);
    if (distance.x <= activeRadius.width && distance.y <= activeRadius.height) {
      return CellState.active;
    } else if (distance.x < unloadRadius.width &&
        distance.y < unloadRadius.height) {
      return CellState.inactive;
    }
    return CellState.suspended;
  }

  Vector2 _cellDistanceFromActiveCell(Cell cell) {
    final current = _currentCell;
    if (current == null) return Vector2.zero();
    final diff = (current.center - cell.center)..absolute();
    return Vector2(diff.x / blockSize.width, diff.y / blockSize.height);
  }

  Set<Cell> _findCellsInRadius(Size radius, {bool create = false}) {
    final current = _currentCell;
    if (current == null) throw 'current cell cant be null!';

    Set<Cell> cells = {};
    var tmpDirection = current;
    for (var leftCounter = 1; leftCounter <= radius.width; leftCounter++) {
      if (create) {
        tmpDirection = tmpDirection.left;
      } else {
        final rawLeft = tmpDirection.leftChecked;
        if (rawLeft == null) break;
        tmpDirection = rawLeft;
      }
      cells.add(tmpDirection);

      var topDirection = tmpDirection;
      for (var topCounter = 1;
          topCounter <= min(leftCounter, radius.height);
          topCounter++) {
        if (create) {
          topDirection = topDirection.top;
        } else {
          final rawTop = topDirection.topChecked;
          if (rawTop == null) break;
          topDirection = rawTop;
        }
        cells.add(topDirection);
      }

      var bottomDirection = tmpDirection;
      for (var bottomCounter = 1;
          bottomCounter <= min(leftCounter, radius.height);
          bottomCounter++) {
        if (create) {
          bottomDirection = bottomDirection.bottom;
        } else {
          final rawBottom = bottomDirection.bottomChecked;
          if (rawBottom == null) break;
          bottomDirection = rawBottom;
        }
        cells.add(bottomDirection);
      }
    }

    tmpDirection = current;
    for (var rightCounter = 1; rightCounter <= radius.width; rightCounter++) {
      if (create) {
        tmpDirection = tmpDirection.right;
      } else {
        final rawRight = tmpDirection.rightChecked;
        if (rawRight == null) break;
        tmpDirection = rawRight;
      }
      cells.add(tmpDirection);

      var topDirection = tmpDirection;
      for (var topCounter = 1;
          topCounter <= min(rightCounter, radius.height);
          topCounter++) {
        if (create) {
          topDirection = topDirection.top;
        } else {
          final rawTop = topDirection.topChecked;
          if (rawTop == null) break;
          topDirection = rawTop;
        }
        cells.add(topDirection);
      }

      var bottomDirection = tmpDirection;
      for (var bottomCounter = 1;
          bottomCounter <= min(rightCounter, radius.height);
          bottomCounter++) {
        if (create) {
          bottomDirection = bottomDirection.bottom;
        } else {
          final rawBottom = bottomDirection.bottomChecked;
          if (rawBottom == null) break;
          bottomDirection = rawBottom;
        }
        cells.add(bottomDirection);
      }
    }

    tmpDirection = current;
    for (var topCounter = 1; topCounter <= radius.height; topCounter++) {
      if (create) {
        tmpDirection = tmpDirection.top;
      } else {
        final rawTop = tmpDirection.topChecked;
        if (rawTop == null) break;
        tmpDirection = rawTop;
      }
      cells.add(tmpDirection);

      var leftDirection = tmpDirection;
      for (var leftCounter = 1;
          leftCounter <= min(topCounter, radius.width);
          leftCounter++) {
        if (create) {
          leftDirection = leftDirection.left;
        } else {
          final rawLeft = leftDirection.leftChecked;
          if (rawLeft == null) break;
          leftDirection = rawLeft;
        }
        cells.add(leftDirection);
      }

      var rightDirection = tmpDirection;
      for (var rightCounter = 1;
          rightCounter <= min(topCounter, radius.width);
          rightCounter++) {
        if (create) {
          rightDirection = rightDirection.right;
        } else {
          final rawRight = rightDirection.rightChecked;
          if (rawRight == null) break;
          rightDirection = rawRight;
        }
        cells.add(rightDirection);
      }
    }

    tmpDirection = current;
    for (var bottomCounter = 1;
        bottomCounter <= radius.height;
        bottomCounter++) {
      if (create) {
        tmpDirection = tmpDirection.bottom;
      } else {
        final rawBottom = tmpDirection.bottomChecked;
        if (rawBottom == null) break;
        tmpDirection = rawBottom;
      }
      cells.add(tmpDirection);

      var leftDirection = tmpDirection;
      for (var leftCounter = 1;
          leftCounter <= min(leftCounter, radius.width);
          leftCounter++) {
        if (create) {
          leftDirection = leftDirection.left;
        } else {
          final rawLeft = leftDirection.leftChecked;
          if (rawLeft == null) break;
          leftDirection = rawLeft;
        }
        cells.add(leftDirection);
      }

      var rightDirection = tmpDirection;
      for (var rightCounter = 1;
          rightCounter <= min(rightCounter, radius.width);
          rightCounter++) {
        if (create) {
          rightDirection = rightDirection.right;
        } else {
          final rawRight = rightDirection.rightChecked;
          if (rawRight == null) break;
          rightDirection = rawRight;
        }
        cells.add(rightDirection);
      }
    }
    return cells;
  }

  Cell? findExistingCellByPosition(Vector2 position) {
    final nearest = findNearestCellToPosition(position);
    if (nearest?.rect.containsPoint(position) == true) {
      return nearest;
    }
    return null;
  }

  Cell? findNearestCellToPosition(Vector2 position) {
    double shortestDistance = double.maxFinite;
    Cell? nearestCell;
    for (final cell in cells.entries) {
      final distance = cell.value.center.distanceToSquared(position);
      if (distance < shortestDistance) {
        shortestDistance = distance;
        nearestCell = cell.value;
      }
    }
    return nearestCell;
  }

  Rect getCellRectAtPosition(Vector2 position) {
    final nearest = findNearestCellToPosition(position);
    if (nearest == null) {
      throw "There are no cells probably? Position: $position";
    }

    var startPoint = nearest.center;
    final diff = position - startPoint;
    final xSign = diff.x > 0 ? 1 : -1;
    final ySign = diff.y > 0 ? 1 : -1;
    var moveByX = diff.x.abs();
    var moveByY = diff.y.abs();

    while (moveByX >= blockSize.width / 2) {
      moveByX -= blockSize.width;
      if (xSign > 0) {
        startPoint.x += blockSize.width;
      } else {
        startPoint.x -= blockSize.width;
      }
    }
    while (moveByY >= blockSize.height / 2) {
      moveByY -= blockSize.height;
      if (ySign > 0) {
        startPoint.y += blockSize.height;
      } else {
        startPoint.y -= blockSize.height;
      }
    }

    final rect = Rect.fromCenter(
        center: startPoint.toOffset(),
        width: blockSize.width,
        height: blockSize.height);

    return rect;
  }

  Cell createNewCellAtPosition(Vector2 position) {
    final rect = getCellRectAtPosition(position);

    final existingCell = cells[rect];
    if (existingCell != null) {
      return existingCell;
    }

    final cell = Cell(spatialGrid: this, rect: rect);
    cell.left;
    cell.right;
    cell.top;
    cell.bottom;

    return cell;
  }
}
