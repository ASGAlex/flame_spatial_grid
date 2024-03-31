import 'dart:async';
import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/geometry.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/components/macro_object.dart';
import 'package:flutter/foundation.dart';
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
mixin HasGridSupport on PositionComponent
    implements
        MacroObjectInterface,
        ScheduleAfterUpdateMixin,
        ScheduleBeforeUpdateMixin {
  @internal
  static final componentHitboxes = HashMap<ShapeHitbox, HasGridSupport>();

  @internal
  static final cachedCenters = HashMap<ShapeHitbox, Vector2>();

  @internal
  static final defaultCollisionType = HashMap<ShapeHitbox, CollisionType>();

  @internal
  static final shapeHitboxIndex = HashMap<ShapeHitbox, int>();

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

  bool noVisibleChildren = false;
  bool noChildrenToUpdate = false;
  bool checkOutOfCellBounds = true;
  bool needResize = false;

  bool _positionCached = false;
  final _absolutePositionOfCache = Vector2.zero();

  /// If component stay at cell with state [CellState.suspended]
  bool get isSuspended =>
      currentCell != null && currentCell?.state == CellState.suspended;

  @override
  Vector2 get macroSize => boundingBox.macroSize;

  @override
  Vector2 get macroPosition => boundingBox.macroPosition;

  Cell? _currentCell;

  /// Component's current cell. If null - something definitely went wrong!
  Cell? get currentCell => _currentCell;

  void Function(Cell? previousCell)? onCurrentCellChangedCallback;

  void onCurrentCellChanged(Cell? previousCell) {}

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

    CellState? newCellState;
    if (previousCell != null) {
      if (previousCell.isRemoving) {
        return;
      }
      if (_currentCell != null && previousCell.state != _currentCell!.state) {
        newCellState = _currentCell!.state;
      }
    }

    _updateComponentHitboxes(previousCell, newCellState);
    onCurrentCellChanged(previousCell);
    onCurrentCellChangedCallback?.call(previousCell);
  }

  void _updateComponentHitboxes([Cell? previousCell, CellState? newCellState]) {
    final broadphase = spatialGrid?.game?.collisionDetection.broadphase;
    if (broadphase == null) {
      return;
    }
    _updateHitboxesRecursive(
      children.query<ShapeHitbox>(),
      broadphase,
      previousCell,
      newCellState,
    );
  }

  void _updateHitboxesRecursive(
    List<ShapeHitbox> children,
    SpatialGridBroadphase broadphase, [
    Cell? previousCell,
    CellState? newCellState,
  ]) {
    for (final hitbox in children) {
      if (newCellState != null) {
        switch (newCellState) {
          case CellState.active:
          case CellState.inactive:
            Cell.setCollisionTypeForHitbox(hitbox);
            break;
          case CellState.suspended:
            Cell.setCollisionTypeForHitbox(hitbox, CollisionType.inactive);
            break;
        }
      } else {
        // if (previousCell != null) {
        broadphase.updateHitboxIndexes(
          hitbox,
          previousCell,
        );
      }
      // }
      broadphase.saveHitboxCell(hitbox, _currentCell, previousCell);
      if (hitbox.children.isNotEmpty) {
        _updateHitboxesRecursive(
          hitbox.children.query<ShapeHitbox>(),
          broadphase,
          previousCell,
          newCellState,
        );
      }
    }
  }

  SpatialGrid? spatialGrid;

  HasSpatialGridFramework get sgGame {
    Game? game = spatialGrid?.game;
    if (game == null) {
      game = findGame();
      if (game is HasSpatialGridFramework) {
        spatialGrid = game.spatialGrid;
      } else {
        throw 'Spatial grid did not initialized correctly';
      }
      game = spatialGrid?.game;
    }
    return game! as HasSpatialGridFramework;
  }

  /// If this component is that component which all spatial grid system keeps
  /// in center of grid?
  bool get isTracked => this == spatialGrid?.trackedComponent;

  /// Bounding box for component and it's additional hitboxes. By default it is
  /// disabled from collision detection system, but you can change it's
  /// collisionType and defaultCollisionType values.
  BoundingHitbox get boundingBox => _boundingHitbox ??= boundingHitboxFactory();

  BoundingHitbox? _boundingHitbox;

  BoundingHitboxFactory get boundingHitboxFactory => () => BoundingHitbox(
        position: Vector2.zero(),
        size: size,
        parentWithGridSupport: this,
      );

  /// This is the way to reset [onComponentTypeCheck] cache
  BoundingHitbox recreateBoundingHitbox(BoundingHitboxFactory? hitboxFactory) {
    boundingBox.removeFromParent();
    _boundingHitbox = hitboxFactory?.call() ?? boundingHitboxFactory.call();
    add(_boundingHitbox!);
    return _boundingHitbox!;
  }

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
    // ignore: invalid_use_of_protected_member
    if (boundingBox.shouldFillParent) {
      boundingBox.size.setFrom(size);
    }
    add(boundingBox);
    position.addListener(_onPositionChanged);
    return super.onLoad();
  }

  void _onPositionChanged() {
    _positionCached = false;
  }

  @override
  Vector2 absolutePositionOf(Vector2 point) {
    if (_positionCached) {
      return _absolutePositionOfCache;
    } else {
      var parentPoint = positionOf(point);
      var ancestor = parent;
      while (ancestor != null) {
        if (ancestor is PositionComponent) {
          parentPoint = ancestor.positionOf(parentPoint);
        }
        ancestor = ancestor.parent;
      }
      _absolutePositionOfCache.setFrom(parentPoint);
      return _absolutePositionOfCache;
    }
  }

  void onSpatialGridInitialized() {}

  @override
  void onGameResize(Vector2 size) {
    if (sgGame.doOnGameResizeForAllComponents || needResize) {
      super.onGameResize(size);
      needResize = false;
    }
  }

  void onCalculateDistance(
    Component other,
    double distanceX,
    double distanceY,
  ) {}

  @override
  void onChildrenChanged(Component child, ChildrenChangeType type) {
    // ignore: invalid_use_of_protected_member
    if (!boundingBox.shouldFillParent) {
      return;
    }
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
    if (_permanent) {
      scheduleAfterListPermanent.remove(this);
      _actionScheduled = false;
    }

    if (_isOutOfCellBounds && _previousOutOfBoundsCell != null) {
      _decreaseOutOfBoundsCounter(_previousOutOfBoundsCell!);
      _previousOutOfBoundsCell = null;
    }
    if (isTracked) {
      spatialGrid?.trackedComponent = null;
    }

    if (children.query<BoundingHitbox>().isEmpty) {
      // otherwise it will be removed with hitbox removal.
      currentCell = null;
    }
    position.removeListener(_onPositionChanged);
  }

  @override
  void updateTree(double dt) {
    if (_currentCell?.isRemoving == true) {
      removeFromParent();
    }
    if (isSuspended) {
      dtElapsedWhileSuspended += dt;
      updateSuspendedTree(dtElapsedWhileSuspended);
    } else {
      if (noChildrenToUpdate) {
        update(dt);
      } else {
        super.updateTree(dt);
      }
    }
  }

  VoidCallback? onInactiveCallback;

  void onInactive() {}

  VoidCallback? onActiveCallback;

  void onActivate() {}

  /// Called instead of [updateTree] when component is suspended.
  /// [dtElapsedWhileSuspended] accumulates all "dt" values since
  /// component suspension
  void updateSuspendedTree(double dtElapsedWhileSuspended) {}

  /// Called when component state changes to "suspended". You should stop
  /// all undesired component's movements (for example) here
  void onSuspend() {}

  VoidCallback? onSuspendCallback;

  /// Called when component state changes from "suspended" to active.
  /// [dtElapsedWhileSuspended] accumulates all "dt" values since
  /// component suspension. Useful to calculate next animation step as if
  /// the component was never suspended.
  void onResume(double dtElapsedWhileSuspended) {}

  Function(double dtElapsedWhileSuspended)? onResumeCallback;

  @override
  void renderTree(Canvas canvas) {
    if (currentCell?.state == CellState.active) {
      if (noVisibleChildren) {
        decorator.applyChain(render, canvas);
      } else {
        super.renderTree(canvas);
      }
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
    final componentCenter = boundingBox.aabbCenter =
        cachedCenters[boundingBox] = boundingBox.aabb.center;
    var current = currentCell;
    if (kDebugMode && current == null) {
      if (kDebugMode) {
        print('better to set currentCell manually. Component: $runtimeType');
      }
    }

    List<Cell?>? previousCellNeighbours;
    current ??= spatialGrid.findExistingCellByPosition(componentCenter) ??
        spatialGrid.createNewCellAtPosition(componentCenter);
    if (current.rect.containsPoint(componentCenter)) {
      currentCell = current;
    } else {
      Cell? newCell;
      //look close neighbours
      previousCellNeighbours = current.neighbours;
      for (final cell in previousCellNeighbours) {
        if (cell?.rect.containsPoint(componentCenter) == true) {
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

      if (isTracked) {
        spatialGrid.currentCell = newCell;
      }
      currentCell = newCell;
    }
    if (checkOutOfCellBounds) {
      _updateOutOfCellBounds();
    }
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
      cell?.outOfBoundsCounter++;
    }
  }

  void _decreaseOutOfBoundsCounter(Cell centralCell) {
    final cellNeighbours = centralCell.neighboursAndMe;
    for (final cell in cellNeighbours) {
      var outOfBoundsCounter = cell?.outOfBoundsCounter;
      if (outOfBoundsCounter != null) {
        outOfBoundsCounter--;
        cell!.outOfBoundsCounter = outOfBoundsCounter;
        if (outOfBoundsCounter < 0) {
          if (kDebugMode) {
            print('outOfBoundsCounter should not be below zero!');
          }
          cell.outOfBoundsCounter = 0;
        }
      }
    }
  }

  bool pureTypeCheck(PositionComponent other) {
    final myParent = parent;
    final otherParent = other.parent;
    if (myParent is HasGridSupport && otherParent is PositionComponent) {
      return myParent.pureTypeCheck(otherParent);
    }

    return true;
  }

  bool get canBeActive => boundingBox.canBeActive;

  RaycastResult<ShapeHitbox>? raycast(
    Ray2 ray, {
    double? maxDistance,
    List<ShapeHitbox>? ignoreHitboxes,
    List<Type>? ignoreHitboxesTypes,
    List<Type>? allowOnlyHitboxesTypes,
    Type? rayAsHitboxType,
    RaycastResult<ShapeHitbox>? out,
  }) {
    final allHitboxes = ignoreHitboxes ?? <ShapeHitbox>[];
    children.query<BoundingHitbox>().forEach(allHitboxes.add);
    return sgGame.collisionDetection.raycast(
      ray,
      maxDistance: maxDistance,
      ignoreHitboxes: allHitboxes,
      rayAsHitboxType: rayAsHitboxType,
      allowOnlyHitboxesTypes: allowOnlyHitboxesTypes,
      ignoreHitboxesTypes: ignoreHitboxesTypes,
      out: out,
    );
  }

  RaycastResult<ShapeHitbox>? raycastToPoint(
    Vector2 toPoint, {
    Vector2? offset,
    Vector2? offsetTarget,
    double? maxDistance,
    Type? rayAsHitboxType,
    List<ShapeHitbox>? ignoreHitboxes,
    List<Type>? ignoreHitboxesTypes,
    List<Type>? allowOnlyHitboxesTypes,
    RaycastResult<ShapeHitbox>? out,
  }) {
    final from = boundingBox.aabbCenter.clone();
    if (offset != null) {
      from.add(offset);
    }
    if (offsetTarget != null) {
      toPoint.add(offsetTarget);
    }
    final direction = (toPoint - from)..normalize();
    final ray = Ray2(origin: from, direction: direction);
    return raycast(
      ray,
      maxDistance: maxDistance,
      rayAsHitboxType: rayAsHitboxType,
      ignoreHitboxes: ignoreHitboxes,
      allowOnlyHitboxesTypes: allowOnlyHitboxesTypes,
      ignoreHitboxesTypes: ignoreHitboxesTypes,
      out: out,
    );
  }

  RaycastResult<ShapeHitbox>? raycastToComponentCenter(
    HasGridSupport component, {
    Vector2? offset,
    Vector2? offsetTarget,
    double? maxDistance,
    Type? rayAsHitboxType,
    List<ShapeHitbox>? ignoreHitboxes,
    List<Type>? ignoreHitboxesTypes,
    List<Type>? allowOnlyHitboxesTypes,
    RaycastResult<ShapeHitbox>? out,
  }) {
    final centerPoint = component.boundingBox.aabbCenter;

    List<ShapeHitbox>? allHitboxes;
    if (rayAsHitboxType == null) {
      allHitboxes = ignoreHitboxes ?? <ShapeHitbox>[];
      for (final child in component.children.query<BoundingHitbox>()) {
        if (child == component.boundingBox) {
          continue;
        }
        allHitboxes.add(child);
      }
    } else {
      allHitboxes = ignoreHitboxes;
    }
    return raycastToPoint(
      centerPoint,
      offset: offset,
      offsetTarget: offsetTarget,
      ignoreHitboxes: allHitboxes,
      maxDistance: maxDistance,
      rayAsHitboxType: rayAsHitboxType ?? boundingBox.runtimeType,
      allowOnlyHitboxesTypes: allowOnlyHitboxesTypes,
      ignoreHitboxesTypes: ignoreHitboxesTypes,
      out: out,
    );
  }

  List<RaycastResult<ShapeHitbox>?> raycastToComponentCorners(
    HasGridSupport component, {
    Vector2? offset,
    Vector2? offsetTarget,
    double? maxDistance,
    Type? rayAsHitboxType,
    List<ShapeHitbox>? ignoreHitboxes,
    List<Type>? ignoreHitboxesTypes,
    List<Type>? allowOnlyHitboxesTypes,
  }) {
    final allHitboxes = ignoreHitboxes ?? <ShapeHitbox>[];
    for (final child in component.children.query<BoundingHitbox>()) {
      if (child == component.boundingBox) {
        continue;
      }
      allHitboxes.add(child);
    }

    final results = <RaycastResult<ShapeHitbox>?>[];
    final vertices = component.boundingBox.aabb.toRect().toVertices();
    for (final vertex in vertices) {
      results.add(
        raycastToPoint(
          vertex,
          offset: offset,
          offsetTarget: offsetTarget,
          rayAsHitboxType: rayAsHitboxType ?? boundingBox.runtimeType,
          ignoreHitboxes: allHitboxes,
          allowOnlyHitboxesTypes: allowOnlyHitboxesTypes,
          ignoreHitboxesTypes: ignoreHitboxesTypes,
          maxDistance: maxDistance,
        ),
      );
    }
    return results;
  }

  @override
  List<ScheduleAfterUpdateMixin> get scheduleAfterList =>
      sgGame.scheduledAfterUpdate;

  @override
  List<ScheduleAfterUpdateMixin> get scheduleAfterListPermanent =>
      sgGame.scheduledAfterUpdatePermanent;

  @override
  List<ScheduleBeforeUpdateMixin> get scheduleBeforeList =>
      sgGame.scheduledBeforeUpdate;

  @override
  List<ScheduleBeforeUpdateMixin> get scheduleBeforeListPermanent =>
      sgGame.scheduledBeforeUpdatePermanent;

  bool _actionScheduled = false;
  bool _permanent = false;

  @override
  void scheduleAfterUpdateAction({bool permanent = false}) {
    if (!_actionScheduled) {
      if (permanent) {
        _permanent = true;
        scheduleAfterListPermanent.add(this);
      } else {
        try {
          scheduleAfterList.add(this);
          _actionScheduled = true;
        } catch (_) {}
      }
    }
  }

  @override
  void scheduleBeforeUpdateAction({bool permanent = false}) {
    if (!_actionScheduled) {
      if (permanent) {
        _permanent = true;
        scheduleBeforeListPermanent.add(this);
      } else {
        try {
          scheduleBeforeList.add(this);
          _actionScheduled = true;
        } catch (_) {}
      }
    }
  }

  @override
  void runAfterUpdateAction(double dt) {
    if (!_permanent) {
      _actionScheduled = false;
    }
    onAfterUpdate(dt);
  }

  @override
  void onAfterUpdate(double dt) {}

  @override
  void runBeforeUpdateAction(double dt) {
    if (!_permanent) {
      _actionScheduled = false;
    }
    onBeforeUpdate(dt);
  }

  @override
  void onBeforeUpdate(double dt) {}
}

extension PositionComponentWithGridSupport on PositionComponent {
  bool get canBeActive {
    if (this is HasGridSupport) {
      return (this as HasGridSupport).canBeActive;
    }
    final hitbox = children.query<ShapeHitbox>().firstOrNull;
    if (hitbox == null) {
      return false;
    }
    return hitbox.canBeActive;
  }
}
