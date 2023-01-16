# Getting started guide

This is a short instruction how to make everything work.
If you looking for some more complex, please check working example here:
[game.dart](/examples/lib/game.dart)

## Creating the game class

#### 0. Create a game class with `HasSpatialGridFramework` mixin.

```dart
class MinimalGame extends FlameGame with HasSpatialGridFramework {
  MinimalGame();
}
```

#### 1. Create `onLoad` function and call `await initializeSpatialGrid` inside:

```dart
  @override
FutureOr<void> onLoad() async {
  await initializeSpatialGrid(
    blockSize: 50,
    debug: true,
    activeRadius: const Size(2, 2),
    unloadRadius: const Size(2, 2),
    trackWindowSize: false,
  );

  return super.onLoad();
}
```

Run the code. You should see a window with green-red grid. A very minimal spatial grid setup for
demonstration purposes.

#### 2. Create a simple component to represent a player:

```dart
class Player extends PositionComponent with HasGridSupport, HasPaint {
  Player({super.position}) : super(size: Vector2(10, 10)) {
    paint.color = Colors.indigoAccent;
    _rect = Rect.fromLTWH(0, 0, size.x, size.y);
  }

  late final Rect _rect;

  @override
  void render(Canvas canvas) {
    canvas.drawRect(_rect, paint);
  }
}
```

It will be a simple indigo square 10x10 px size.
Let's add the component into our `onLoad`:

```dart
@override
FutureOr<void> onLoad() async {
  final player = Player(position: Vector2(160, 190));
  await initializeSpatialGrid(
    blockSize: 50,
    debug: true,
    activeRadius: const Size(2, 2),
    unloadRadius: const Size(2, 2),
    trackWindowSize: false,
    trackedComponent: player,
  );
  add(player);
  return super.onLoad();
}
```

Let's restart application. We should to see indigo square in the center of green grid.

#### 3. Adding movement

Add these variables and functions into player's class:

```dart

final speed = 80;
final vector = Vector2.zero();
double dtElapsed = 0;
final dtMax = 1000;

@override
void update(double dt) {
  dtElapsed++;
  if (dtElapsed >= dtMax || _outOfBounds()) {
    vector.setZero();
    dtElapsed = 0;
  }
  if (vector.isZero()) {
    _createNewVector();
  }

  final dtSpeed = speed * dt;
  final newStep = vector * dtSpeed;
  if (!vector.isZero()) {
    position.add(newStep);
  }
  super.update(dt);
}

void _createNewVector() {
  final rand = Random();
  var xSign = rand.nextBool() ? -1 : 1;
  var ySign = rand.nextBool() ? -1 : 1;
  if (position.x >= 900) {
    xSign = -1;
  } else if (position.x <= 0) {
    xSign = 1;
  }

  if (position.y >= 500) {
    ySign = -1;
  } else if (position.y <= 0) {
    ySign = 1;
  }
  final xValue = rand.nextDouble();
  final yValue = rand.nextDouble();
  vector.setValues(xValue * xSign, yValue * ySign);
}

bool _outOfBounds() =>
    position.x <= 0 ||
        position.y <= 0 ||
        position.x >= 900 ||
        position.y >= 500;
```

Run the application. You should see how the player's square moves and creates new cells on its
way. You will also see new "gray" cells - it means the cell is active, but components should not
be visible. And black cells - it means the cell is suspended and no `update` is performed for
possible components inside this cell

#### 4. Adding additional components

Let's check, how other components will interact with spatial grid. Add a small 'for' loop into
`onLoad` function:

```dart
for (var i = 0; i < 90; i++) {
add(Player(position: Vector2(i * 10.0, 20)));
}
```

Let's also add some visual difference between main component and other components. Update Player
constructor this way:

```dart
class Player extends PositionComponent with HasGridSupport, HasPaint {
  Player({super.position, bool? isPrimary}) : super(size: Vector2(10, 10)) {
    _isPrimary = isPrimary ?? false;
    paint.color = _isPrimary ? Colors.indigoAccent : Colors.brown;
    _rect = Rect.fromLTWH(0, 0, size.x, size.y);

    if (!_isPrimary) {
      debugMode = true;
    }
  }
}
```

Please notice that we enabled debug mode for non-primary components.
Let's run our application.
You should see how components become invisible in the grey zone but keep moving. That cells are
called
"inactive". Also, you should see how components freeze in black cells. Such cells are "suspended",
The `updateTree` function does not work in components from such cells. Finally, suspended components
start moving again when their cell state changed to "inactive" (grey) or "active" (green).

#### 5. Adding collision detections

Let's make components collide. It is similar to vanilla Flame except for one moment: we already have
a hitbox and can reuse to minimize computations.

1. Add `CollisionCallbacks` mixin into `Player` class.
2. Add `boundingBox.collisionType = boundingBox.defaultCollisionType = CollisionType.active;` at
   the end of `Player` constructor
3. Create `onCollision` function:

```dart
  @override
void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
  if (other is Player) {
    vector.setZero();
  }

  super.onCollision(intersectionPoints, other);
}
```

Now you should see, how components change their directions when colliding.
Take a look at `boundingBox.defaultCollisionType`. When a component is in a suspended cell, it's
`boundingBox.collisionType` become `CollisionType.inactive`. The `defaultCollisionType` is used at
a moment of re-activation of the suspended component, so `boundingBox.collisionType` become
`boundingBox.defaultCollisionType`.

#### 5. Stress test

Now we will test how custom collision system works with lot of objects.
Firstly, remove (or comment) these lines in `Player` constructor:

```dart
if (!_isPrimary) {
debugMode = true;
}
```

this is recommended because drawing debugging overlay is too expensive operation.
Then modify a loop of adding non-primary components:

```dart
for (var i = 0; i < 1000; i++) {
final y = (20 + (i / 90).floor() * 10).toDouble();
final x = (i * 10.0) - (i / 90).floor() * 900;
add(Player(position: Vector2(x, y)));
}
```

Finally, add FPS component to the game to look at some pretty (or not very pretty) benchmarks:

```dart
add(FpsTextComponent());
```

Let's start the example.
Most probably you will see something not very wonderful, about 25-30 FPS. The reason is - high
density of objects and a big count of simultaneous collisions happen.
But the good news is that it still works at least! You can increase objects count to 2000 or more
and example still will be functional.

#### 6. Resources economy

Imagine that this small game field represents player's movement through the large game world. Also
imagine that the world is so large that we can't store in memory every game object and need to
remove some very old components, which barely have a chance to interact with player.

The Framework offers you a solution.

Every cell while being suspended have a personal timer. When the timer reaches a limit value, the
cell is marked for removal (that also means removing all components on this cell too). By default
this functionality is disabled, but you can simply enable it, adding new parameters into
`initializeSpatialGrid` function:

```
suspendedCellLifetime: const Duration(seconds: 30),
removeCellsPerUpdate: 1,
```

You might want to change `suspendedCellLifetime` to seconds to see the effect faster: old cells are
removed with components inside them. This allows you to save resources on a large game field, but
restoration of removed components is up to you. Hopefully, the Framework has a tool to solve
this problem

#### 6. Cell builders

In the moment of cell creation you can fill it with game components: an NPCs, environment elements,
map tiles, etc. The most basic functionality is adding new components via `cellBuilderNoMap`
parameter of `initializeSpatialGrid` function.

Let's add the new function into our `MinimalGame` class:

```dart

Future<void> onBuildNewCell(Cell cell,
    Component rootComponent,) async {
  final random = Random();
  final doCreation = random.nextBool();
  if (doCreation) {
    add(Player(position: cell.center)
      ..currentCell = cell);
  }
}
```

Take a closer look into `Player`'s creation lines. There is one new thing: `..СurrentCell = cell`.
Usually, we should not control a component's cell manually. To be honest, here we also can safely
remove this line and everything will be functional. Functional, but not too performant. If the
Framework mounts a component without `currentCell`, it tries to find an existing cell or to create a
new one. This operation is not cheap, so it is a good approach to specify `currentCell` manually at
the component's creation time when you already have the
cell's instance.

Let's then add a new parameter into `initializeSpatialGrid`:

```
cellBuilderNoMap: onBuildNewCell,
```

All done! Now, you indigo square will never be alone!
This was a simplest cell builder in the system. `TiledMapLoader` and `WorldLoader` classes
provides much more powerful builders especially for working with tiles on a map.

## Final words

Of course this example is too synthetic and small. Why do we ever need to suspend just 10 components
is such small screen?
But let's scale this example. You might have thousands of components and many screens between them.
An at such situation all demonstrated optimizations become make sense!

If you are too tired to reproduce all tutorial step-by-step, you can find completed code
at [minimal_game.dart](/examples/lib/minimal_game.dart) 