# Working with Tiled worlds

## Overview

Tiled *.world file format is an easy way to load multiple maps into a game. With Flame, you will
most probably need to unload a previous map and load a next. Additionally, flame_tiled does not
support *.world files at all.

With this Framework loading multiple maps into single game area become easy. All maps from the
"world" would be rendered as one big map, but the Framework's resource management system will
preserve system resources for you.

For now, every map from a "world" file would be processed. But I have the plan to make a map's
loading also depend on a player's position, so this feature will come in the future.

## Usage

Unlike with `TiledMapLoader` you need not to create new subclasses of the `WorldLoader` class. But
you still need to implement a class for every map of the "world", as described in section
[Working with Tiled maps](tiled_maps_basics.md)

After that, just add a new parameter into `initializeSpatialGrid` function:

```dart

@override
Future<void> onLoad() async {
  await initializeSpatialGrid(
    ///
    ///omitting other parameters
    ///
    worldLoader: WorldLoader(
      fileName: 'example.world',
      mapLoader: {'example': DemoMapLoader(), 'another_map': AnotherMapLoader()},
    ),
  );
}
```

That's all! 

You can safely combine `worldLoader` parameter with `maps` parameter. In fact, `WorldLoader` is just
automation of `maps` parameter functionality.
