import 'dart:async';
import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

/// Core mixin of spatial grid framework.
/// This mixin should have EVERY game component, working with spatial grid.
/// Components without this mixin will be hidden from collision detection
/// system.
///
/// The one thing you should do for you game component is to set initial
/// [currentCell]. If [currentCell] is not specified, system try to locate it by
/// searching corresponding cell for component's [position], but it is not cheap
/// operation and you should avoid it while can.
///
/// If component is outside of cells with state [CellState.active], it means
/// that it is outside of viewport and it will be hidden.
/// If component is outside of [SpatialGrid.unloadRadius], it will be suspended.
/// That means that no [updateTree] function would be called for such
/// components, but [updateSuspendedTree] will be called instead. The component
/// is very far from the player and most probably is not reachable, so main game
/// logic os suspended and you have to implement a lightweight one, if needed.
/// It is ok just to ignore it and do not implement anything.
/// If you need to catch a moment when component become suspended, use
/// [onSuspend] function. If you need to catch a moment when component become
/// active again, use [onResume].
///
/// Each component with grid support have default hitbox: [boundingBox].
/// This is required for component's movement tracking and calculating current
/// cells.
/// [boundingBox] could be enabled for checking collisions. If you need this
/// functionality, change it's "collisionType" from default
/// [CollisionType.inactive] value. Additionally, change
/// "boundingBox.defaultCollisionType" to that value too.
/// See [toggleCollisionOnSuspendChange] to discover, why.
///
/// [boundingBox] always has calculated size to include component itself and
/// all component's child components. So if you have an hitbox outside from
/// component, keep in mind that [boundingBox] will contain it too!
///
mixin HasGridSupport on PositionComponent {
  @internal
  static final componentHitboxes = HashMap<ShapeHitbox, HasGridSupport>();

  @internal
  static final cachedCenters = HashMap<ShapeHitbox, Vector2>();

  @internal
  static final defaultCollisionType = HashMap<ShapeHitbox, CollisionType>();

  /// If component's cell state become [CellState.inactive], the component
  /// become inactive too. It also become disabled in collision detection
  /// system, so "boundingBox.collisionType" become [CollisionType.inactive].
  /// After component is restored from suspension, we need to restore it's
  /// previous "collisionType" value. So by default we do this restoration.
  /// You might want to change [toggleCollisionOnSuspendChange] to false if
  /// you know that [boundingBox] should always have state
  /// [CollisionType.inactive] and want to optimise you code a bit.
  /// But you also can just to ignore this parameter.
  bool toggleCollisionOnSuspendChange = true;

  /// If component stay at cell with state [CellState.suspended]
  bool get isSuspended =>
      currentCell != null && currentCell?.state == CellState.suspended;

  Cell? _currentCell;

  /// Component's current cell. If null - something definitely went wrong!
  Cell? get currentCell => _currentCell;

  set currentCell(Cell? value) {
    final previousCell = _currentCell;
    if (previousCell == value) {
      return;
    }
    if (previousCell != null && !previousCell.isRemoving) {
      previousCell.components.remove(this);
    }

    _currentCell = value;

    if (value != null && !value.isRemoving) {
      value.components.add(this);
    }

    if (previousCell == null || previousCell.isRemoving) {
      return;
    }

    _updateComponentHitboxes(previousCell);
  }

  void _updateComponentHitboxes(Cell previousCell) {
    for (final hitbox in children) {
      if (hitbox is! ShapeHitbox) {
        continue;
      }
      spatialGrid?.game.collisionDetection.broadphase
          .updateHitboxIndexes(hitbox, previousCell);
    }
  }

  SpatialGrid? spatialGrid;

  HasSpatialGridFramework get sgGame {
    final game = spatialGrid?.game;
    if (game == null) {
      throw 'Spatial grid did not initialized correctly';
    }
    return game;
  }

  /// If this component is that component which all spatial grid system keeps
  /// in center of grid?
  bool get isTracked => this == spatialGrid?.trackedComponent;

  /// Bounding box for component and it's additional hitboxes. By default it is
  /// disabled from collision detection system, but you can change it's
  /// collisionType and defaultCollisionType values.
  late final boundingBox = BoundingHitbox(
    position: Vector2.zero(),
    size: Vector2.zero(),
    parentWithGridSupport: this,
  )..collisionType = CollisionType.inactive;

  @internal
  double dtElapsedWhileSuspended = 0;

  // bool _isOutOfCellBoundsPrevious = false;
  bool _isOutOfCellBounds = false;

  /// If component fully lays inside cell bounds or overlaps other cells?
  bool get isOutOfCellBounds => _isOutOfCellBounds;

  /// [boundingBox] initialisation provided here. It is absolutely necessary for
  /// keeping framework to work correctly, so please never forgot to call
  /// super.onLoad in yours onLoad functions!
  @override
  @mustCallSuper
  FutureOr<void>? onLoad() {
    boundingBox.size.setFrom(size);
    add(boundingBox);
    return null;
  }

  void onCalculateDistance(
    Component other,
    double distanceX,
    double distanceY,
  ) {}

  @override
  void onChildrenChanged(Component child, ChildrenChangeType type) {
    if (type == ChildrenChangeType.added) {
      if (child != boundingBox && child is ShapeHitbox) {
        boundingBox.resizeToIncludeChildren(child);
      }
    } else {
      boundingBox.resizeToIncludeChildren();
    }
  }

  @override
  @mustCallSuper
  void onRemove() {
    if (_isOutOfCellBounds && _previousOutOfBoundsCell != null) {
      _decreaseOutOfBoundsCounter(_previousOutOfBoundsCell!);
      _previousOutOfBoundsCell = null;
    }
    if (isTracked) {
      spatialGrid?.trackedComponent = null;
    }

    if (children.whereType<BoundingHitbox>().isEmpty) {
      // otherwise it will be removed with hitbox removal.
      currentCell = null;
    }
  }

  @override
  void updateTree(double dt) {
    if (currentCell == null || _currentCell!.isRemoving) {
      removeFromParent();
    }
    if (isSuspended) {
      dtElapsedWhileSuspended += dt;
      updateSuspendedTree(dtElapsedWhileSuspended);
    } else {
      super.updateTree(dt);
    }
  }

  /// Called instead of [updateTree] when component is suspended.
  /// [dtElapsedWhileSuspended] accumulates all "dt" values since
  /// component suspension
  void updateSuspendedTree(double dtElapsedWhileSuspended) {}

  /// Called when component state changes to "suspended". You should stop
  /// all undesired component's movements (for example) here
  void onSuspend() {}

  /// Called when component state changes from "suspended" to active.
  /// [dtElapsedWhileSuspended] accumulates all "dt" values since
  /// component suspension. Useful to calculate next animation step as if
  /// the component was never suspended.
  void onResume(double dtElapsedWhileSuspended) {}

  @override
  void renderTree(Canvas canvas) {
    if (currentCell?.state == CellState.active) {
      super.renderTree(canvas);
    } else if (debugMode) {
      decorator.applyChain(renderDebugMode, canvas);
    }
  }

  /// This is called on every [boundingBox]'s aabb recalculation. If bounding
  /// box was mover or resized - it is necessary to recalculate component's
  /// [currentCell], probably create new one...
  @internal
  void updateTransform() {
    final spatialGrid = this.spatialGrid;
    if (spatialGrid == null) {
      return;
    }
    boundingBox.aabbCenter = boundingBox.aabb.center;
    cachedCenters.remove(boundingBox);
    final componentCenter = boundingBox.aabbCenter;
    var current = currentCell;
    List<Cell>? previousCellNeighbours;
    current ??= spatialGrid.findExistingCellByPosition(componentCenter) ??
        spatialGrid.createNewCellAtPosition(componentCenter);
    if (current.rect.containsPoint(componentCenter)) {
      currentCell = current;
    } else {
      Cell? newCell;
      //look close neighbours
      previousCellNeighbours = current.neighbours;
      for (final cell in previousCellNeighbours) {
        if (cell.rect.containsPoint(componentCenter)) {
          newCell = cell;
          break;
        }
      }
      //if nothing - search among all cells
      if (newCell == null) {
        previousCellNeighbours = null;
        for (final cell in spatialGrid.cells.entries) {
          if (cell.value.rect.containsPoint(componentCenter)) {
            newCell = cell.value;
            break;
          }
        }
      }
      //if nothing again - try to locate new cell's position from component's
      //coordinates
      newCell ??= spatialGrid.createNewCellAtPosition(componentCenter);

      currentCell = newCell;
      if (isTracked) {
        spatialGrid.currentCell = newCell;
      }
    }
    _updateOutOfCellBounds();
  }

  Cell? _previousOutOfBoundsCell;

  void _updateOutOfCellBounds() {
    final current = currentCell;
    if (boundingBox.size.isZero() ||
        boundingBox.collisionType == CollisionType.inactive ||
        current == null) {
      _isOutOfCellBounds = false;
      return;
    }
    _isOutOfCellBounds = !boundingBox.isFullyInsideRect(current.rect);
    if (_isOutOfCellBounds) {
      if (current != _previousOutOfBoundsCell) {
        if (_previousOutOfBoundsCell != null) {
          _decreaseOutOfBoundsCounter(_previousOutOfBoundsCell!);
        }
        _increaseOutOfBoundsCounter(current);
      }
      _previousOutOfBoundsCell = current;
    } else {
      if (_previousOutOfBoundsCell != null) {
        _decreaseOutOfBoundsCounter(_previousOutOfBoundsCell!);
      }
      _previousOutOfBoundsCell = null;
      // _decreaseOutOfBoundsCounter(current);
    }
  }

  void _increaseOutOfBoundsCounter(Cell centralCell) {
    final cellNeighbours = centralCell.neighboursAndMe;
    for (final cell in cellNeighbours) {
      cell.outOfBoundsCounter++;
    }
  }

  void _decreaseOutOfBoundsCounter(Cell centralCell) {
    final cellNeighbours = centralCell.neighboursAndMe;
    for (final cell in cellNeighbours) {
      cell.outOfBoundsCounter--;
      if (cell.outOfBoundsCounter < 0) {
        print('outOfBoundsCounter should not be below zero!');
        cell.outOfBoundsCounter = 0;
      }
    }
  }
}
