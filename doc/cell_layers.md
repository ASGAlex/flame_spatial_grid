# Optimizing static objects rendering and collisions using CellLayers

## Overview

The Framework offers your a way to improve the speed of rendering static objects. Every game Cell
could have a special `CellLayer` component whose purpose is batching components rendering, compiling
component's sprites into single `Image`, and updating the image in case some component did change.
Of course, such approach is only effective for rarely modifiable objects.

Every `CellLayer` class is a component, so you can easily create and add it into the game manually.
But it is recommended to use game's `LayersManager` instance, embedded
into `HasSpatialGridFramework` mixin. This allows you to forget about resource management because
CellLayer's lifecycle will be controlled by the Framework.

## Optimizing SpriteComponent's rendering

To add a `SpriteComponent` to a layer, the component must meet one general condition: it must
have `HasGridSupport` mixin!

Suppose, you have `HasSpatialGridFramework` instance in the `game` variable. Then, instead of
calling `add` method, use game's `layersManager` as follows:

```dart
game.layersManager.addComponent
(
component: anSpriteComponent,
layerType: MapLayerType.static, // Layer's type 
layerName: "Layer's unique name",
priority: 2, // Layer's priority
);
```

That's all! All components, added to the layer, will be rendered as `Image`, and the `Image` will
be updated only when layer's components parameters being changed.

## Optimizing SpriteAnimationComponent's rendering

Animated components also could be optimized in the same way as SpriteComponents. But you should
notice that this works only for components with the same animations. Components with different
animations should be added to different layers.

```dart
game.layersManager.addComponent
(
component: anSpriteAnimationComponent,
layerType: MapLayerType.animated, // Layer's type 
layerName: "Layer's unique name",
priority: 2, // Layer's priority
);
```

As you can see, everything is the same, only `layerType` was changed.

## Collisions optimizing

Every layer offers a way of collision optimization. It's enabled by default. To disable this, you
should use the `optimizeCollisions` parameter.

The optimization logic is simple: all objects in the layer are checked for being overlapped. If so,
a new `GroupHitbox` is created for a set of overlapped components, and this special kind of hitbox
is involved in the collision detection broad phase. And only if a component collides
with `GroupHitbox` - the second pass of the broad phase is started to find out concrete components
in the grouped set.

Items count in one group is limited to 25 items. For now, this value is hardcoded. This limitation
allows to avoid iterating hundreds of grouped items in a moment of collision and prevents heavy
performance drops.

If you enable debug mode either in `initializeSpatialGrid` or using the `isSpatialGridDebugEnabled`
setter, you will see blue lines in place of group hitboxes.

This approach allows the collision detection system to operate with spaces smaller than a Cell's
space. This is an attempt to obtain the QuadTree approach's advantages without its drawbacks

## Collision approximation

In a game, you might have a situation where some of the game objects do not need to have very
accurate information about collisions. For example, imagine that your NPC might be in two modes:
random walking and chasing. In the second mode, it needs to know exact collision information because
it tries to chase and hit a player and needs to avoid any small obstacles. Whereas in the first
mode, the NPC does not try to achieve any goal, it just shows you a random pointless movement. So,
there is no problem if some of the map areas become unreachable for the NPC due to inaccurate
collision calculation.

In the Framework collision approximation works for layers with optimized collisions. Normally, if an
object is colliding with `GroupHitbox`, the second pass of the broad phase is performed to find out,
what objects from `GroupHitbox` are colliding with the component. But you can skip this phase if
collision approximation is enabled. So, onCollision callbacks will not report you about a collision
with a game component, but with a CellLayer instead. So you also should modify your component's
collision handling to support approximated mode.

Let's look to a code example:

```dart
class Npc extends SpriteComponent with HasGridSupport {
  Npc() {
    /// This will enable collision approximation for
    /// listed CellLayer names
    boundingBox.groupCollisionsTags..add('Brick')..add('Water');
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints,
      PositionComponent other,) {
    if (other is CellLayer) {
      /// Collision approximation is enabled and we just have to collide with an
      /// GroupHitbox of "other" CellLayer
    } else {
      /// Normal collisions with components
    }
  }
}

/// Somewhere in cell builder function: 
Future<void> onBuildWater(CellBuilderContext context) async {
  final waterAnimation =
      getPreloadedTileData('tileset', 'Water')?.spriteAnimation;
  final water = Water(
    position: context.position,
    animation: waterAnimation,
    context: context,
  );
  water.currentCell = context.cell;
  game.layersManager.addComponent(
    component: water,
    layerType: MapLayerType.animated,

    /// The layer's name is important because it should match with tags we added to NPC's hitbox
    layerName: 'Water',
  );
}
```

So, you can add or remove tags in the `groupCollisionsTags` list at any time. This will allow you to
do 25 fewer checks on every collision with `GroupHitbox` 