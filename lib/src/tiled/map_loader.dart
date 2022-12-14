import 'dart:async';
import 'dart:collection';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
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

  bool preloadTileSets = false;
  var mapRect = Rect.zero;

  final _contextByCell = HashMap<Cell, List<CellBuilderContext>>();
  final _animationLayers = HashMap<Cell, CellStaticAnimationLayer>();
  final _staticLayers = HashMap<Cell, CellStaticLayer>();

  Future<void> init(HasClusterizedCollisionDetection game) async {
    this.game = game;

    _tiledComponent = await TiledComponent.load(fileName, destTileSize,
        priority: basePriority);
    final renderableTiledMap = _tiledComponent?.tileMap;
    if (renderableTiledMap == null) return;
    final widthInTiles = _tiledComponent?.tileMap.map.width;
    final heightInTiles = _tiledComponent?.tileMap.map.height;
    if (widthInTiles != null && heightInTiles != null) {
      mapRect = Rect.fromLTWH(initialPosition.x, initialPosition.y,
          widthInTiles * destTileSize.x, heightInTiles * destTileSize.y);
    }
    if (preloadTileSets) {
      await _preloadTileSets(renderableTiledMap.map);
    }

    _processTileType(tileMap: renderableTiledMap);
  }

  static final _preloadedTileSet =
      HashMap<String, HashMap<String, TileCache>>();

  Future<void> _preloadTileSets(TiledMap map) async {
    for (final tileSet in map.tilesets) {
      final tilesetName = tileSet.name;
      if (tilesetName == null) continue;
      final tilesetCache =
          _preloadedTileSet[tilesetName] ?? HashMap<String, TileCache>();
      for (final tile in tileSet.tiles) {
        final tileTypeName = tile.type;
        if (tileTypeName == null) continue;
        tilesetCache[tileTypeName] = TileCache(
            sprite: await tile.getSprite(tileSet),
            spriteAnimation: await tile.getSpriteAnimation(tileSet));
      }
      _preloadedTileSet[tilesetName] = tilesetCache;
    }
  }

  TileCache? getPreloadedTileData(String tileSetName, String tileType) =>
      _preloadedTileSet[tileSetName]?[tileType];

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

  void addToStaticLayer(ClusterizedComponent component,
      {int layerPriority = 1,
      bool optimizeCollisions = true,
      CellStaticLayer? layer}) {
    final cell = component.currentCell;
    if (cell == null) {
      throw 'Cell must be specified!';
    }
    final staticLayer = layer ?? (_staticLayers[cell] ?? CellStaticLayer(cell));
    _addToLayer(component,
        externalLayer: layer != null,
        layer: staticLayer,
        layerPriority: layerPriority,
        optimizeCollisions: optimizeCollisions);
  }

  void addToAnimatedLayer(ClusterizedComponent component,
      {int layerPriority = 1,
      bool optimizeCollisions = true,
      CellStaticAnimationLayer? layer}) {
    final cell = component.currentCell;
    if (cell == null) {
      throw 'Cell must be specified!';
    }
    if (component is! SpriteAnimationComponent) {
      throw 'Component ${component.runtimeType} must be SpriteAnimationComponent!';
    }
    final animationLayer =
        layer ?? (_animationLayers[cell] ?? CellStaticAnimationLayer(cell));
    _addToLayer(component,
        externalLayer: layer != null,
        layer: animationLayer,
        layerPriority: layerPriority,
        optimizeCollisions: optimizeCollisions);
  }

  void _addToLayer(ClusterizedComponent component,
      {int layerPriority = 1,
      bool optimizeCollisions = true,
      required bool externalLayer,
      required CellLayer layer}) {
    final cell = component.currentCell;
    if (cell == null) {
      throw 'Cell must be specified!';
    }
    layer.priority = layerPriority;
    layer.optimizeCollisions = optimizeCollisions;
    component.position = component.position - cell.rect.topLeft.toVector2();
    layer.add(component);
    if (externalLayer) {
      rootComponent.add(layer);
    } else {
      if (layer is CellStaticLayer) {
        if (_staticLayers[cell] == null) {
          _staticLayers[cell] = layer;
          rootComponent.add(layer);
        }
      } else if (layer is CellStaticAnimationLayer) {
        if (_animationLayers[cell] == null) {
          _animationLayers[cell] = layer;
          rootComponent.add(layer);
        }
      }
    }
  }

  bool isCellOutsideOfMap(Cell cell) {
    final checkList = [
      cell.rect.topLeft,
      cell.rect.bottomLeft,
      cell.rect.topRight,
      cell.rect.bottomRight
    ];
    var isCellOutsideOfMap = true;
    for (final map in TiledMapLoader.loadedMaps) {
      if (map.mapRect == Rect.zero) continue;
      for (final cellPoint in checkList) {
        if (map.mapRect.contains(cellPoint)) {
          isCellOutsideOfMap = false;
          break;
        }
      }
    }

    return isCellOutsideOfMap;
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
      for (final rl in tileMap.renderableLayers) {
        rl.refreshCache();
      }
    }
  }
}

@immutable
class TileCache {
  const TileCache({this.sprite, this.spriteAnimation});

  final Sprite? sprite;
  final SpriteAnimation? spriteAnimation;
}
