import 'dart:typed_data';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/entry_point.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/extensions.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/flat_buffers/flat_buffers_optimizer.dart'
    as fb;
import 'package:flame_spatial_grid/src/collisions/optimizer/optimized_collisions_list.dart';
import 'package:isolate_manager/isolate_manager.dart';
import 'package:meta/meta.dart';

class CollisionOptimizer {
  CollisionOptimizer(this.parentLayer) {
    _isolateManager ??= IsolateManager.create(
      findOverlappingRectsIsolated,
      concurrent: 4,
      workerName: 'spatial_grid_optimizer_worker',
    );
  }

  static IsolateManager<Uint8List, Uint8List>? _isolateManager;

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
    final toCheck = List<fb.BoundingHitboxObjectBuilder>.filled(
      componentsForOptimization.length,
      defaultBoundingHitboxObjectBuilder,
    );

    for (var i = 0; i < toCheck.length; i++) {
      final child = componentsForOptimization[i];
      if (cell.state != CellState.inactive) {
        child.boundingBox.collisionType =
            child.boundingBox.defaultCollisionType;
        child.boundingBox.group = null;
      }
      toCheck[i] = child.boundingBox.toBuilder(i);
    }

    final params = fb.OverlappingSearchRequestObjectBuilder(
      hitboxes: toCheck,
      maximumItemsInGroup: maximumItemsInGroup,
    );
    final buffer = params.toBytes();

    final responseData = await _isolateManager!.compute(
      buffer,
    );
    final response = fb.OverlappedSearchResponse(responseData);
    for (final collisionsList in response.optimizedCollisions!) {
      final hydratedHitboxes = List<BoundingHitbox>.filled(
        collisionsList.indicies!.length,
        _emptyBoundingHitbox,
      );
      for (var i = 0; i < hydratedHitboxes.length; i++) {
        try {
          final index = collisionsList.indicies![i];
          final component = componentsForOptimization[index];
          component.boundingBox.collisionType = CollisionType.inactive;
          hydratedHitboxes[i] = component.boundingBox;
        } on RangeError catch (_) {}
      }
      final rect = Rect.fromLTRB(
        collisionsList.optimizedBoundingRect!.left,
        collisionsList.optimizedBoundingRect!.top,
        collisionsList.optimizedBoundingRect!.right,
        collisionsList.optimizedBoundingRect!.bottom,
      );
      final optimized = OptimizedCollisionList(
        hydratedHitboxes,
        parentLayer,
        rect,
      );
      _createdCollisionLists.add(optimized);
      collisionsListByGroup[optimized.boundingBox] = optimized;
    }
  }

  Future buildMacroObjects() {
    throw UnimplementedError();
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

final _emptyBoundingHitbox = BoundingHitbox();
