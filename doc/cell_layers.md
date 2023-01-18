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