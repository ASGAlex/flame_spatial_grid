# Overview

This library is a framework and set of tools for working with infinitive game fields, loading
infinite maps for one game level, creating an infinite count of game objects and active game players
and NPCs - as much as possible.

The framework is fully compatible with Flame and does not contain any strict requirements for the
game
structure. Even existing games could be migrated to this framework if necessary.

## Features

There are a lot of utility functions and the list of its features is too long to describe at a fast
glance.
So here is a list of only top-level features:

- __Building endless game levels__ without the need to change the screen for rendering another map.
  System
  gives you the ability to create big open worlds with seamless loading of new maps while a player
  approaches to them.
- __Build game levels with a destructible environment.__ Every Tiled tile could be converted into
  separate game component and handle interactions with other game elements individually
- __Building procedural-generated__ pieces of a map (or whole maps) on the fly, as the player
  approaches
  to them.
- __Wise resource management__: the system does not eat resources greedily, it takes care of proper
  allocation and de-allocation so you can enjoy your game even in a browser or weak mobile phone.
- __New visual effects__: lean resource management system allows to create trails for many players
  and persists during a long game session, blending with other game elements like ground.

Some of possible features might still be undiscovered :-)

## Core concepts

The core of the framework is a spatial grid that is building on-the-fly and controls component's
visibility and activity, loads and unloads maps by chunks. It allows optimizing rendering by
pre-rendering statical components into images, but keeps images size small enough and unloads unused
chunks from memory.

## Usage: minimal setup

1. Add `HasSpatialGridFramework` mixin into you game
2. Add `HasGridSupport` mixin to every your game component
3. Call `initializeSpatialGrid` at your game's `onLoad` function before adding any component into
   game.
4. Call `gameInitializationDone` when all components are added and the game should start.
5. Enjoy!

See detailed "minimal start" tutorial at [Getting Started](doc/getting_started.md) section.

See [game.dart](examples/lib/game.dart) for working code example
Check out our working demo at https://asgalex.github.io/flame_spatial_grid/

## Future usage instructions

0. [Getting Started Guide](doc/getting_started.md), if you still did not read it
1. [Working with Tiled maps](doc/tiled_maps_basics.md)
2. [Working with Tiled worlds](doc/tiled_maps_worlds.md)
3. [TODO] Optimizing static objects rendering and collisions using CellLayers
4. [TODO] Creating trails and other temporary marks on the ground.

## Advanced section

1. [TODO] How custom collision detection system works
2. [TODO] How CellLayers optimizes collision detection.
3. [TODO] Spatial grid and camera movement: problems, possible solutions
