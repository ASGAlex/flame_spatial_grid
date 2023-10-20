import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/bounding_hitbox_dehydrated.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/entry_point.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/optimized_collisions_list.dart';
import 'package:isolate_manager/isolate_manager.dart';
import 'package:meta/meta.dart';

class CollisionOptimizer {
  CollisionOptimizer(this.parentLayer) {
    _isolateManager ??= IsolateManager.create(
      findOverlappingRectsIsolated,
      concurrent: 4,
    );
  }

  static IsolateManager<OverlappedSearchResponse, OverlappingSearchRequest>?
      _isolateManager;

  final CellLayer parentLayer;
  final _createdCollisionLists = <OptimizedCollisionList>[];

  bool get isEmpty => _createdCollisionLists.isEmpty;

  int? _maximumItemsInGroup;

  set maximumItemsInGroup(int? value) {
    _maximumItemsInGroup = value;
  }

  int get maximumItemsInGroup =>
      _maximumItemsInGroup ?? game.collisionOptimizerGroupLimit;

  HasSpatialGridFramework get game => parentLayer.game;

  @internal
  static final rectCache = <PositionComponent, Rect>{};

  Future optimize() async {
    final cell = clear();
    if (cell == null) {
      return;
    }

    final optimizedCollisionsByGroupBox =
        game.collisionDetection.broadphase.optimizedCollisionsByGroupBox;
    final collisionsListByGroup = optimizedCollisionsByGroupBox[cell]!;

    final componentsForOptimization =
        parentLayer.children.query<HasGridSupport>();
    final toCheck = List<BoundingHitboxDehydrated>.filled(
      componentsForOptimization.length,
      BoundingHitboxDehydrated.empty,
    );
    for (var i = 0; i < toCheck.length; i++) {
      final child = componentsForOptimization[i];
      if (cell.state != CellState.inactive) {
        child.boundingBox.collisionType =
            child.boundingBox.defaultCollisionType;
        child.boundingBox.group = null;
      }
      toCheck[i] = BoundingHitboxDehydrated(child.boundingBox, i);
    }

    final params = OverlappingSearchRequest(
      hitboxes: toCheck,
      maximumItemsInGroup: maximumItemsInGroup,
    );

    final response = await _isolateManager!.compute(params);
    for (final collisionsList in response.optimizedCollisions) {
      final hydratedHitboxes = List<BoundingHitbox>.filled(
        collisionsList.hitboxes.length,
        BoundingHitboxDehydrated.emptyBoundingHitbox,
      );
      for (var i = 0; i < hydratedHitboxes.length; i++) {
        try {
          final dehydrated = collisionsList.hitboxes[i];
          final component = componentsForOptimization[dehydrated.index];
          component.boundingBox.collisionType = CollisionType.inactive;
          hydratedHitboxes[i] = component.boundingBox;
        } on RangeError catch (_) {}
      }
      final optimized = OptimizedCollisionList(
        hydratedHitboxes,
        parentLayer,
        collisionsList.expandedBoundingRect,
      );
      _createdCollisionLists.add(optimized);
      collisionsListByGroup[optimized.boundingBox] = optimized;
    }
  }

  Cell? clear() {
    final cell = parentLayer.currentCell;
    if (cell == null) {
      return null;
    }

    final optimizedCollisionsByGroupBox =
        game.collisionDetection.broadphase.optimizedCollisionsByGroupBox;
    var collisionsListByGroup = optimizedCollisionsByGroupBox[cell];

    if (collisionsListByGroup == null) {
      optimizedCollisionsByGroupBox[cell] = collisionsListByGroup = {};
    }
    for (final optimized in _createdCollisionLists) {
      collisionsListByGroup.remove(optimized.boundingBox);
      optimized.clear();
    }
    _createdCollisionLists.clear();
    return cell;
  }
}
