# Overview

This library is a framework and set of tools for working with infinitive game fields, loading
infinite maps for one game level, creating infinite count of game objects and active game players
and NPCs - as much as possible.

Framework is fully compatible with Flame and does not contain any strict requirements for game
structure. Even existing games could be migrated to this framework if necessary.

## Features

There are a lot of utility function and list of its features is too long to describe at fast glance.
So here is a list of only top-level features:

- *Building endless game levels* without need to change screen for rendering another map. System
  gives you ability to create big open worlds with seamlessly loading of new maps while player
  approaches to them.
- *Build game levels with destructible environment.* Every Tiled tile could be converted into
  separate game component and handle interactions with other game elements individually
- *Building procedural-generated* pieces of map (or whole maps) on the fly, as player approaches to
  them.
- *Wise resource management*: system does not eat resources greedily, it takes care about proper
  allocation and de-allocation so you can enjoy you game even in browser or weak mobile phone.
- *New visual effects*: lean resource management system allows to create trails for many players
  and persists it during long game session, blending with other game elements like ground.

Some of possible features might still be undiscovered :-)

## Core concepts

The core of framework is spatial grid which is build on-the-fly and controls components visibility,
activity, loads and unloads maps by chunks. It allows to optimize rendering by pre-rendering
statical components into images, but keeps images size small enough and unloads unused chunks from
memory.

## Usage: minimal setup

1. Add `HasSpatialGridFramework` mixin into you game
2. Add `HasGridSupport` mixin to every your game component
3. Call `initializeSpatialGrid` at your game's `onLoad` function before adding any component into
   game.
4. Call `gameInitializationDone` when all components are added and the game should start.
5. Enjoy!

