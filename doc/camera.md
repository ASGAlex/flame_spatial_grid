# Interacting with Flame's Cameras

Framework interactions with a camera might be a too complicated thing, but thanks to the new camera
API it is not.

If you use `CameraComponent`, you just need to wrap it into the `SpatialGridCameraWrapper` class and
pass this class into `initializeSpatialGrid` as the `trackedComponent` parameter. That's all! The
spatial grid framework will react to the camera's movement, and expand or shrink the active area on
zoom events automatically.

The second thing you should do is to call the `gameInitializationDone` function
after `initializeSpatialGrid` and after adding all necessary game components into the game's
components tree. This function initially calculates the active area according to window size and
default zoom level.

Here is example of setup:

```dart

@override
Future<void> onLoad() async {
  super.onLoad();

  cameraComponent = CameraComponent(world: world);
  cameraComponent.viewfinder.zoom = 5;
  cameraComponent.follow(player, maxSpeed: 40);

  await initializeSpatialGrid(

    /// other initialization parameters are omitted
    /// 
    /// Just wrap the cameraComponent into the SpatialGridCameraWrapper and pass to the parameter.
    /// There is no need to add either cameraComponent or wrapper into game explicitly. 
    trackedComponent: SpatialGridCameraWrapper(cameraComponent),
  );

  /// The rest of initialization here.
  /// 
  /// After everything is loaded and ready for the game, call this:
  gameInitializationDone();
}

```