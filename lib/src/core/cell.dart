import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

enum _CellCreationContext { left, top, right, bottom }

enum CellState { active, inactive, suspended }

class Cell {
  Cell(
      {required this.spatialGrid, required this.rect, bool suspended = false}) {
    center = rect.center.toVector2();
    spatialGrid.cells[rect] = this;

    rawLeft = _checkCell(_CellCreationContext.left);
    rawRight = _checkCell(_CellCreationContext.right);
    rawTop = _checkCell(_CellCreationContext.top);
    rawBottom = _checkCell(_CellCreationContext.bottom);

    if (suspended) {
      state = CellState.suspended;
      _scheduleToBuild = true;
    } else {
      state = spatialGrid.getCellState(this);
      if (state == CellState.suspended) {
        _scheduleToBuild = true;
      } else {
        spatialGrid.cellsScheduledToBuild.add(this);
      }
    }
  }

  bool _scheduleToBuild = false;
  bool _remove = false;
  final SpatialGrid spatialGrid;
  final Rect rect;
  late final Vector2 center;

  final _state = ValueNotifier<CellState>(CellState.active);

  final components = HashSet<HasGridSupport>();

  get broadphase => spatialGrid.game.collisionDetection.broadphase;

  Cell? get rawLeft => _rawLeft?._remove == true ? null : _rawLeft;

  Cell? get rawRight => _rawRight?._remove == true ? null : _rawRight;

  Cell? get rawTop => _rawTop?._remove == true ? null : _rawTop;

  Cell? get rawBottom => _rawBottom?._remove == true ? null : _rawBottom;

  set rawLeft(Cell? value) {
    _rawLeft = value;
  }

  set rawRight(Cell? value) {
    _rawRight = value;
  }

  set rawTop(Cell? value) {
    _rawTop = value;
  }

  set rawBottom(Cell? value) {
    _rawBottom = value;
  }

  Cell? _rawLeft;
  Cell? _rawRight;
  Cell? _rawTop;
  Cell? _rawBottom;

  double beingSuspendedTimeMicroseconds = 0;

  final _cachedRects = <_CellCreationContext, Rect>{};

  Cell? get leftChecked => rawLeft ??= _checkCell(_CellCreationContext.left);

  Cell? get rightChecked => rawRight ??= _checkCell(_CellCreationContext.right);

  Cell? get topChecked => rawTop ??= _checkCell(_CellCreationContext.top);

  Cell? get bottomChecked =>
      rawBottom ??= _checkCell(_CellCreationContext.bottom);

  Cell get left => rawLeft ??= _createCell(_CellCreationContext.left);

  Cell get right => rawRight ??= _createCell(_CellCreationContext.right);

  Cell get top => rawTop ??= _createCell(_CellCreationContext.top);

  Cell get bottom => rawBottom ??= _createCell(_CellCreationContext.bottom);

  CellState get state => _state.value;

  CellState tmpState = CellState.active;

  set state(CellState value) {
    if (_state.value == value) return;

    _state.value = value;
    if (_state.value != CellState.suspended && _scheduleToBuild) {
      spatialGrid.cellsScheduledToBuild.add(this);
      _scheduleToBuild = false;
    }
    updateComponentsState();
  }

  @internal
  void updateComponentsState() {
    switch (_state.value) {
      case CellState.active:
        beingSuspendedTimeMicroseconds = 0;
        _activateComponents();
        break;
      case CellState.inactive:
        beingSuspendedTimeMicroseconds = 0;
        _deactivateComponents();
        break;
      case CellState.suspended:
        _suspendComponents();
        break;
    }
  }

  void _activateComponents() {
    for (final component in components) {
      component.isSuspended = false;
      component.isVisible = true;
      final hitboxes = component.children.whereType<ShapeHitbox>();
      for (final hitbox in hitboxes) {
        if (component.toggleCollisionOnSuspendChange) {
          hitbox.collisionType = hitbox.defaultCollisionType;
        }
      }
    }
  }

  void _deactivateComponents() {
    for (final component in components) {
      component.isVisible = false;
      final hitboxes = component.children.whereType<ShapeHitbox>();
      for (final hitbox in hitboxes) {
        if (component.toggleCollisionOnSuspendChange) {
          hitbox.collisionType = hitbox.defaultCollisionType;
        }
      }
    }
  }

  void _suspendComponents() {
    for (final component in components) {
      component.isSuspended = true;
      component.isVisible = false;
      final hitboxes = component.children.whereType<ShapeHitbox>();

      for (final hitbox in hitboxes) {
        if (component.toggleCollisionOnSuspendChange) {
          hitbox.collisionType = CollisionType.inactive;
        }
      }
    }
  }

  void remove() {
    _remove = true;
    rawLeft?.rawRight = null;
    rawLeft = null;
    rawRight?.rawLeft = null;
    rawRight = null;
    rawTop?.rawBottom = null;
    rawTop = null;
    rawBottom?.rawTop = null;
    rawBottom = null;

    spatialGrid.cells.remove(rect);
    for (final component in components) {
      component.removeFromParent();
    }
    _state.dispose();
  }

  Cell _createCell(_CellCreationContext direction) =>
      _checkCell(direction) ??
      Cell(spatialGrid: spatialGrid, rect: _createRectForDirection(direction));

  Cell? _checkCell(_CellCreationContext direction) {
    final cell = spatialGrid.cells[_createRectForDirection(direction)];
    if (cell?._remove == true) {
      spatialGrid.cells.remove(cell?.rect);
      return null;
    }
    return cell;
  }

  Rect _createRectForDirection(_CellCreationContext creationContext) {
    var newRect = _cachedRects[creationContext];
    if (newRect == null) {
      final width = spatialGrid.blockSize.width;
      final height = spatialGrid.blockSize.height;
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
}
