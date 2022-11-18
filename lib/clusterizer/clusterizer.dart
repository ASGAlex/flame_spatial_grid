import 'package:cluisterizer_test/clusterizer/cell_builder.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/foundation.dart';

import 'cell.dart';

class Clusterizer extends ChangeNotifier {
  Clusterizer(
      {required this.blockSize,
      required this.trackedComponent,
      this.cellBuilder,
      int? activeRadius,
      int? unloadRadius}) {
    this.activeRadius = (activeRadius ?? 1);
    this.unloadRadius = (unloadRadius ?? 10);
    final cell = Cell(
        clusterizer: this,
        rect: Rect.fromCenter(
            center: trackedComponent.position.toOffset(),
            width: blockSize.width,
            height: blockSize.height));
    cell.left;
    cell.right;
    cell.top;
    cell.bottom;

    _currentCell = cell;
    trackedComponent.transform.addListener(_onTrackedComponentTransform);
  }

  @override
  dispose() {
    trackedComponent.transform.removeListener(_onTrackedComponentTransform);
    for (var cell in cells.values) {
      cell.dispose();
    }
    cells.clear();
    super.dispose();
  }

  final cells = <Rect, Cell>{};
  Cell? _currentCell;
  CellBuilder? cellBuilder;

  final Size blockSize;
  final PositionComponent trackedComponent;

  var activeRadius = 1;
  var unloadRadius = 3;

  void _onTrackedComponentTransform() {
    final lookAtPoint = trackedComponent.toRect().center.toVector2();
    final current = _currentCell;
    if (current == null) throw 'current cell cant be null!';
    if (current.rect.containsPoint(lookAtPoint) != true) {
      Cell? newCell;
      //look close neighbours
      for (var cell in current.neighbours) {
        if (cell.rect.containsPoint(lookAtPoint)) {
          newCell = cell;
          break;
        }
      }
      //if nothing - search among all cells
      if (newCell == null) {
        for (var cell in cells.entries) {
          if (cell.value.rect.containsPoint(lookAtPoint)) {
            newCell = cell.value;
            break;
          }
        }
      }
      //should be impossible
      if (newCell == null) {
        throw 'error finding new cell';
      }
      newCell.left;
      newCell.right;
      newCell.top;
      newCell.bottom;
      _currentCell = newCell;
      for (var cell in cells.values) {
        cell.state = CellState.suspended;
      }

      final cellsToInactivate = _findCellsInRadius(unloadRadius);
      for (var cell in cellsToInactivate) {
        cell.state = CellState.inactive;
      }

      final cellsToActivate = _findCellsInRadius(activeRadius, create: true);
      for (var cell in cellsToActivate) {
        cell.state = CellState.active;
      }
      _currentCell?.state = CellState.active;
      notifyListeners();
    }
  }

  Set<Cell> _findCellsInRadius(int radius, {bool create = false}) {
    final current = _currentCell;
    if (current == null) throw 'current cell cant be null!';

    Set<Cell> cells = {};
    var tmpDirection = current;
    for (var leftCounter = 1; leftCounter <= radius; leftCounter++) {
      if (create) {
        tmpDirection = tmpDirection.left;
      } else {
        final rawLeft = tmpDirection.rawLeft;
        if (rawLeft == null) break;
        tmpDirection = rawLeft;
      }
      cells.add(tmpDirection);

      var topDirection = tmpDirection;
      for (var topCounter = 1; topCounter <= leftCounter; topCounter++) {
        if (create) {
          topDirection = topDirection.top;
        } else {
          final rawTop = topDirection.rawTop;
          if (rawTop == null) break;
          topDirection = rawTop;
        }
        cells.add(topDirection);
      }

      var bottomDirection = tmpDirection;
      for (var bottomCounter = 1;
          bottomCounter <= leftCounter;
          bottomCounter++) {
        if (create) {
          bottomDirection = bottomDirection.bottom;
        } else {
          final rawBottom = bottomDirection.rawBottom;
          if (rawBottom == null) break;
          bottomDirection = rawBottom;
        }
        cells.add(bottomDirection);
      }
    }

    tmpDirection = current;
    for (var rightCounter = 1; rightCounter <= radius; rightCounter++) {
      if (create) {
        tmpDirection = tmpDirection.right;
      } else {
        final rawRight = tmpDirection.rawRight;
        if (rawRight == null) break;
        tmpDirection = rawRight;
      }
      cells.add(tmpDirection);

      var topDirection = tmpDirection;
      for (var topCounter = 1; topCounter <= rightCounter; topCounter++) {
        if (create) {
          topDirection = topDirection.top;
        } else {
          final rawTop = topDirection.rawTop;
          if (rawTop == null) break;
          topDirection = rawTop;
        }
        cells.add(topDirection);
      }

      var bottomDirection = tmpDirection;
      for (var bottomCounter = 1;
          bottomCounter <= rightCounter;
          bottomCounter++) {
        if (create) {
          bottomDirection = bottomDirection.bottom;
        } else {
          final rawBottom = bottomDirection.rawBottom;
          if (rawBottom == null) break;
          bottomDirection = rawBottom;
        }
        cells.add(bottomDirection);
      }
    }

    tmpDirection = current;
    for (var topCounter = 1; topCounter <= radius; topCounter++) {
      if (create) {
        tmpDirection = tmpDirection.top;
      } else {
        final rawTop = tmpDirection.rawTop;
        if (rawTop == null) break;
        tmpDirection = rawTop;
      }
      cells.add(tmpDirection);

      var leftDirection = tmpDirection;
      for (var leftCounter = 1; leftCounter <= topCounter; leftCounter++) {
        if (create) {
          leftDirection = leftDirection.left;
        } else {
          final rawLeft = leftDirection.rawLeft;
          if (rawLeft == null) break;
          leftDirection = rawLeft;
        }
        cells.add(leftDirection);
      }

      var rightDirection = tmpDirection;
      for (var rightCounter = 1; rightCounter <= topCounter; rightCounter++) {
        if (create) {
          rightDirection = rightDirection.right;
        } else {
          final rawRight = rightDirection.rawRight;
          if (rawRight == null) break;
          rightDirection = rawRight;
        }
        cells.add(rightDirection);
      }
    }

    tmpDirection = current;
    for (var bottomCounter = 1; bottomCounter <= radius; bottomCounter++) {
      if (create) {
        tmpDirection = tmpDirection.bottom;
      } else {
        final rawBottom = tmpDirection.rawBottom;
        if (rawBottom == null) break;
        tmpDirection = rawBottom;
      }
      cells.add(tmpDirection);

      var leftDirection = tmpDirection;
      for (var leftCounter = 1; leftCounter <= bottomCounter; leftCounter++) {
        if (create) {
          leftDirection = leftDirection.left;
        } else {
          final rawLeft = leftDirection.rawLeft;
          if (rawLeft == null) break;
          leftDirection = rawLeft;
        }
        cells.add(leftDirection);
      }

      var rightDirection = tmpDirection;
      for (var rightCounter = 1;
          rightCounter <= bottomCounter;
          rightCounter++) {
        if (create) {
          rightDirection = rightDirection.right;
        } else {
          final rawRight = rightDirection.rawRight;
          if (rawRight == null) break;
          rightDirection = rawRight;
        }
        cells.add(rightDirection);
      }
    }
    return cells;
  }

  Cell? findCellByPosition(Vector2 position) {
    for (final cell in cells.entries) {
      if (cell.value.rect.containsPoint(position)) return cell.value;
    }
    return null;
  }
}
