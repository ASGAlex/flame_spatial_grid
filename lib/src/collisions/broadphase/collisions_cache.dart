part of '../broadphase.dart';

class CollisionsCache {
  @protected
  final activeCollisions = <ShapeHitbox>{};

  @internal
  final allCollisionsByCell = <Cell, HashSet<ShapeHitbox>>{};

  @internal
  final passiveCollisionsByCell = <Cell, Map<Type, HashSet<ShapeHitbox>>>{};

  @internal
  final activeCollisionsByCell = <Cell, Map<Type, HashSet<ShapeHitbox>>>{};

  final _passiveByCellUnmodifiable = <Cell, Map<Type, List<ShapeHitbox>?>>{};
  final _activeByCellUnmodifiable = <Cell, Map<Type, List<ShapeHitbox>?>>{};

  void activeUnmodifiableCacheClear() => _activeByCellUnmodifiable.clear();

  void passiveUnmodifiableCacheClear() => _passiveByCellUnmodifiable.clear();

  bool _activeCollisionsChanged = false;
  bool _passiveCollisionsChanged = false;

  bool get activeCollisionsChanged => _activeCollisionsChanged;

  bool get passiveCollisionsChanged => _passiveCollisionsChanged;

  void preUpdate() {
    _activeCollisionsChanged = false;
    _passiveCollisionsChanged = false;
  }

  void processOperation(ScheduledHitboxOperation operation) {
    if (operation.add) {
      final cell = operation.cell;
      if (operation.all) {
        var list = allCollisionsByCell[cell];
        list ??= allCollisionsByCell[cell] = HashSet<ShapeHitbox>();
        list.add(operation.hitbox);
      } else {
        if (operation.active) {
          activeCollisions.add(operation.hitbox);
          _addOperation(operation, activeCollisionsByCell);
          _activeCollisionsChanged = true;
        } else {
          _addOperation(operation, passiveCollisionsByCell);
          _passiveCollisionsChanged = true;
        }
      }
    } else {
      final cell = operation.cell;
      if (operation.all) {
        final cellCollisions = allCollisionsByCell[cell];
        if (cellCollisions != null) {
          cellCollisions.remove(operation.hitbox);
          if (cellCollisions.isEmpty) {
            allCollisionsByCell.remove(cell);
          }
        }
      } else {
        if (operation.active) {
          activeCollisions.remove(operation.hitbox);
          operation.hitbox.broadphaseActiveIndex = -1;
          _removeOperation(operation, activeCollisionsByCell);
          _activeCollisionsChanged = true;
        } else {
          _removeOperation(operation, passiveCollisionsByCell);
          _passiveCollisionsChanged = true;
        }
      }
    }
  }

  void _addOperation(
    ScheduledHitboxOperation operation,
    Map<Cell, Map<Type, HashSet<ShapeHitbox>>> storage,
  ) {
    var typeStorage = storage[operation.cell];
    typeStorage ??= storage[operation.cell] = <Type, HashSet<ShapeHitbox>>{};
    var type = operation.hitbox.runtimeType;
    final component = operation.hitbox.hitboxParent;
    if (component is CellLayer) {
      type = component.primaryHitboxCollisionType ?? type;
    }
    var list = storage[operation.cell]![type];
    list ??= typeStorage[type] = HashSet<ShapeHitbox>();

    list.add(operation.hitbox);
  }

  void _removeOperation(
    ScheduledHitboxOperation operation,
    Map<Cell, Map<Type, HashSet<ShapeHitbox>>> storage,
  ) {
    final cellCollisions = storage[operation.cell];
    if (cellCollisions != null) {
      final list = cellCollisions[operation.hitbox.runtimeType];
      if (list != null) {
        list.remove(operation.hitbox);
        if (list.isEmpty) {
          cellCollisions.remove(operation.hitbox.runtimeType);
          if (cellCollisions.isEmpty) {
            storage.remove(operation.cell);
          }
        }
      }
    }
  }

  List<ShapeHitbox> unmodifiableCacheStore(
    Cell cell,
    Type type,
    Iterable<ShapeHitbox> data, {
    required bool isActive,
  }) {
    final storage =
        isActive ? _activeByCellUnmodifiable : _passiveByCellUnmodifiable;
    var list = storage[cell]?[type];
    if (list == null) {
      list = data.toList(growable: false);
      if (storage[cell] == null) {
        storage[cell] = <Type, List<ShapeHitbox>?>{};
      }
      if (storage[cell]![type] == null) {
        storage[cell]![type] = list;
      }
    }
    return list;
  }

  void clear() {
    activeCollisions.clear();
    allCollisionsByCell.clear();
    passiveCollisionsByCell.clear();
    activeCollisionsByCell.clear();
  }
}
