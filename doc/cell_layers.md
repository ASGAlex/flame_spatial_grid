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
game.layersManager.addComponent(
  component: anSpriteComponent,
  layerType: MapLayerType.static, // Layer's type 
  layerName: "Layer's unique name",
  priority: 2, // Layer's priority
);
```

That's all! All components, added to the layer, will be rendered as `Image`, and the `Image` will 
be updated only when layer's components parameters being changed. 


## Optimizing SpriteAnimationComponent's rendering

