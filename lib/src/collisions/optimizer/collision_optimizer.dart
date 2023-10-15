import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/extensions.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/optimized_collisions_list.dart';
import 'package:meta/meta.dart';

class CollisionOptimizer {
  CollisionOptimizer(this.parentLayer);

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

  void optimize() {
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
    Uint16List? removalsIndicesOutput,
  ]) {
    final hitboxes = <BoundingHitbox>[];
    hitboxes.add(hitbox);
    _componentsForOptimisation.remove(hitbox.parentWithGridSupport);
    var initialRemovalsCount = 0;
    if (removalsIndicesOutput != null) {
      initialRemovalsCount = removalsIndicesOutput.length;
      removalsIndicesOutput.add(index);
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
        hitboxes.addAll(_findOverlappingRects(
          otherChild.boundingBox,
          i,
          removalsIndicesOutput,
        ));
        if (removalsIndicesOutput != null &&
            initialRemovalsCount < removalsIndicesOutput.length) {
          for (final removedIndex in removalsIndicesOutput) {
            if (removedIndex <= i) {
              i--;
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
