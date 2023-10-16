import 'dart:collection';
import 'dart:typed_data';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/extensions.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/optimized_collisions_list.dart';
import 'package:isolate_manager/isolate_manager.dart';
import 'package:meta/meta.dart';

@immutable
class OverlappingSearchRequest {
  const OverlappingSearchRequest({
    required this.hitboxes,
    required this.maximumItemsInGroup,
  });

  final List<BoundingHitboxDehydrated> hitboxes;
  final int maximumItemsInGroup;
}

class OverlappedSearchResponse {
  OverlappedSearchResponse(this.optimizedCollisions);

  final List<OptimizedCollisionListDehydrated> optimizedCollisions;
}

class BoundingHitboxDehydrated {
  BoundingHitboxDehydrated(BoundingHitbox hitbox, this.index) {
    aabb = hitbox.aabb;
    positionStorage = hitbox.position.storage;

    parentPositionStorage =
        (hitbox.parent as PositionComponent?)?.position.storage;
    sizeStorage = hitbox.size.storage;
    skip = hitbox.collisionType == CollisionType.inactive;
  }

  late final Float64List sizeStorage;
  late final Float64List positionStorage;
  late final Float64List? parentPositionStorage;
  late final Aabb2 aabb;
  final int index;
  late final bool skip;

  Rect? _rectCache;
  late Float64List _hydratedRect;

  Float64List get hydratedRect {
    toRectSpecial();
    return _hydratedRect;
  }

  final Vector2 _aabbCenter = Vector2.zero();
  bool _aabbCenterNotSet = true;

  Vector2 get aabbCenter {
    if (_aabbCenterNotSet) {
      _aabbCenterNotSet = false;
      _aabbCenter.setFrom(aabb.center);
    }
    return _aabbCenter;
  }

  Rect toRectSpecial() {
    final cache = _rectCache;
    if (cache != null) {
      return cache;
    } else {
      if (parentPositionStorage == null) {
        return Rect.zero;
      } else {
        final parentPosition = Vector2.fromFloat64List(parentPositionStorage!);
        final position = Vector2.fromFloat64List(positionStorage);
        final size = Vector2.fromFloat64List(sizeStorage);
        final cache = Rect.fromLTWH(
          parentPosition.x + position.x,
          parentPosition.y + position.y,
          size.x,
          size.y,
        );

        _hydratedRect = Float64List.fromList([
          cache.left,
          cache.top,
          cache.right,
          cache.bottom,
        ]);

        _rectCache = cache;
        return cache;
      }
    }
  }
}

@pragma('vm:entry-point')
OverlappedSearchResponse findOverlappingRectsIsolated(
  OverlappingSearchRequest parameters,
) {
  final skip = <int>{};
  final optimizedCollisions = <OptimizedCollisionListDehydrated>[];
  for (var i = 0; i < parameters.hitboxes.length; i++) {
    if (skip.contains(i)) {
      continue;
    }
    final target = parameters.hitboxes[i];
    if (target.skip) {
      continue;
    }
    final hitboxesUnsorted = _findOverlappingRects(target, parameters.hitboxes);
    for (final element in hitboxesUnsorted) {
      skip.add(element.index);
    }

    if (hitboxesUnsorted.length > 1) {
      if (hitboxesUnsorted.length > parameters.maximumItemsInGroup) {
        final hitboxesSorted = hitboxesUnsorted.toList(growable: false);
        hitboxesSorted.sort((a, b) {
          if (a.aabbCenter == b.aabbCenter) {
            return 0;
          }
          if (a.aabbCenter.y < b.aabbCenter.y) {
            return -1;
          } else if (a.aabbCenter.y == b.aabbCenter.y) {
            return a.aabbCenter.x < b.aabbCenter.x ? -1 : 1;
          } else {
            return 1;
          }
        });
        var totalInChunk = 0;
        var chunk = <BoundingHitboxDehydrated>[];
        for (final hbInChunk in hitboxesSorted) {
          if (totalInChunk == parameters.maximumItemsInGroup) {
            final optimized = OptimizedCollisionListDehydrated(
              <BoundingHitboxDehydrated>{}..addAll(chunk),
            );
            optimizedCollisions.add(optimized);
            totalInChunk = 0;
            chunk = <BoundingHitboxDehydrated>[];
          } else {
            chunk.add(hbInChunk);
            totalInChunk++;
          }
        }
        if (chunk.isNotEmpty) {
          final optimized = OptimizedCollisionListDehydrated(
            HashSet<BoundingHitboxDehydrated>()..addAll(chunk),
          );
          optimizedCollisions.add(optimized);
        }
      } else {
        final optimized = OptimizedCollisionListDehydrated(
          hitboxesUnsorted,
        );
        optimizedCollisions.add(optimized);
      }
      if (hitboxesUnsorted.length >= parameters.hitboxes.length) {
        break;
      }
    }
  }

  return OverlappedSearchResponse(optimizedCollisions);
}

Iterable<BoundingHitboxDehydrated> _findOverlappingRects(
  BoundingHitboxDehydrated target,
  List<BoundingHitboxDehydrated> hitboxesForOptimization, [
  Set<int>? excludedIndices,
]) {
  final hitboxes = <BoundingHitboxDehydrated>[];
  hitboxes.add(target);
  if (excludedIndices != null) {
    excludedIndices.add(target.index);
  } else {
    excludedIndices = <int>{};
  }
  for (final otherHitbox in hitboxesForOptimization) {
    if (otherHitbox.skip ||
        otherHitbox.index == target.index ||
        excludedIndices.contains(otherHitbox.index)) {
      continue;
    }
    if (target.toRectSpecial().overlapsSpecial(otherHitbox.toRectSpecial())) {
      hitboxes.addAll(
        _findOverlappingRects(
          otherHitbox,
          hitboxesForOptimization,
          excludedIndices,
        ),
      );
    }
  }
  return hitboxes;
}

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
    var i = 0;
    final toCheck = <BoundingHitboxDehydrated>[];
    for (final child in componentsForOptimization) {
      if (cell.state != CellState.inactive) {
        child.boundingBox.collisionType =
            child.boundingBox.defaultCollisionType;
        child.boundingBox.group = null;
      }
      toCheck.add(BoundingHitboxDehydrated(child.boundingBox, i));
      i++;
    }

    final params = OverlappingSearchRequest(
      hitboxes: toCheck,
      maximumItemsInGroup: maximumItemsInGroup,
    );

    final response = await _isolateManager!.compute(params);
    for (final collisionsList in response.optimizedCollisions) {
      final hydratedHitboxes = <BoundingHitbox>[];
      for (final dehydrated in collisionsList.hitboxes) {
        try {
          final component = componentsForOptimization[dehydrated.index];
          component.boundingBox.collisionType = CollisionType.inactive;
          hydratedHitboxes.add(component.boundingBox);
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
