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

  @internal
  final passiveByCellUnmodifiable = <Cell, Map<Type, List<ShapeHitbox>?>>{};

  @internal
  final activeByCellUnmodifiable = <Cell, Map<Type, List<ShapeHitbox>?>>{};

  void activeUnmodifiableCacheClear() {
    _activeCollisionsChanged.forEach(activeByCellUnmodifiable.remove);
  }

  void passiveUnmodifiableCacheClear() {
    _passiveCollisionsChanged.forEach(passiveByCellUnmodifiable.remove);
  }

  final _activeCollisionsChanged = <Cell>{};
  final _passiveCollisionsChanged = <Cell>{};

  bool get activeCollisionsChanged => _activeCollisionsChanged.isNotEmpty;

  bool get passiveCollisionsChanged => _passiveCollisionsChanged.isNotEmpty;

  void preUpdate() {
    _activeCollisionsChanged.clear();
    _passiveCollisionsChanged.clear();
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
          _activeCollisionsChanged.add(cell);
        } else {
          _addOperation(operation, passiveCollisionsByCell);
          _passiveCollisionsChanged.add(cell);
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
          _activeCollisionsChanged.add(cell);
        } else {
          _removeOperation(operation, passiveCollisionsByCell);
          _passiveCollisionsChanged.add(cell);
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
        isActive ? activeByCellUnmodifiable : passiveByCellUnmodifiable;
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
