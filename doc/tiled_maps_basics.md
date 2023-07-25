# Working with Tiled maps

## Basics

In general the approach to working with Tiled maps is concluded that every map's tile should be
converted to a component - more complex or less.

Every tiled map should be described by special class, subclassed from `TiledMapLoader`. This class
will describe map's core parameters and tiles build logics. For every additional map you should to
implement additional loader class.

The minimal functional custom map loader would be looks as follows:

```dart
class ExampleMapLoader extends TiledMapLoader {
  @override
  String fileName = 'example.tmx';

  @override
  Vector2 get destTileSize => Vector2.all(16);

  @override
  Map<String, TileBuilderFunction>? get tileBuilders => null;
}
```

Also you should to list you map in `initializeSpatialGrid` function:

```dart
FutureOr<void> onLoad() async {
  await initializeSpatialGrid(
    cellSize: 50,
    activeRadius: const Size(2, 2),
    unloadRadius: const Size(2, 2),
    trackWindowSize: false,

    /// You can list multiple maps here, including multiple instances of the same map, but with
    /// different initial position
    maps: [
      ExampleMapLoader(),
    ],
  );

  return super.onLoad();
}
```

This will result in rendering your map just as a simple background image without any interactive
elements. So it is very close to core `RenderableTiledMap` functionality, but this class was
designed to offer your much more power.

Suppose we have any [objects](https://doc.mapeditor.org/en/stable/manual/objects/) in our tiled map.
We can to assign a 'personal' builder for object of any class using `tileBuilders` property:

```dart
class ExampleMapLoader extends TiledMapLoader {
  @override
  String fileName = 'example.tmx';

  @override
  Vector2 get destTileSize => Vector2.all(16);

  @override
  Map<String, TileBuilderFunction>? get tileBuilders =>
      {
        'TestObject': onBuildTestObject,
      };

  Future<void> onBuildTestObject(CellBuilderContext context) async {
    /// add game components related to object here
    /// access to object's data, using [context.tiledObject] property
  }

}
```

But this is not limited only to objects. You also can handle every tile processing, according to
the tile's class as well:

```dart
class ExampleMapLoader extends TiledMapLoader {
  @override
  Map<String, TileBuilderFunction>? get tileBuilders =>
      {
        'TestObject': onBuildTestObject,
        'AnyTileClass': onBuildAnyTile,
      };

  Future<void> onBuildAnyTile(CellBuilderContext context) async {
    /// add tile representation here
    /// access to object's data, using [context.tileDataProvider] property
  }
}
```

`CellBuilderContext` is a special class with all information about a tile or object. It offers you
easy access to the most wanted properties. If you need to read additional tile's or object's
parameters, you can access core classes `tileObject` - for objects processing -
and `tileDataProvider.tile` - for tiles processing.

The `tileDataProvider` provides such useful functions like `getSprite` for accessing tile's sprite,
and `getSpriteAnimation` to get tile's `SpriteAnimation`. For animations variable step times are

## Customizing map's background layer building

The `notFoundBuilder` is supposed to be used for processing all tile classes, not described
explicitly in `tileBuilders` property. It offers default functionality through `genericTileBuilder`
function of core `TiledMapLoader` class.

In general it should work fine for most of cases, but the one thing you might want to customize
there is `priority` of components. Especially for this case `context.priorityOverride` variable
exists. You should to change it before calling `genericTileBuilder`.

Let's see an example. Here individual priority is specified according to layer's name:

```dart
@override
TileBuilderFunction? get notFoundBuilder => onBackgroundBuilder;

Future<void> onBackgroundBuilder(CellBuilderContext context) async {
  var priority = -3;
  if (context.layerInfo.name == 'moss') {
    priority = -2;
  } else if (context.layerInfo.name == 'flowers') {
    priority = -1;
  }
  context.priorityOverride = priority;

  super.genericTileBuilder(context);
}
```

## Map's tiles lifecycle

Because the Framework could occasionally unload old cells with all components inside, map builders
functions could be called many times till a game process.

Every map tile's information normally is stored into `CellBuilderContext`. These context classes are
stored whole game and are reused in time when a piece of map should be rebuilt.

That means that you can safely save `CellBuilderContext` somewhere in your game and change some of
it's parameters to keep your environment changes between map's chunks reload. But keep in mind
that `position` of tile should be kept inside the `cellRect`. You can also use `remove` property to
indicate to the Framework that this tile or object should not be recreated in future map cell's
reload.

In general, this part of API still is not too user-friendly. TODO: will be fixed in future releases.

