import 'dart:async';
import 'dart:collection';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:meta/meta.dart';

typedef TileBuilderFunction = Future<void> Function(CellBuilderContext context);

abstract class TiledMapLoader {
  static List<TiledMapLoader> loadedMaps = [];

  String fileName = '';

  Vector2 get destTileSize;

  Vector2 initialPosition = Vector2.zero();

  bool lazyLoad = true;

  Map<String, TileBuilderFunction>? get tileBuilders;

  TileBuilderFunction? get defaultBuilder;

  TileBuilderFunction? get notFoundBuilder => genericTileBuilder;

  int get basePriority => 0;

  TiledComponent? _tiledComponent;

  late HasSpatialGridFramework game;

  Component get rootComponent => game.rootComponent;

  bool preloadTileSets = false;
  var mapRect = Rect.zero;

  final _contextByCellRect = HashMap<Rect, HashSet<CellBuilderContext>>();

  @internal
  final layers = HashMap<Cell, HashMap<String, CellLayer>>();

  Future<void> init(HasSpatialGridFramework game) async {
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
    final contextList = _contextByCellRect[cell.rect];
    final contextsToRemove = <CellBuilderContext>[];
    if (contextList == null || contextList.isEmpty) return;

    for (final context in contextList) {
      if (context.remove) {
        contextsToRemove.add(context);
      } else {
        final tileType = context.tileDataProvider.tile.type;
        final processor = tileBuilders?[tileType];
        if (processor != null) {
          await processor(context);
        } else {
          await notFoundBuilder?.call(context);
        }
      }

      await defaultBuilder?.call(context);
    }

    if (contextsToRemove.isNotEmpty) {
      for (final context in contextsToRemove) {
        contextList.remove(context);
      }
    }
  }

  Future<void> genericTileBuilder(CellBuilderContext context) async {
    final component =
        await TileComponent.fromProvider(context.tileDataProvider);
    component.currentCell = context.cell;
    component.position = context.position;
    component.size = context.size;
    var priority = -100;
    if (context.priorityOverride != null) {
      priority = context.priorityOverride!;
    } else {
      priority = context.layerInfo.priority;
    }
    if (component.sprite != null) {
      addToLayer(
          component: component,
          layerName: 'static-${context.layerInfo.name}',
          animated: false,
          priority: priority);
    } else if (component.animation != null) {
      addToLayer(
          component: component,
          layerName: 'animated-${context.layerInfo.name}',
          animated: true,
          priority: priority);
    }
  }

  void addToLayer({
    required HasGridSupport component,
    required bool animated,
    required String layerName,
    bool optimizeCollisions = true,
    int priority = 1,
  }) {
    final cell = component.currentCell;
    if (cell == null) {
      throw 'Cell must be specified!';
    }
    CellLayer? layer = layers[cell]?[layerName];
    final isNew = layer == null;
    if (animated) {
      if (component is! SpriteAnimationComponent) {
        throw 'Component ${component.runtimeType} must be SpriteAnimationComponent!';
      }
      if (isNew) {
        layer = CellStaticAnimationLayer(cell, layerName);
      }
    } else {
      if (component is! SpriteComponent) {
        throw 'Component ${component.runtimeType} must be SpriteComponent!';
      }
      if (isNew) {
        layer = CellStaticLayer(cell, layerName);
      }
    }

    component.position = component.position - cell.rect.topLeft.toVector2();
    layer.add(component);

    if (isNew) {
      layer.mapLoader = this;
      layer.priority = priority;
      layer.optimizeCollisions = optimizeCollisions;
      if (layers[cell] == null) {
        layers[cell] = HashMap<String, CellLayer>();
      }
      layers[cell]?[layerName] = layer;
      rootComponent.add(layer);
    }
  }

  CellLayer? getLayer({required String name, required Cell cell}) =>
      layers[cell]?[name];

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

  bool isCellInsideOfMap(Cell cell) => !isCellOutsideOfMap(cell);

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

    var layerPriority = 0;
    for (final tileLayer in tileLayers) {
      final tileData = tileLayer.data;
      if (tileData == null) {
        continue;
      }
      final layerInfo = LayerInfo(tileLayer.name, layerPriority);
      int xOffset = 0;
      int yOffset = 0;
      for (var tileId in tileData) {
        if (tileId != 0) {
          final tileset = tileMap.map.tilesetByTileGId(tileId);

          final firstGid = tileset.firstGid;
          if (firstGid != null) {
            tileId = tileId - firstGid;
          }
          final tileData = tileset.tiles[tileId];
          final position = Vector2(xOffset.toDouble() * tileMap.map.tileWidth,
                  yOffset.toDouble() * tileMap.map.tileWidth) +
              initialPosition;

          final size = Vector2(tileMap.map.tileWidth.toDouble(),
              tileMap.map.tileWidth.toDouble());
          final tileProcessor = TileDataProvider(tileData, tileset);

          Rect rect;
          if (lazyLoad) {
            rect = game.spatialGrid.getCellRectAtPosition(position);
          } else {
            final cell =
                game.spatialGrid.createNewCellAtPosition(position + size / 2);
            rect = cell.rect;
          }
          final context = CellBuilderContext(
              tileProcessor, position, size, rect, game.spatialGrid, layerInfo);
          var list = HashSet<CellBuilderContext>();
          list = _contextByCellRect[rect] ??= list;
          list.add(context);
        }
        xOffset++;
        if (xOffset == tileLayer.width) {
          xOffset = 0;
          yOffset++;
        }
      }
      layerPriority++;
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
