// ignore_for_file: use_if_null_to_convert_nulls_to_bools, comment_references

import 'dart:collection';

import 'package:flame/camera.dart';
import 'package:flame/collisions.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

enum Direction {
  left,
  top,
  right,
  bottom;

  Direction opposite() {
    switch (this) {
      case Direction.left:
        return Direction.right;
      case Direction.right:
        return Direction.left;
      case Direction.top:
        return Direction.bottom;
      case Direction.bottom:
        return Direction.top;
    }
  }
}

/// The state controls cell's lifecycle and how many resources it consumes
enum CellState {
  /// Active cells - cells you usually see at the screen. Everything works
  /// here as in ordinary Flame game.
  active(2),

  /// This cells are usually out of the screen, so no components are displayed,
  /// [Component.renderTree] is completely omitted for components inside such
  /// cells. See [HasGridSupport] for details.
  inactive(1),

  /// This kind of cells are very far from player. Usually, player did there
  /// at past but then left these cells. Fot such cells [Component.updateTree]
  /// is omitted to preserve CPU resources. See [HasGridSupport] for details.
  suspended(0);

  const CellState(this.weight);

  final int weight;

  bool operator >(CellState other) => weight > other.weight;

  bool operator >=(CellState other) {
    if (other == this) {
      return true;
    }
    return weight > other.weight;
  }

  bool operator <=(CellState other) {
    if (other == this) {
      return true;
    }
    return weight < other.weight;
  }

  bool operator <(CellState other) => weight < other.weight;
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

    rawLeft = _checkCell(Direction.left);
    rawRight = _checkCell(Direction.right);
    rawTop = _checkCell(Direction.top);
    rawBottom = _checkCell(Direction.bottom);

    if (suspended) {
      state = CellState.suspended;
    } else {
      state = spatialGrid.getCellState(this);
    }
  }

  /// Locks cell in specified state, preventing unloading when not used.
  /// Feature is disabled, when null.
  CellState? lockInState;

  bool _isCellBuildFinished = false;

  bool get isCellBuildFinished => _isCellBuildFinished;

  set isCellBuildFinished(bool value) {
    _isCellBuildFinished = value;
    final layers = spatialGrid.game!.layersManager.layers[this];
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
  int outOfBoundsCounter = 0;

  bool get hasOutOfBoundsComponents => outOfBoundsCounter > 0;

  /// Cell's central point.
  late final Vector2 center;

  var _state = CellState.suspended;

  TileBuilderContextProvider? tileBuilderContextProvider;
  bool fullyInsideMap = false;

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

  final _cachedRects = <Direction, Rect>{};

  /// Existing left cell if not scheduled for removal, otherwise null
  Cell? get leftChecked => rawLeft ??= _checkCell(Direction.left);

  /// Existing right cell if not scheduled for removal, otherwise null
  Cell? get rightChecked => rawRight ??= _checkCell(Direction.right);

  /// Existing top cell if not scheduled for removal, otherwise null
  Cell? get topChecked => rawTop ??= _checkCell(Direction.top);

  /// Existing bottom cell if not scheduled for removal, otherwise null
  Cell? get bottomChecked => rawBottom ??= _checkCell(Direction.bottom);

  /// Existing or new left cell
  Cell get left => rawLeft ??= _createCell(Direction.left);

  /// Existing or new right cell
  Cell get right => rawRight ??= _createCell(Direction.right);

  /// Existing or new top cell
  Cell get top => rawTop ??= _createCell(Direction.top);

  /// Existing or new bottom cell
  Cell get bottom => rawBottom ??= _createCell(Direction.bottom);

  /// Most important cell's parameter, controls cell's lifecycle and lifecycle
  /// of components inside the cell.
  /// See [CellState] for detailed description of states meaning.
  /// See [updateComponentsState] to understand a part of internal mechanics.
  CellState get state => _state;

  @internal
  CellState tmpState = CellState.active;

  set state(CellState value) {
    if (lockInState != null) {
      if (lockInState! > value) {
        return;
      }
    }
    final oldValue = _state;
    if (oldValue == value) {
      return;
    }
    beingSuspendedTimeMicroseconds = 0;

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
        _setCollisionType();
        break;
      case CellState.inactive:
        _setCollisionType();
        break;
      case CellState.suspended:
        _setCollisionType(CollisionType.inactive);
        break;
    }
  }

  void _setCollisionType([CollisionType? collisionType]) {
    final broadphase = spatialGrid.game?.collisionDetection.broadphase;
    if (broadphase == null) {
      return;
    }
    final hitboxes = broadphase.allCollisionsByCell[this];
    if (hitboxes == null) {
      return;
    }
    for (final hitbox in hitboxes) {
      setCollisionTypeForHitbox(hitbox, collisionType);
    }
  }

  @internal
  static void setCollisionTypeForHitbox(
    ShapeHitbox hitbox, [
    CollisionType? collisionType,
  ]) {
    if (hitbox is BoundingHitbox && hitbox.optimized) {
      return;
    }
    if (hitbox.parentWithGridSupport?.toggleCollisionOnSuspendChange == true) {
      final newType = collisionType ?? hitbox.defaultCollisionType;
      hitbox.collisionType = newType;
    }
  }

  /// The cell should to remove itself from all neighbours and [spatialGrid],
  /// remove all cell's components from game tree and dispose [state]'s
  /// listeners.
  void remove() {
    if (_remove) {
      return;
    }

    final trackedComponent = spatialGrid.trackedComponent;
    if (trackedComponent is SpatialGridCameraWrapper) {
      final follow = trackedComponent.cameraComponent.viewfinder.children
          .query<FollowBehavior>();
      try {
        final target = follow.first.target;
        if (target is HasGridSupport && target.currentCell == this) {
          return;
        }
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
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

    final game = spatialGrid.game!;
    final cellLayers = game.layersManager.layers[this];
    if (cellLayers != null) {
      for (final layer in cellLayers.values) {
        layer.removeFromParent();
      }
    }
    game.layersManager.layers.remove(this);

    for (final component in components) {
      component.removeFromParent();
    }
    components.clear();

    final broadphase = game.collisionDetection.broadphase;
    broadphase.optimizedCollisionsByGroupBox.remove(this)?.clear();
    broadphase.activeCollisionsByCell.remove(this)?.clear();
    broadphase.passiveCollisionsByCell.remove(this)?.clear();
    _cachedRects.clear();
  }

  Cell _createCell(Direction direction) =>
      _checkCell(direction) ??
      Cell(spatialGrid: spatialGrid, rect: _createRectForDirection(direction));

  Cell? _checkCell(Direction direction) {
    final cell = spatialGrid.cells[_createRectForDirection(direction)];
    if (cell?._remove == true) {
      spatialGrid.cells.remove(cell?.rect);
      return null;
    }
    return cell;
  }

  Rect _createRectForDirection(Direction creationContext) {
    var newRect = _cachedRects[creationContext];
    if (newRect == null) {
      final width = spatialGrid.cellSize.width;
      final height = spatialGrid.cellSize.height;
      switch (creationContext) {
        case Direction.left:
          newRect = Rect.fromLTWH(rect.left - width, rect.top, width, height);
          break;
        case Direction.top:
          newRect = Rect.fromLTWH(rect.left, rect.top - height, width, height);
          break;
        case Direction.right:
          newRect = Rect.fromLTWH(rect.right, rect.top, width, height);
          break;
        case Direction.bottom:
          newRect = Rect.fromLTWH(rect.left, rect.bottom, width, height);
          break;
      }
      newRect = newRect.toRounded();
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

extension RoundPrecision on Rect {
  Rect toRounded([int precision = 1]) {
    var value = 1;
    for (var i = 0; i < precision; i++) {
      value = value * 10;
    }

    return Rect.fromLTRB(
      (left * value).round() / value,
      (top * value).round() / value,
      (right * value).round() / value,
      (bottom * value).round() / value,
    );
  }
}
