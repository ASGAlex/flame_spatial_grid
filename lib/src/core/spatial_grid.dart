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
  Iterable<Rect> rectsOfMap,
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
    required this.cellSize,
    HasGridSupport? trackedComponent,
    Vector2? initialPosition,
    this.game,
    bool lazyLoad = true,
    Size? activeRadius,
    Size? unloadRadius,
    Size? preloadRadius,
  }) {
    this.activeRadius = activeRadius ?? const Size(2, 2);
    this.unloadRadius = unloadRadius ?? const Size(5, 5);
    this.preloadRadius = preloadRadius ?? const Size(5, 5);
    final position =
        initialPosition ?? trackedComponent?.position ?? Vector2(0, 0);

    final cell = Cell(
      spatialGrid: this,
      suspended: lazyLoad,
      rect: getCellRectAtPosition(position),
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
    for (final cell in cells.values.toList(growable: false)) {
      cell.remove();
    }
    cells.clear();
    _currentCell = null;
  }

  /// The game on which the grid is built
  final HasSpatialGridFramework? game;

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
  Cell? _previousCell;

  /// The central cell on which [trackedComponent] currently
  /// stay. It changes automatically during [trackedComponent] moving so use
  /// it as readonly value.
  Cell? get currentCell => _currentCell;

  set currentCell(Cell? value) {
    if (value == null || _currentCell == value) {
      return;
    }
    _previousCell = _currentCell;
    _currentCell = value;

    if (_previousCell == _currentCell!.left) {
      _updateCellsAfterMovementToNeighbour(Direction.right);
    } else if (_previousCell == _currentCell!.right) {
      _updateCellsAfterMovementToNeighbour(Direction.left);
    } else if (_previousCell == _currentCell!.top) {
      _updateCellsAfterMovementToNeighbour(Direction.bottom);
    } else if (_previousCell == _currentCell!.bottom) {
      _updateCellsAfterMovementToNeighbour(Direction.top);
    } else {
      updateCellsStateByRadius(fullScan: false);
    }
  }

  @internal
  final cellsScheduledToBuild = Queue<Cell>();

  final Size cellSize;

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

  Set<Cell> get activeRadiusCells {
    if (currentCell == null) {
      return <Cell>{};
    }
    return _findCellsInRadius(activeRadius, initialCell: currentCell)
      ..add(currentCell!);
  }

  /// Count of cells after last active cell (by X and Y
  /// dimensions). These cells will work as usual but all components on it
  /// will be hidden. Such cells are in [CellState.inactive] state.
  /// The rest of grid cells will be moved into [CellState.suspended] state,
  /// when no [Component.updateTree] performed and all cell's components could
  /// be unloaded from memory after some time.
  /// So, unloadRadius specifies count of cells to preserve in
  /// [CellState.inactive] state.
  Size get unloadRadius => _unloadRadius;

  Set<Cell> get unloadRadiusCells {
    if (currentCell == null) {
      return <Cell>{};
    }
    return _findCellsInRadius(unloadRadius, initialCell: currentCell)
      ..add(currentCell!);
  }

  Size _unloadRadius = const Size(5, 5);

  set unloadRadius(Size value) {
    _unloadRadius = value + activeRadius.toOffset();
  }

  Size get preloadRadius => _preloadRadius;

  Set<Cell> get preloadRadiusCells {
    if (currentCell == null) {
      return <Cell>{};
    }
    return _findCellsInRadius(preloadRadius, initialCell: currentCell)
      ..add(currentCell!);
  }

  Size _preloadRadius = const Size(5, 5);

  set preloadRadius(Size value) {
    _preloadRadius = value + _unloadRadius.toOffset();
  }

  void _updateCellsAfterMovementToNeighbour(Direction direction) {
    final current = _currentCell;
    if (current == null) {
      throw 'current cell cant be null!';
    }
    var counterActiveRadius = 0;
    var counterActiveRadiusCrossAxis = 0;
    var counterUnloadRadius = 0;
    var counterUnloadRadiusCrossAxis = 0;
    switch (direction) {
      case Direction.left:
      case Direction.right:
        counterActiveRadius = activeRadius.width.toInt();
        counterUnloadRadius =
            counterActiveRadius + unloadRadius.width.toInt() - 2;
        counterActiveRadiusCrossAxis = activeRadius.height.toInt();
        counterUnloadRadiusCrossAxis =
            counterActiveRadiusCrossAxis + unloadRadius.height.toInt() - 2;
        break;

      case Direction.top:
      case Direction.bottom:
        counterActiveRadius = activeRadius.height.toInt();
        counterUnloadRadius =
            counterActiveRadius + unloadRadius.height.toInt() - 2;
        counterActiveRadiusCrossAxis = activeRadius.width.toInt();
        counterUnloadRadiusCrossAxis =
            counterActiveRadiusCrossAxis + unloadRadius.width.toInt() - 2;
    }

    // 1. find previous line of cells with unloadRadius and suspend
    _findLineAndChangeState(
      distance: counterUnloadRadius + 1,
      crossAxisDistance: counterUnloadRadiusCrossAxis + 1,
      direction: direction.opposite(),
      newState: CellState.suspended,
    );
    // 2. find previous line of cells with activeRadius and inactivate
    _findLineAndChangeState(
      distance: counterActiveRadius + 1,
      crossAxisDistance: counterActiveRadiusCrossAxis + 1,
      direction: direction.opposite(),
      newState: CellState.inactive,
    );
    // 3. find next line of cells with unloadRadius and inactivate
    _findLineAndChangeState(
      distance: counterUnloadRadius,
      crossAxisDistance: counterUnloadRadiusCrossAxis,
      direction: direction,
      newState: CellState.inactive,
    );
    // 4. find next line of cells with activeRadius and activate
    _findLineAndChangeState(
      distance: counterActiveRadius,
      crossAxisDistance: counterActiveRadiusCrossAxis,
      direction: direction,
      newState: CellState.active,
    );
  }

  void _findLineAndChangeState({
    required int distance,
    required int crossAxisDistance,
    required Direction direction,
    required CellState newState,
  }) {
    final current = _currentCell;
    if (current == null) {
      throw 'current cell cant be null!';
    }

    var tmpCell = current;
    for (var i = 0; i < distance; i++) {
      switch (direction) {
        case Direction.left:
          tmpCell = tmpCell.left;
          break;
        case Direction.right:
          tmpCell = tmpCell.right;
          break;
        case Direction.top:
          tmpCell = tmpCell.top;
          break;
        case Direction.bottom:
          tmpCell = tmpCell.bottom;
          break;
      }
    }
    final centralCell = tmpCell;
    centralCell.state = newState;
    if (direction == Direction.left || direction == Direction.right) {
      for (var i = 0; i < crossAxisDistance; i++) {
        tmpCell = tmpCell.top;
        tmpCell.state = newState;
      }
      tmpCell = centralCell;
      for (var i = 0; i < crossAxisDistance; i++) {
        tmpCell = tmpCell.bottom;
        tmpCell.state = newState;
      }
    } else {
      for (var i = 0; i < crossAxisDistance; i++) {
        tmpCell = tmpCell.left;
        tmpCell.state = newState;
      }
      tmpCell = centralCell;
      for (var i = 0; i < crossAxisDistance; i++) {
        tmpCell = tmpCell.right;
        tmpCell.state = newState;
      }
    }
  }

  /// Updates [Cell.state] of every cell in spatial grid according to values in
  /// [activeRadius] and [unloadRadius], starting from [currentCell] position.
  @internal
  void updateCellsStateByRadius({required bool fullScan}) {
    final cellsToActivate = _findCellsInRadius(activeRadius, create: true);
    var newCellsCreated = false;
    for (final cell in cellsToActivate) {
      if (!cell.isCellBuildFinished) {
        newCellsCreated = true;
        break;
      }
    }

    if (newCellsCreated) {
      _createCellsInPreloadRadius();
    }
    final previousCells = <Cell>[];
    if (fullScan) {
      for (final cell in cells.values) {
        cell.tmpState = CellState.suspended;
      }
    } else {
      previousCells.addAll(
        _findCellsInRadius(
          unloadRadius,
          initialCell: _previousCell,
        ),
      );
      for (final cell in previousCells) {
        cell.tmpState = CellState.suspended;
      }
    }

    final cellsToInactivate = _findCellsInRadius(unloadRadius);
    for (final cell in cellsToInactivate) {
      cell.tmpState = CellState.inactive;
    }

    for (final cell in cellsToActivate) {
      cell.tmpState = CellState.active;
    }
    _currentCell?.tmpState = CellState.active;

    if (fullScan) {
      for (final cell in cells.values) {
        cell.state = cell.tmpState;
      }
    } else {
      final allAffectedCells = <Cell>[
        ...cellsToActivate,
        ...previousCells,
        ...cellsToInactivate,
      ];
      for (final cell in allAffectedCells) {
        cell.state = cell.tmpState;
      }
    }
  }

  void _createCellsInPreloadRadius() {
    final cellsToPreload = _findCellsInRadius(preloadRadius, create: true);
    for (final cell in cellsToPreload) {
      cell.state = CellState.inactive;
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
    final diff = (current.center - cell.center)..absolute();
    return Vector2(diff.x / cellSize.width, diff.y / cellSize.height);
  }

  Set<Cell> _findCellsInRadius(
    Size radius, {
    Cell? initialCell,
    bool create = false,
  }) {
    final current = initialCell ?? _currentCell;
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
    if (cells.isEmpty) {
      return _createRectWithLimitedPrecision(
        Vector2(position.x.floorToDouble(), position.y.floorToDouble()),
      );
    }

    final nearest = findNearestCellToPosition(position);
    if (nearest == null) {
      throw 'There are no cells probably? Position: $position';
    }
    if (nearest.rect.containsPoint(position) == true) {
      return nearest.rect;
    }

    final startPoint = nearest.center;
    final diff = position - startPoint;
    final xSign = diff.x > 0 ? 1 : -1;
    final ySign = diff.y > 0 ? 1 : -1;
    var moveByX = diff.x.abs();
    var moveByY = diff.y.abs();

    while (moveByX >= cellSize.width / 2) {
      moveByX -= cellSize.width;
      if (xSign > 0) {
        startPoint.x += cellSize.width;
      } else {
        startPoint.x -= cellSize.width;
      }
    }
    while (moveByY >= cellSize.height / 2) {
      moveByY -= cellSize.height;
      if (ySign > 0) {
        startPoint.y += cellSize.height;
      } else {
        startPoint.y -= cellSize.height;
      }
    }

    return _createRectWithLimitedPrecision(startPoint);
  }

  Rect _createRectWithLimitedPrecision(Vector2 center) {
    final rect = Rect.fromCenter(
      center: center.toOffset(),
      width: cellSize.width,
      height: cellSize.height,
    );

    return rect.toRounded();
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

  List<Cell> findCellsInRect(Rect rect) {
    var rowCell = findExistingCellByPosition(rect.topLeft.toVector2()) ??
        createNewCellAtPosition(rect.topLeft.toVector2());
    var cell = rowCell.right;
    final cellsInRect = <Cell>[];

    while (rowCell.rect.top <= rect.bottom) {
      cellsInRect.add(rowCell);
      while (cell.rect.left <= rect.right) {
        cellsInRect.add(cell);
        cell = cell.right;
      }
      rowCell = rowCell.bottom;
      cell = rowCell.right;
    }
    return cellsInRect;
  }
}
