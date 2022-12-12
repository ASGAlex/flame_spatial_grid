import 'dart:collection';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/extensions.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';

class CellStaticLayer extends PositionComponent
    with
        ClusterizedComponent,
        UpdateOnDemand,
        ListenerChildrenUpdate,
        HasGameReference<HasClusterizedCollisionDetection> {
  CellStaticLayer(Cell cell)
      : super(
            position: cell.rect.topLeft.toVector2(),
            size: cell.rect.size.toVector2()) {
    currentCell = cell;
    _collisionOptimizer = CollisionOptimizer(this);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    layerPicture = recorder.endRecording();
  }

  bool _needRepaint = true;

  late Picture layerPicture;
  Image? layerImage;

  bool renderAsImage = true;
  bool optimizeCollisions = false;
  late final CollisionOptimizer _collisionOptimizer;

  @override
  void renderTree(Canvas canvas) {
    isVisible = (currentCell?.state == CellState.active ? true : false);
    if (isVisible) {
      decorator.applyChain(render, canvas);
    }
  }

  @override
  void render(Canvas canvas) {
    if (_needRepaint) {
      _renderToPicture();
      _needRepaint = false;
    }
    if (renderAsImage && layerImage != null) {
      canvas.drawImage(layerImage!, Offset.zero, Paint());
    } else {
      canvas.drawPicture(layerPicture);
    }
  }

  void _renderToPicture() async {
    final cell = currentCell;
    if (cell == null) return;

    var recorder = PictureRecorder();
    var canvas = Canvas(recorder);
    for (var component in children) {
      component.renderTree(canvas);
    }
    layerPicture = recorder.endRecording();
    if (renderAsImage) {
      layerImage = await layerPicture.toImageSafe(
          cell.rect.width.toInt(), cell.rect.height.toInt());
    }
  }

  @override
  void onChildrenUpdate() {
    _needRepaint = true;
  }

  @override
  void updateTree(double dt) {
    if (isUpdateNeeded) {
      super.updateTree(dt);
      if (optimizeCollisions) {
        _collisionOptimizer.optimize();
        isUpdateNeeded = true;
      }
      super.updateTree(dt);
    }
  }

  @override
  void update(double dt) {
    onChildrenUpdate();
  }
}

mixin ListenerChildrenUpdate on PositionComponent {
  final _listenerChildrenUpdate = <Component, VoidCallback>{};

  void onChildrenUpdate();

  @override
  Future<void>? add(Component component) {
    if (component is ClusterizedComponent) {
      if (component is RepaintOnDemand) {
        component.repaintNotifier.addListener(onChildrenUpdate);
      } else {
        component.transform.addListener(onChildrenUpdate);
      }
      _listenerChildrenUpdate[component] = onChildrenUpdate;
    }
    onBeforeChildrenChanged(component, ChildrenChangeType.added);
    return super.add(component);
  }

  @override
  void remove(Component component) {
    final callback = _listenerChildrenUpdate.remove(component);
    if (callback != null) {
      if (component is RepaintOnDemand) {
        component.repaintNotifier.removeListener(callback);
      } else {
        (component as PositionComponent).transform.removeListener(callback);
      }
    }

    onBeforeChildrenChanged(component, ChildrenChangeType.removed);

    super.remove(component);
  }

  void onBeforeChildrenChanged(Component child, ChildrenChangeType type) {
    if (child is UpdateOnDemand) {
      child.isUpdateNeeded = true;
    }
    if (this is UpdateOnDemand) {
      (this as UpdateOnDemand).isUpdateNeeded = true;
    }
  }
}

class CollisionOptimizer {
  CollisionOptimizer(this.parentLayer);

  final ClusterizedComponent parentLayer;
  final _createdCollisionLists = <OptimizedCollisionList>[];

  List<ClusterizedComponent> get clusterizedChildren => parentLayer.children
      .whereType<ClusterizedComponent>()
      .toList(growable: false);

  List<ClusterizedComponent> get clusterizedChildrenActiveOrPassive =>
      parentLayer.children
          .whereType<ClusterizedComponent>()
          .where((element) =>
              element.boundingBox.collisionType != CollisionType.inactive)
          .toList(growable: false);

  final _alreadyProcessed = HashSet<ShapeHitbox>();

  HasClusterizedCollisionDetection get game =>
      (parentLayer as HasGameReference<HasClusterizedCollisionDetection>).game;

  void optimize() {
    final cell = parentLayer.currentCell;
    if (cell == null) return;

    final optimizedCollisionsByGroupBox =
        game.collisionDetection.broadphase.optimizedCollisionsByGroupBox;
    var collisionsListByGroup = optimizedCollisionsByGroupBox[cell];

    if (collisionsListByGroup == null) {
      optimizedCollisionsByGroupBox[cell] = collisionsListByGroup = {};
    }
    for (final optimized in _createdCollisionLists) {
      optimized.boundingBox.removeFromParent();
      collisionsListByGroup.remove(optimized.boundingBox);
    }
    _createdCollisionLists.clear();
    _alreadyProcessed.clear();

    for (final child in clusterizedChildren) {
      if (cell.state != CellState.inactive) {
        child.boundingBox.collisionType =
            child.boundingBox.defaultCollisionType;
      }
    }

    for (final child in clusterizedChildrenActiveOrPassive) {
      if (_alreadyProcessed.contains(child.boundingBox)) continue;
      final hitboxes = _findOverlappingRects(child.boundingBox);
      if (hitboxes.isNotEmpty) {
        hitboxes.add(child.boundingBox);

        final optimized = OptimizedCollisionList(hitboxes, parentLayer);
        collisionsListByGroup[optimized.boundingBox] = optimized;
        _createdCollisionLists.add(optimized);
        for (final hb in hitboxes) {
          hb.collisionType = CollisionType.inactive;
        }
      }
    }
  }

  HashSet<ShapeHitbox> _findOverlappingRects(ShapeHitbox hitbox,
      [HashSet<ShapeHitbox>? exception]) {
    exception ??= HashSet<ShapeHitbox>();
    final hitboxes = HashSet<ShapeHitbox>();
    exception.add(hitbox);
    for (final otherChild in clusterizedChildrenActiveOrPassive) {
      if (exception.contains(otherChild.boundingBox)) continue;
      if (hitbox.toRect().overlapsSpecial(otherChild.boundingBox.toRect())) {
        hitboxes.add(otherChild.boundingBox);
        _alreadyProcessed.add(otherChild.boundingBox);
        hitboxes
            .addAll(_findOverlappingRects(otherChild.boundingBox, exception));
      }
    }
    return hitboxes;
  }
}

extension RectSpecialOverlap on Rect {
  /// Whether `other` has a nonzero area of overlap with this rectangle.
  bool overlapsSpecial(Rect other) {
    if (right < other.left || other.right < left) {
      return false;
    }
    if (bottom < other.top || other.bottom < top) {
      return false;
    }
    return true;
  }
}
