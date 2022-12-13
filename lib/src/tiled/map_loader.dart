import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:meta/meta.dart';

typedef TileBuilderFunction = Future<void> Function(
    TileDataProvider tile, Vector2 position, Vector2 size, Cell cell);

abstract class TiledMapLoader {
  static List<TiledMapLoader> loadedMaps = [];

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

  final _contextByCell = HashMap<Cell, List<CellBuilderContext>>();

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

    _processTileType(tileMap: renderableTiledMap);
  }

  Future<TiledComponent> _load() async => _tiledComponent =
      await TiledComponent.load(fileName, destTileSize, priority: basePriority);

  @mustCallSuper
  Future<void> cellBuilder(Cell cell, Component rootComponent) async {
    final contextList = _contextByCell.remove(cell);
    if (contextList == null) return;

    for (final context in contextList) {
      final tileType = context.tileBuilder.tile.type;
      final processor = tileBuilders?[tileType];
      if (processor != null) {
        await processor(
            context.tileBuilder, context.position, context.size, cell);
      } else {
        await notFoundBuilder?.call(
            context.tileBuilder, context.position, context.size, cell);
      }

      await defaultBuilder?.call(
          context.tileBuilder, context.position, context.size, cell);
    }
    contextList.clear();
  }

  void _processTileType(
      {required RenderableTiledMap tileMap,
      List<String>? layersToLoad,
      bool clear = true}) {
    List<TileLayer>? tileLayers = <TileLayer>[];
    if (layersToLoad != null) {
      for (final layer in layersToLoad) {
        final tileLayer = tileMap.getLayer<TileLayer>(layer);
        if (tileLayer != null) {
          tileLayers.add(tileLayer);
        }
      }
    } else {
      tileLayers =
          tileMap.map.layers.whereType<TileLayer>().toList(growable: false);
    }

    for (final tileLayer in tileLayers) {
      final tileData = tileLayer.data;
      if (tileData == null) {
        continue;
      }
      int xOffset = 0;
      int yOffset = 0;
      for (var tileId in tileData) {
        if (tileId != 0) {
          final tileset = tileMap.map.tilesetByTileGId(tileId);

          final firstGid = tileset.firstGid;
          if (firstGid != null) {
            tileId = tileId - firstGid; //+ 1;
          }
          final tileData = tileset.tiles[tileId];
          final position = Vector2(xOffset.toDouble() * tileMap.map.tileWidth,
                  yOffset.toDouble() * tileMap.map.tileWidth) +
              initialPosition;

          final size = Vector2(tileMap.map.tileWidth.toDouble(),
              tileMap.map.tileWidth.toDouble());
          final tileProcessor = TileDataProvider(tileData, tileset);

          final context = CellBuilderContext(tileProcessor, position, size);
          final cell =
              game.clusterizer.createNewCellAtPosition(position + size / 2);
          var list = <CellBuilderContext>[];
          list = _contextByCell[cell] ??= list;
          list.add(context);
        }
        xOffset++;
        if (xOffset == tileLayer.width) {
          xOffset = 0;
          yOffset++;
        }
      }
    }

    if (clear) {
      for (final layer in tileLayers) {
        tileMap.map.layers.remove(layer);
      }
      for (var rl in tileMap.renderableLayers) {
        rl.refreshCache();
      }
    }
  }
}
