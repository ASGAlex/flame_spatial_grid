import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame/image_composition.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';

class CellStaticAnimationLayer extends PositionComponent
    with
        ClusterizedComponent,
        UpdateOnDemand,
        ListenerChildrenUpdate,
        HasGameReference<HasClusterizedCollisionDetection> {
  CellStaticAnimationLayer(Cell cell)
      : super(
            position: cell.rect.topLeft.toVector2(),
            size: cell.rect.size.toVector2()) {
    currentCell = cell;
    cell.components.add(this);
    _collisionOptimizer = CollisionOptimizer(this);
  }

  SpriteAnimationComponent? animationComponent;
  SpriteAnimation? animation;

  bool optimizeCollisions = false;
  late final CollisionOptimizer _collisionOptimizer;

  @override
  Future<void>? add(Component component) {
    if (component is SpriteAnimationComponent) {
      animation ??= component.animation;
    }
    return super.add(component);
  }

  @override
  void updateTree(double dt) {
    animationComponent?.update(dt);
    if (isUpdateNeeded) {
      super.updateTree(dt);
      if (optimizeCollisions) {
        _collisionOptimizer.optimize();
        isUpdateNeeded = true;
      }
      super.updateTree(dt);
      compileToSingleLayer();
    }
  }

  @override
  void renderTree(Canvas canvas) {
    isVisible = (currentCell?.state == CellState.active ? true : false);
    if (isVisible) {
      decorator.applyChain(render, canvas);
    }
  }

  @override
  void render(Canvas canvas) {
    animationComponent?.render(canvas);
  }

  Future<void> compileToSingleLayer() async {
    final anim = animation?.clone();
    if (anim == null) {
      throw "Can't compile while animation is not loaded!";
    }

    List<Sprite> newSprites = [];

    while (anim.currentIndex < anim.frames.length) {
      final sprite = anim.getSprite();
      final composition = ImageComposition();
      for (final component in children.whereType<SpriteAnimationComponent>()) {
        composition.add(sprite.image, component.position, source: sprite.src);
      }
      var composedImage = await composition.compose();
      newSprites.add(Sprite(composedImage));
      anim.currentIndex++;
    }
    final spriteAnimation = SpriteAnimation.variableSpriteList(newSprites,
        stepTimes: anim.getVariableStepTimes());
    animationComponent = SpriteAnimationComponent(
        animation: spriteAnimation,
        position: Vector2.all(0),
        size: newSprites.first.image.size);
  }

  @override
  void onChildrenUpdate() {
    isUpdateNeeded = true;
  }
}

extension _VariableStepTimes on SpriteAnimation {
  List<double> getVariableStepTimes() {
    final times = <double>[];
    for (final frame in frames) {
      times.add(frame.stepTime);
    }
    return times;
  }
}
