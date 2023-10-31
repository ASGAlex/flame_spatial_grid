import 'dart:typed_data';

import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/flat_buffers/flat_buffers_optimizer.dart'
    as fb;
import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/geometry_universal.dart';
import 'package:vector_math/vector_math_64.dart';

@pragma('vm:entry-point')
Uint8List findOverlappingRectsIsolated(
  Uint8List parameters,
) {
  final request = fb.OverlappingSearchRequest(parameters);
  final hitboxes = request.hitboxes!;
  final skip = <int>{};
  final optimizedCollisions = <fb.OptimizedCollisionsObjectBuilder>[];
  // final optimizedCollisions = <fb.OptimizedCollisionList>[];
  for (var i = 0; i < hitboxes.length; i++) {
    if (skip.contains(i)) {
      continue;
    }
    final target = hitboxes[i];
    if (target.skip) {
      continue;
    }
    final hitboxesUnsorted = _findOverlappingRects(target, hitboxes);
    for (final element in hitboxesUnsorted) {
      skip.add(element.index);
    }

    if (hitboxesUnsorted.length > 1) {
      if (hitboxesUnsorted.length > request.maximumItemsInGroup &&
          request.maximumItemsInGroup > 0) {
        final hitboxesSorted = hitboxesUnsorted.toList(growable: false);
        hitboxesSorted.sort((a, b) {
          if (a.aabbCenter == b.aabbCenter) {
            return 0;
          }
          if (a.aabbCenter!.y < b.aabbCenter!.y) {
            return -1;
          } else if (a.aabbCenter!.y == b.aabbCenter!.y) {
            return a.aabbCenter!.x < b.aabbCenter!.x ? -1 : 1;
          } else {
            return 1;
          }
        });
        var totalInChunk = 0;
        final chunk = List<int>.filled(request.maximumItemsInGroup, -1);

        for (var sortedIndex = 0;
            sortedIndex < hitboxesSorted.length;
            sortedIndex++) {
          if (totalInChunk == request.maximumItemsInGroup) {
            var boundingRect = Rect.zero;
            final indices = List<int>.filled(chunk.length, 0);
            for (var i = 0; i < chunk.length; i++) {
              final hitbox = hitboxesSorted[chunk[i]];
              indices[i] = hitbox.index;
              if (boundingRect == Rect.zero) {
                boundingRect = hitbox.toRectSpecial();
              } else {
                boundingRect =
                    boundingRect.expandToInclude(hitbox.toRectSpecial());
              }
            }
            final optimized = fb.OptimizedCollisionsObjectBuilder(
              indicies: indices,
              optimizedBoundingRect: boundingRect.toFlatBufferRect(),
            );
            optimizedCollisions.add(optimized);
            totalInChunk = 0;
            chunk.fillRange(0, request.maximumItemsInGroup, -1);
          } else {
            chunk[totalInChunk] = sortedIndex;
            totalInChunk++;
          }
        }
        if (totalInChunk != 0) {
          final indices = List<int>.filled(chunk.length, 0);
          var boundingRect = Rect.zero;
          for (var i = 0; i < chunk.length; i++) {
            final index = chunk[i];
            if (index == -1) {
              break;
            }
            final hitbox = hitboxesSorted[index];
            indices[i] = hitbox.index;
            if (boundingRect == Rect.zero) {
              boundingRect = hitbox.toRectSpecial();
            } else {
              boundingRect =
                  boundingRect.expandToInclude(hitbox.toRectSpecial());
            }
          }
          final optimized = fb.OptimizedCollisionsObjectBuilder(
            indicies: indices,
            optimizedBoundingRect: boundingRect.toFlatBufferRect(),
          );
          optimizedCollisions.add(optimized);
        }
      } else {
        final indices = List<int>.filled(hitboxesUnsorted.length, 0);
        var boundingRect = Rect.zero;
        for (var i = 0; i < hitboxesUnsorted.length; i++) {
          final hitbox = hitboxesUnsorted[i];
          indices[i] = hitbox.index;
          if (boundingRect == Rect.zero) {
            boundingRect = hitbox.toRectSpecial();
          } else {
            boundingRect = boundingRect.expandToInclude(hitbox.toRectSpecial());
          }
        }
        final optimized = fb.OptimizedCollisionsObjectBuilder(
          indicies: indices,
          optimizedBoundingRect: boundingRect.toFlatBufferRect(),
        );
        optimizedCollisions.add(optimized);
      }
      if (hitboxesUnsorted.length >= hitboxes.length) {
        break;
      }
    }
  }

  final responseBuilder = fb.OverlappedSearchResponseObjectBuilder(
      optimizedCollisions: optimizedCollisions);
  return responseBuilder.toBytes();
}

List<fb.BoundingHitbox> _findOverlappingRects(
  fb.BoundingHitbox target,
  List<fb.BoundingHitbox> hitboxesForOptimization, [
  Set<int>? excludedIndices,
]) {
  final hitboxes = <fb.BoundingHitbox>[];
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

extension ToFlatBuffersRect on Rect {
  fb.RectObjectBuilder toFlatBufferRect() => fb.RectObjectBuilder(
        left: left,
        right: right,
        top: top,
        bottom: bottom,
      );
}

extension ToRectSpecial on fb.BoundingHitbox {
  Rect toRectSpecial() {
    final cache = rectCache;
    if (cache != null) {
      _aabbCenterUpdate();
      return cache;
    } else {
      if (this.parentPosition == null) {
        return Rect.zero;
      }
      final parentPosition =
          Vector2(this.parentPosition!.x, this.parentPosition!.y);
      final position = Vector2(this.position!.x, this.position!.y);
      final size = Vector2(this.size!.x, this.size!.y);
      final cache = Rect.fromLTWH(
        parentPosition.x + position.x,
        parentPosition.y + position.y,
        size.x,
        size.y,
      );

      rectCache = cache;
      _aabbCenterUpdate();
      return cache;
    }
  }

  void _aabbCenterUpdate() {
    if (aabbCenter == null) {
      final aabb = Aabb2();
      aabb.min.setValues(this.aabb!.min.x, this.aabb!.min.y);
      aabb.max.setValues(this.aabb!.max.x, this.aabb!.max.y);
      aabbCenter = aabb.center;
    }
  }
}

extension RectSpecialOverlap on Rect {
  /// Whether `other` has a nonzero area of overlap with this rectangle.
  bool overlapsSpecial(Rect other) {
    if (topLeft == other.bottomRight ||
        topRight == other.bottomLeft ||
        bottomLeft == other.topRight ||
        bottomRight == other.topLeft) {
      return false;
    }
    if (right < other.left || other.right < left) {
      return false;
    }
    if (bottom < other.top || other.bottom < top) {
      return false;
    }
    return true;
  }
}
