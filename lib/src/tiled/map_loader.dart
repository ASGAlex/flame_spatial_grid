import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';
import 'package:flame_tiled/flame_tiled.dart';

import 'tile_builder.dart';

abstract class TiledMapLoader {
  String get fileName;

  Vector2 get destTileSize;

  Vector2 get initialPosition;

  Map<String, TileBuilderFunction>? get tileBuilders;

  TileBuilderFunction? get defaultBuilder;

  TileBuilderFunction? get notFoundBuilder;

  int get basePriority => 0;

  TiledComponent? _tiledComponent;

  late HasClusterizedCollisionDetection game;

  Component get rootComponent => game.rootComponent;

  var mapRect = Rect.zero;

  Future<void> init(HasClusterizedCollisionDetection game) async {
    this.game = game;

    await _load();
    final renderableTiledMap = _tiledComponent?.tileMap;
    if (renderableTiledMap == null) return;
    final widthInTiles = _tiledComponent?.tileMap.map.width;
    final heightInTiles = _tiledComponent?.tileMap.map.height;
    if (widthInTiles != null && heightInTiles != null) {
      mapRect = Rect.fromLTWH(initialPosition.x, initialPosition.y,
          widthInTiles * destTileSize.x, heightInTiles * destTileSize.y);
    }

    await TileBuilder.processTileType(
        tileMap: renderableTiledMap,
        processorByType: tileBuilders,
        initialPosition: initialPosition,
        clusterizer: game.clusterizer,
        defaultBuilder: defaultBuilder,
        notFoundBuilder: notFoundBuilder);
  }

  Future<TiledComponent> _load() async => _tiledComponent =
      await TiledComponent.load(fileName, destTileSize, priority: basePriority);
}
