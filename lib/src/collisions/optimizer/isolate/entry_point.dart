import 'dart:collection';

import 'package:flame_spatial_grid/src/collisions/optimizer/extensions.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/bounding_hitbox_dehydrated.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/optimized_collision_list_dehydrated.dart';
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
