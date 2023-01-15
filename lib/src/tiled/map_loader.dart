import 'dart:async';
import 'dart:collection';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:meta/meta.dart';

typedef TileBuilderFunction = Future<void> Function(CellBuilderContext context);

enum MapLayerType { static, animated, trail }

abstract class TiledMapLoader {
  static List<TiledMapLoader> loadedMaps = [];

  String fileName = '';

  Vector2 get destTileSize;

  Vector2 initialPosition = Vector2.zero();

  bool lazyLoad = true;

  Map<String, TileBuilderFunction>? get tileBuilders;

  TileBuilderFunction? get cellPostBuilder;

  TileBuilderFunction? get notFoundBuilder => genericTileBuilder;

  int get basePriority => 0;

  late final HasSpatialGridFramework game;

  Component get rootComponent => game.rootComponent;

  bool preloadTileSets = false;
  Rect mapRect = Rect.zero;

  final _contextByCellRect = HashMap<Rect, HashSet<CellBuilderContext>>();

  Future<TiledComponent> init(HasSpatialGridFramework game) async {
    this.game = game;

    final tiledComponent = await TiledComponent.load(
      fileName,
      destTileSize,
      priority: basePriority,
    );
    final renderableTiledMap = tiledComponent.tileMap;
    final widthInTiles = tiledComponent.tileMap.map.width;
    final heightInTiles = tiledComponent.tileMap.map.height;
    mapRect = Rect.fromLTWH(
      initialPosition.x,
      initialPosition.y,
      widthInTiles * destTileSize.x,
      heightInTiles * destTileSize.y,
    );
    if (preloadTileSets) {
      await _preloadTileSets(renderableTiledMap.map);
    }

    _processTileType(tileMap: renderableTiledMap);

    return tiledComponent;
  }

  static final _preloadedTileSet =
      HashMap<String, HashMap<String, TileCache>>();

  Future<void> _preloadTileSets(TiledMap map) async {
    for (final tileSet in map.tilesets) {
      final tilesetName = tileSet.name;
      if (tilesetName == null) {
        continue;
      }
      final tilesetCache =
          _preloadedTileSet[tilesetName] ?? HashMap<String, TileCache>();
      for (final tile in tileSet.tiles) {
        final tileTypeName = tile.type;
        if (tileTypeName == null) {
          continue;
        }
        tilesetCache[tileTypeName] = TileCache(
          sprite: await tile.getSprite(tileSet),
          spriteAnimation: await tile.getSpriteAnimation(tileSet),
        );
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
    if (contextList == null || contextList.isEmpty) {
      return;
    }

    for (final context in contextList) {
      if (context.remove) {
        contextsToRemove.add(context);
      } else {
        final builderType =
            context.tileDataProvider?.tile.type ?? context.tiledObject?.type;
        final processor = tileBuilders?[builderType];
        if (processor != null) {
          await processor(context);
        } else {
          await notFoundBuilder?.call(context);
        }
      }

      await cellPostBuilder?.call(context);
    }

    contextsToRemove.forEach(contextList.remove);
  }

  Future<void> genericTileBuilder(CellBuilderContext context) async {
    final provider = context.tileDataProvider;
    if (provider == null) {
      return;
    }
    final component = await TileComponent.fromProvider(provider);
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
      game.layersManager.addComponent(
        component: component,
        layerName: 'static-${context.layerInfo.name}',
        layerType: MapLayerType.static,
        isRenewable: false,
        priority: priority,
      );
    } else if (component.animation != null) {
      game.layersManager.addComponent(
        component: component,
        layerName: 'animated-${context.layerInfo.name}',
        layerType: MapLayerType.animated,
        isRenewable: false,
        priority: priority,
      );
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
      if (map.mapRect == Rect.zero) {
        continue;
      }
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

  List<Layer> _getLayers(
    RenderableTiledMap tileMap,
    List<String>? layersToLoad,
  ) {
    var layers = <Layer>[];
    if (layersToLoad != null) {
      for (final layer in layersToLoad) {
        final tileLayer = tileMap.getLayer<Layer>(layer);
        if (tileLayer != null) {
          layers.add(tileLayer);
        }
      }
    } else {
      layers = tileMap.map.layers.toList(growable: false);
    }

    return layers;
  }

  void _processTileType<T extends Layer>({
    required RenderableTiledMap tileMap,
    List<String>? layersToLoad,
    bool clear = true,
  }) {
    final layers = _getLayers(tileMap, layersToLoad);

    var layerPriority = 0;
    for (final layer in layers) {
      if (layer is TileLayer) {
        final tileData = layer.data;
        if (tileData == null) {
          continue;
        }
        final layerInfo = LayerInfo(layer.name, layerPriority);
        var xOffset = 0;
        var yOffset = 0;
        for (var tileId in tileData) {
          if (tileId != 0) {
            final tileset = tileMap.map.tilesetByTileGId(tileId);

            final firstGid = tileset.firstGid;
            if (firstGid != null) {
              tileId = tileId - firstGid;
            }
            final tileData = tileset.tiles[tileId];
            final position = Vector2(
                  xOffset.toDouble() * tileMap.map.tileWidth,
                  yOffset.toDouble() * tileMap.map.tileWidth,
                ) +
                initialPosition;

            final size = Vector2(
              tileMap.map.tileWidth.toDouble(),
              tileMap.map.tileWidth.toDouble(),
            );
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
              tileDataProvider: tileProcessor,
              position: position,
              size: size,
              cellRect: rect,
              spatialGrid: game.spatialGrid,
              layerInfo: layerInfo,
            );
            var list = HashSet<CellBuilderContext>();
            list = _contextByCellRect[rect] ??= list;
            list.add(context);
          }
          xOffset++;
          if (xOffset == layer.width) {
            xOffset = 0;
            yOffset++;
          }
        }
        layerPriority++;
      } else if (layer is ObjectGroup) {
        final layerInfo = LayerInfo(layer.name, layerPriority);
        for (final object in layer.objects) {
          final position = Vector2(object.x, object.y) + initialPosition;
          final size = Vector2(object.width, object.height);
          Rect rect;
          if (lazyLoad) {
            rect = game.spatialGrid.getCellRectAtPosition(position);
          } else {
            final cell =
                game.spatialGrid.createNewCellAtPosition(position + size / 2);
            rect = cell.rect;
          }

          final context = CellBuilderContext(
            tiledObject: object,
            position: position,
            size: size,
            cellRect: rect,
            spatialGrid: game.spatialGrid,
            layerInfo: layerInfo,
          );
          var list = HashSet<CellBuilderContext>();
          list = _contextByCellRect[rect] ??= list;
          list.add(context);
        }
      }
    }

    if (clear) {
      layers.forEach(tileMap.map.layers.remove);
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
