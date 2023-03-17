// ignore_for_file: use_if_null_to_convert_nulls_to_bools, comment_references

import 'dart:collection';

import 'package:flame/collisions.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

enum _CellCreationContext { left, top, right, bottom }

/// The state controls cell's lifecycle and how many resources it consumes
enum CellState {
  /// Active cells - cells you usually see at the screen. Everything works
  /// here as in ordinary Flame game.
  active,

  /// This cells are usually out of the screen, so no components are displayed,
  /// [Component.renderTree] is completely omitted for components inside such
  /// cells. See [HasGridSupport] for details.
  inactive,

  /// This kind of cells are very far from player. Usually, player did there
  /// at past but then left these cells. Fot such cells [Component.updateTree]
  /// is omitted to preserve CPU resources. See [HasGridSupport] for details.
  suspended
}

/// Cell is the rect (quad) of game space, connected with it's neighbors at
/// left, right, top and bottom.
/// This class stores cell information and automates new cells creation,makes
/// easier querying cell's components for collision detection system.
///
/// Usually you do not need to use any of it's methods. But you absolutely
/// should to ensure that component's [HasGridSupport.currentCell] is not null.
class Cell {
  Cell({
    required this.spatialGrid,
    required this.rect,
    bool suspended = false,
  }) {
    center = rect.center.toVector2();
    spatialGrid.cells[rect] = this;

    rawLeft = _checkCell(_CellCreationContext.left);
    rawRight = _checkCell(_CellCreationContext.right);
    rawTop = _checkCell(_CellCreationContext.top);
    rawBottom = _checkCell(_CellCreationContext.bottom);

    if (suspended) {
      state = CellState.suspended;
    } else {
      state = spatialGrid.getCellState(this);
    }
  }

  bool _isCellBuildFinished = false;

  bool get isCellBuildFinished => _isCellBuildFinished;

  set isCellBuildFinished(bool value) {
    _isCellBuildFinished = value;
    final layers = spatialGrid.game.layersManager.layers[this];
    if (layers != null && layers.isNotEmpty && value == true) {
      for (final layer in layers.values) {
        layer.isUpdateNeeded = true;
      }
    }
  }

  bool _remove = false;

  bool get isRemoving => _remove;

  final SpatialGrid spatialGrid;
  final Rect rect;

  /// Cell's central point.
  late final Vector2 center;

  var _state = CellState.suspended;

  /// Collection of component currently places inside this cell.
  /// Should not be modified manually!
  final components = HashSet<HasGridSupport>();

  /// Left cell from current, or null
  Cell? get rawLeft => _rawLeft?._remove == true ? null : _rawLeft;

  /// Right cell from current, or null
  Cell? get rawRight => _rawRight?._remove == true ? null : _rawRight;

  /// Top cell from current, or null
  Cell? get rawTop => _rawTop?._remove == true ? null : _rawTop;

  /// Bottom cell from current, or null
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

  /// A time in microseconds from the moment when cell's state was changed into
  /// [CellState.suspended].
  /// See [updateComponentsState] too.
  double beingSuspendedTimeMicroseconds = 0;

  final _cachedRects = <_CellCreationContext, Rect>{};

  /// Existing left cell if not scheduled for removal, otherwise null
  Cell? get leftChecked => rawLeft ??= _checkCell(_CellCreationContext.left);

  /// Existing right cell if not scheduled for removal, otherwise null
  Cell? get rightChecked => rawRight ??= _checkCell(_CellCreationContext.right);

  /// Existing top cell if not scheduled for removal, otherwise null
  Cell? get topChecked => rawTop ??= _checkCell(_CellCreationContext.top);

  /// Existing bottom cell if not scheduled for removal, otherwise null
  Cell? get bottomChecked =>
      rawBottom ??= _checkCell(_CellCreationContext.bottom);

  /// Existing or new left cell
  Cell get left => rawLeft ??= _createCell(_CellCreationContext.left);

  /// Existing or new right cell
  Cell get right => rawRight ??= _createCell(_CellCreationContext.right);

  /// Existing or new top cell
  Cell get top => rawTop ??= _createCell(_CellCreationContext.top);

  /// Existing or new bottom cell
  Cell get bottom => rawBottom ??= _createCell(_CellCreationContext.bottom);

  /// Most important cell's parameter, controls cell's lifecycle and lifecycle
  /// of components inside the cell.
  /// See [CellState] for detailed description of states meaning.
  /// See [updateComponentsState] to understand a part of internal mechanics.
  CellState get state => _state;

  @internal
  CellState tmpState = CellState.active;

  set state(CellState value) {
    final oldValue = _state;
    if (oldValue == value) {
      return;
    }
    if (value == CellState.suspended) {
      beingSuspendedTimeMicroseconds = 0;
    }

    _state = value;
    if (isCellBuildFinished) {
      updateComponentsState();
    } else {
      if (!spatialGrid.cellsScheduledToBuild.contains(this)) {
        spatialGrid.cellsScheduledToBuild.add(this);
      }
    }
  }

  @internal
  void updateComponentsState() {
    switch (_state) {
      case CellState.active:
        _activateComponents();
        break;
      case CellState.inactive:
        _deactivateComponents();
        break;
      case CellState.suspended:
        _suspendComponents();
        break;
    }
  }

  void _activateComponents() {
    for (final component in components) {
      for (final hitbox in component.children) {
        if (hitbox is! ShapeHitbox) {
          continue;
        }
        if (component.toggleCollisionOnSuspendChange) {
          hitbox.collisionType = hitbox.defaultCollisionType;
        }
      }
    }
  }

  void _deactivateComponents() {
    for (final component in components) {
      for (final hitbox in component.children) {
        if (hitbox is! ShapeHitbox) {
          continue;
        }
        if (component.toggleCollisionOnSuspendChange) {
          hitbox.collisionType = hitbox.defaultCollisionType;
        }
      }
    }
  }

  void _suspendComponents() {
    for (final component in components) {
      for (final hitbox in component.children) {
        if (hitbox is! ShapeHitbox) {
          continue;
        }
        if (component.toggleCollisionOnSuspendChange) {
          hitbox.collisionType = CollisionType.inactive;
        }
      }
    }
  }

  /// The cell should to remove itself from all neighbours and [spatialGrid],
  /// remove all cell's components from game tree and dispose [state]'s
  /// listeners.
  void remove() {
    if (_remove) {
      return;
    }
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

    final game = spatialGrid.game;
    final cellLayers = game.layersManager.layers[this];
    if (cellLayers != null) {
      for (final layer in cellLayers.values) {
        layer.removeFromParent();
      }
    }
    game.layersManager.layers.remove(this);

    final broadphase = game.collisionDetection.broadphase;
    broadphase.optimizedCollisionsByGroupBox.remove(this)?.clear();
    broadphase.activeCollisionsByCell.remove(this)?.clear();
    broadphase.passiveCollisionsByCell.remove(this)?.clear();

    for (final component in components) {
      component.removeFromParent();
    }
    components.clear();
    _cachedRects.clear();
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

  /// Get cell's left, right, top and bottom neighbours, if exists.
  /// Also includes left-top, right-top, right-bottom and left-bottom
  /// neighbours.
  /// Useful for collision detection system.
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
