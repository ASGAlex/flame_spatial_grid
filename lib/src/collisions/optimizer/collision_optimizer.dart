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
    required this.target,
  });

  final List<BoundingHitboxHydrated> hitboxes;
  final BoundingHitboxHydrated target;
}

class OverlappedSearchResponse {
  OverlappedSearchResponse(this.index, this.hydratedRect);

  final int index;
  final Float64List hydratedRect;

  Rect get rect => Rect.fromLTRB(
        hydratedRect[0],
        hydratedRect[1],
        hydratedRect[2],
        hydratedRect[3],
      );
}

class BoundingHitboxHydrated {
  BoundingHitboxHydrated(BoundingHitbox hitbox, this.index) {
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
Iterable<OverlappedSearchResponse> findOverlappingRectsIsolated(
  OverlappingSearchRequest parameters,
) =>
    _findOverlappingRects(parameters.target, parameters.hitboxes);

Iterable<OverlappedSearchResponse> _findOverlappingRects(
  BoundingHitboxHydrated target,
  List<BoundingHitboxHydrated> hitboxesForOptimization, [
  Set<int>? excludedIndices,
]) {
  final hitboxes = <OverlappedSearchResponse>[];
  hitboxes.add(OverlappedSearchResponse(target.index, target.hydratedRect));
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

  static IsolateManager<Iterable<OverlappedSearchResponse>,
      OverlappingSearchRequest>? _isolateManager;

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

  Set<HasGridSupport> _componentsForOptimisation = {};

  @internal
  static final rectCache = <PositionComponent, Rect>{};

  Future optimizeIsolated() async {
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
    final toCheck = <BoundingHitboxHydrated>[];
    for (final child in componentsForOptimization) {
      if (cell.state != CellState.inactive) {
        child.boundingBox.collisionType =
            child.boundingBox.defaultCollisionType;
        child.boundingBox.group = null;
      }
      toCheck.add(BoundingHitboxHydrated(child.boundingBox, i));
      i++;
    }

    final skip = <int>{};
    for (var i = 0; i < toCheck.length; i++) {
      if (skip.contains(i)) {
        continue;
      }
      final target = toCheck[i];
      if (target.skip) {
        continue;
      }
      final params = OverlappingSearchRequest(
        hitboxes: toCheck,
        target: target,
      );
      final hitboxesUnsortedIndices = await _isolateManager!.compute(params);
      final hitboxesUnsorted = <BoundingHitbox>[];
      for (final responseItem in hitboxesUnsortedIndices) {
        try {
          final hitbox =
              componentsForOptimization[responseItem.index].boundingBox;
          CollisionOptimizer.rectCache[hitbox] = responseItem.rect;
          skip.add(responseItem.index);
          hitboxesUnsorted.add(hitbox);
        } on RangeError catch (_) {
          skip.add(responseItem.index);
        }
      }
      if (hitboxesUnsorted.length > 1) {
        if (hitboxesUnsorted.length > maximumItemsInGroup) {
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
          var chunk = <ShapeHitbox>[];
          for (final hbInChunk in hitboxesSorted) {
            if (totalInChunk == maximumItemsInGroup) {
              final optimized = OptimizedCollisionList(
                <ShapeHitbox>{}..addAll(chunk),
                parentLayer,
              );
              collisionsListByGroup[optimized.boundingBox] = optimized;
              _createdCollisionLists.add(optimized);
              totalInChunk = 0;
              chunk = <ShapeHitbox>[];
            } else {
              chunk.add(hbInChunk);
              totalInChunk++;
            }
          }
          if (chunk.isNotEmpty) {
            final optimized = OptimizedCollisionList(
              HashSet<ShapeHitbox>()..addAll(chunk),
              parentLayer,
            );
            collisionsListByGroup[optimized.boundingBox] = optimized;
            _createdCollisionLists.add(optimized);
          }
        } else {
          final optimized = OptimizedCollisionList(
            hitboxesUnsorted,
            parentLayer,
          );
          collisionsListByGroup[optimized.boundingBox] = optimized;
          _createdCollisionLists.add(optimized);
        }
        for (final hb in hitboxesUnsorted) {
          hb.collisionType = CollisionType.inactive;
        }
        if (hitboxesUnsorted.length >= toCheck.length) {
          break;
        }
      }
    }
  }

  Future optimize() async {
    await optimizeIsolated();
    return;

    final cell = clear();
    if (cell == null) {
      return;
    }

    final optimizedCollisionsByGroupBox =
        game.collisionDetection.broadphase.optimizedCollisionsByGroupBox;
    final collisionsListByGroup = optimizedCollisionsByGroupBox[cell]!;

    _componentsForOptimisation =
        parentLayer.children.query<HasGridSupport>().toSet();
    final temporaryList = _componentsForOptimisation.toList(growable: false);
    for (final child in temporaryList) {
      if (cell.state != CellState.inactive) {
        child.boundingBox.collisionType =
            child.boundingBox.defaultCollisionType;
        child.boundingBox.group = null;
      }
      if (child.boundingBox.collisionType == CollisionType.inactive) {
        _componentsForOptimisation.remove(child);
      }
    }
    final totalLength = _componentsForOptimisation.length;
    var child = _componentsForOptimisation.firstOrNull;

    while (child != null) {
      final hitboxesUnsorted = _findOverlappingRects(child.boundingBox);
      if (hitboxesUnsorted.length > 1) {
        if (hitboxesUnsorted.length > maximumItemsInGroup) {
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
          var chunk = <ShapeHitbox>[];
          for (final hbInChunk in hitboxesSorted) {
            if (totalInChunk == maximumItemsInGroup) {
              final optimized = OptimizedCollisionList(
                <ShapeHitbox>{}..addAll(chunk),
                parentLayer,
              );
              collisionsListByGroup[optimized.boundingBox] = optimized;
              _createdCollisionLists.add(optimized);
              totalInChunk = 0;
              chunk = <ShapeHitbox>[];
            } else {
              chunk.add(hbInChunk);
              totalInChunk++;
            }
          }
          if (chunk.isNotEmpty) {
            final optimized = OptimizedCollisionList(
              HashSet<ShapeHitbox>()..addAll(chunk),
              parentLayer,
            );
            collisionsListByGroup[optimized.boundingBox] = optimized;
            _createdCollisionLists.add(optimized);
          }
        } else {
          final optimized = OptimizedCollisionList(
            hitboxesUnsorted,
            parentLayer,
          );
          collisionsListByGroup[optimized.boundingBox] = optimized;
          _createdCollisionLists.add(optimized);
        }
        for (final hb in hitboxesUnsorted) {
          hb.collisionType = CollisionType.inactive;
        }
        if (hitboxesUnsorted.length >= totalLength) {
          break;
        }
      }
      child = _componentsForOptimisation.firstOrNull;
    }

    _componentsForOptimisation.clear();
    rectCache.clear();
  }

  Iterable<BoundingHitbox> _findOverlappingRects(
    BoundingHitbox hitbox, [
    int index = 0,
    List<int>? removalsIndicesOutput,
  ]) {
    final hitboxes = <BoundingHitbox>[];
    hitboxes.add(hitbox);
    _componentsForOptimisation.remove(hitbox.parentWithGridSupport);
    var initialRemovalsCount = 0;
    if (removalsIndicesOutput != null) {
      initialRemovalsCount = removalsIndicesOutput.length;
      removalsIndicesOutput.add(index);
    } else {
      removalsIndicesOutput = <int>[];
    }
    for (var i = 0; i < _componentsForOptimisation.length;) {
      HasGridSupport otherChild;
      if (i == 0) {
        otherChild = _componentsForOptimisation.first;
      } else {
        otherChild = _componentsForOptimisation.elementAt(i);
      }
      if (hitbox
          .toRectSpecial()
          .overlapsSpecial(otherChild.boundingBox.toRectSpecial())) {
        hitboxes.add(otherChild.boundingBox);
        hitboxes.addAll(
          _findOverlappingRects(
            otherChild.boundingBox,
            i,
            removalsIndicesOutput,
          ),
        );
        if (removalsIndicesOutput.isNotEmpty &&
            initialRemovalsCount < removalsIndicesOutput.length) {
          for (final removedIndex in removalsIndicesOutput) {
            if (removedIndex <= i) {
              i--;
              if (i < 0) {
                i = 0;
              }
            }
          }
        } else {
          i++;
        }
      } else {
        i++;
      }
    }
    return hitboxes;
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
    _componentsForOptimisation.clear();
    _createdCollisionLists.clear();
    return cell;
  }
}
