import 'dart:collection';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

/// Function type, responsible for cell build: filling new cell by components
/// and adding them into [rootComponent]
typedef CellBuilderFunction = Future<void> Function(
    Cell cell,
    Component rootComponent,
    );

/// Main class, responsible for grid creation, searching grid's cells, changing
/// parameters of grid system, ensures that grid is consistent without holes.
///
/// Usually, you need this class only to change some parameters, all other
/// functionality is mostly for internal use.
///
/// [trackedComponent] is component you system currently follow. It is usually
/// player or place, where main action is happening. If you need to move
/// camera from one component to another - you need to change [trackedComponent]
/// too.
///
/// [currentCell] is the central cell on which [trackedComponent] currently
/// stay. It changes automatically during [trackedComponent] moving so use
/// it as readonly value.
///
class SpatialGrid {
  /// See [HasSpatialGridFramework.initializeSpatialGrid] function for full
  /// description of arguments.
  SpatialGrid({
    required this.blockSize,
    HasGridSupport? trackedComponent,
    Vector2? initialPosition,
    required this.game,
    bool lazyLoad = true,
    Size? activeRadius,
    required Size? unloadRadius,
  }) {
    this.activeRadius = activeRadius ?? const Size(2, 2);
    this.unloadRadius = unloadRadius ?? const Size(5, 5);
    final position =
        trackedComponent?.position ?? initialPosition ?? Vector2(0, 0);

    final cell = Cell(
      spatialGrid: this,
      suspended: lazyLoad,
      rect: Rect.fromCenter(
        center: position.toOffset(),
        width: blockSize.width,
        height: blockSize.height,
      ),
    );

    if (!lazyLoad) {
      currentCell = cell;
    } else {
      _currentCell = cell;
    }

    if (trackedComponent != null) {
      trackedComponent.currentCell = cell;
      this.trackedComponent = trackedComponent;
    }
  }

  void dispose() {
    for (final cell in cells.values) {
      cell.remove();
    }
    cells.clear();
  }

  /// The game on which the grid is built
  final HasSpatialGridFramework game;

  /// Cells storage, readonly please!
  /// Use [findExistingCellByPosition] if you know position in global
  /// coordinates and wand to search for corresponding cells.
  /// Use [findNearestCellToPosition] if you have an position outside of
  /// spatial grid and want to find nearest cell.
  /// Use [getCellRectAtPosition] if you want to calculate, what [Rect] should
  /// have a cell, containing corresponding coordinates
  /// Use [createNewCellAtPosition] if you want to add new cell ingo the grid.
  final cells = HashMap<Rect, Cell>();

  Cell? _currentCell;

  /// The central cell on which [trackedComponent] currently
  /// stay. It changes automatically during [trackedComponent] moving so use
  /// it as readonly value.
  Cell? get currentCell => _currentCell;

  set currentCell(Cell? value) {
    if (value == null) {
      return;
    }
    _currentCell = value;
    updateCellsStateByRadius();
  }

  @internal
  final cellsScheduledToBuild = HashSet<Cell>();

  final Size blockSize;

  HasGridSupport? _trackedComponent;

  /// The component you system currently follow. It is usually
  /// player or place, where main action is happening. If you need to move
  /// camera from one component to another - you need to change
  /// [trackedComponent] too.
  HasGridSupport? get trackedComponent => _trackedComponent;

  set trackedComponent(HasGridSupport? value) {
    _trackedComponent = value;
    final newCell = _trackedComponent?.currentCell;
    if (newCell != null && newCell != _currentCell) {
      currentCell = newCell;
    }
  }

  /// count of active cells ([CellState.active]) around tracked (player's) cell
  /// by X and Y dimensions.
  Size activeRadius = const Size(2, 2);

  /// Count of cells after last active cell (by X and Y
  /// dimensions). These cells will work as usual but all components on it
  /// will be hidden. Such cells are in [CellState.inactive] state.
  /// The rest of grid cells will be moved into [CellState.suspended] state,
  /// when no [Component.updateTree] performed and all cell's components could
  /// be unloaded from memory after some time.
  /// So, unloadRadius specifies count of cells to preserve in
  /// [CellState.inactive] state.
  Size get unloadRadius => _unloadRadius;

  Size _unloadRadius = const Size(5, 5);

  set unloadRadius(Size value) {
    _unloadRadius = value + activeRadius.toOffset();
  }

  /// Updates [Cell.state] of every cell in spatial grid according to values in
  /// [activeRadius] and [unloadRadius], starting from [currentCell] position.
  @internal
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

  /// Recalculates cell's state based on distance from [currentCell].
  @internal
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
    if (current == null) {
      return Vector2.zero();
    }
    final diff = (current.center - cell.center)
      ..absolute();
    return Vector2(diff.x / blockSize.width, diff.y / blockSize.height);
  }

  Set<Cell> _findCellsInRadius(Size radius, {bool create = false}) {
    final current = _currentCell;
    if (current == null) {
      throw 'current cell cant be null!';
    }

    final cells = <Cell>{};
    var tmpDirection = current;
    for (var leftCounter = 1; leftCounter <= radius.width; leftCounter++) {
      if (create) {
        tmpDirection = tmpDirection.left;
      } else {
        final rawLeft = tmpDirection.leftChecked;
        if (rawLeft == null) {
          break;
        }
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
          if (rawTop == null) {
            break;
          }
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
          if (rawBottom == null) {
            break;
          }
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
        if (rawRight == null) {
          break;
        }
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
          if (rawTop == null) {
            break;
          }
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
          if (rawBottom == null) {
            break;
          }
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
        if (rawTop == null) {
          break;
        }
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
          if (rawLeft == null) {
            break;
          }
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
          if (rawRight == null) {
            break;
          }
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
        if (rawBottom == null) {
          break;
        }
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
          if (rawLeft == null) {
            break;
          }
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
          if (rawRight == null) {
            break;
          }
          rightDirection = rawRight;
        }
        cells.add(rightDirection);
      }
    }
    return cells;
  }

  Cell? findExistingCellByPosition(Vector2 position) {
    final nearest = findNearestCellToPosition(position);
    // ignore: use_if_null_to_convert_nulls_to_bools
    if (nearest?.rect.containsPoint(position) == true) {
      return nearest;
    }
    return null;
  }

  Cell? findNearestCellToPosition(Vector2 position) {
    var shortestDistance = double.maxFinite;
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

  /// Cell [Rect] is useful for creating unique cell's keys in hash maps and
  /// hash sets, because only one cell could be in some position.
  Rect getCellRectAtPosition(Vector2 position) {
    final nearest = findNearestCellToPosition(position);
    if (nearest == null) {
      throw 'There are no cells probably? Position: $position';
    }

    final startPoint = nearest.center;
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
      height: blockSize.height,
    );

    return rect;
  }

  /// Use this function if you want to create new cell manually. Do not access
  /// [cells] directly!!!
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
