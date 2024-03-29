import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:meta/meta.dart';

typedef TileBuilderFunction<T> = Future<void> Function(
  TileBuilderContext<T> context,
);

typedef LayerBuilderFunction<T> = Future<bool> Function(
  LayerInfo layerInfo,
  TileBuilderContext<T> context,
);

typedef InitialPositionChecker = Vector2? Function(
  ObjectGroup layer,
  TiledObject object,
  Vector2 mapOffset,
  String? worldName,
);

/// List of basic types of [CellLayer], supported natively by spatial grid
/// framework
enum MapLayerType {
  /// [CellStaticLayer] class instance
  static,

  /// [CellStaticAnimationLayer] class instance
  animated,

  /// [CellTrailLayer] class instance
  trail,

  /// Use [LayersManager.customLayerBuilder] to build layer class
  custom,
}

/// This is base class for describing a Tiled map. You going to create
/// new class for every map type (map file) you will use in your game.
/// Each class describes map's [fileName], it's [destTileSize], it's
/// [initialPosition] and various build functions to convert each tile into
/// corresponding game component.
///
/// [tileBuilders] allows to specify corresponding builder for each tile "Type"
/// ("Class"). If no builder had been found for type - the [notFoundBuilder]
/// function will be called. Bu default it runs [genericTileBuilder] - useful
/// to create map's backgrounds - but you always free to reimplement this.
abstract class TiledMapLoader<T extends HasSpatialGridFramework, C> {
  static List<TiledMapLoader> loadedMaps = [];

  /// File name in '/assets/tiles' directory, with extension
  String fileName = '';

  /// Your map's tile size
  Vector2 get destTileSize;

  /// This helps to position map on your game field
  Vector2 initialPosition = Vector2.zero();

  /// Controls map's loading behavior. If true - whole map will be loaded
  /// at once. If false - just part of map in active cells region will be
  /// converted into game components.
  bool lazyLoad = true;

  /// The first core feature of this class. Allows to specify a build function
  /// for every "Type" ("Class") of map's tile. The builder function will be
  /// called for every tile of corresponding "Class" at stage of map
  /// initialization and during new cells creation.
  Map<String, TileBuilderFunction<C>>? get tileBuilders;

  Map<String, LayerBuilderFunction<C>>? get layerBuilders;

  /// Finds and process objects at any map's point. Useful for initialisation
  /// process, for example to find player's initial position on a map.
  Map<String, TileBuilderFunction<C>>? get globalObjectBuilder;

  /// A function called after tile was successfully built. It is useful if you
  /// need some post-processing for every tile of you map.
  TileBuilderFunction<C>? get cellPostBuilder => null;

  /// The function is called when no corresponded type (class) was found in
  /// [tileBuilders] storage. By default it builds flat image of map, something
  /// like [RenderableTiledMap] do, but already split by cells of grid.
  TileBuilderFunction<C>? get notFoundBuilder => genericTileBuilder;

  /// This specifies the priority of [TiledComponent] you will receive after map
  /// initialization. Does not affect the Frameworks functionality, so might be
  /// safely forgotten.
  int get basePriority => 0;

  /// The link to the current game. Is necessary for accessing [SpatialGrid]
  /// class and working with layers.
  T get game => _game!;
  T? _game;

  TiledComponent? tiledComponent;

  Component get rootComponent => game.rootComponent;

  late final TileBuilderContextProvider<TiledMapLoader, C>
      tileBuilderContextProvider;

  /// By default flame_tiled loads just tilesets that are really used in the
  /// map. But with using tile builders it becomes to be useful to have secured
  /// access to all map's tilesets to reuse them in components creation.
  ///
  /// If you going to keep a system to load tilesets as they are needed,
  /// most probably you will face unexpected async exceptions, trying to access
  /// a sprite or animation, which still is not loaded. To avoid this, set the
  /// parameter to true.
  ///
  /// Setting this to true will force system to load all tilesets firstly and
  /// run builders then.
  /// This also allows [getPreloadedTileData] to work correctly
  bool preloadTileSets = true;

  /// Map dimensions, calculated during initialization
  Rect mapRect = Rect.zero;

  /// Use this function in tile builder to access tile's [Sprite]
  /// or [SpriteAnimation].
  TileCache? getPreloadedTileData(String tileSetName, String tileType) =>
      game.tilesetManager.getTile(tileSetName, tileType);

  Future<TiledComponent> loadTiledComponent() async {
    if (tiledComponent != null) {
      return tiledComponent!;
    } else {
      tiledComponent = await TiledComponent.load(
        fileName,
        destTileSize,
        priority: basePriority,
      );
      final widthInTiles = tiledComponent!.tileMap.map.width;
      final heightInTiles = tiledComponent!.tileMap.map.height;
      mapRect = Rect.fromLTWH(
        initialPosition.x,
        initialPosition.y,
        widthInTiles * destTileSize.x,
        heightInTiles * destTileSize.y,
      );

      return tiledComponent!;
    }
  }

  CellLayer customLayerBuilder(
    PositionComponent component,
    Cell cell,
    String layerName,
    LayerComponentsStorageMode componentsStorageMode,
  ) =>
      throw 'No custom layer for component type ${component.runtimeType}';

  Future<Vector2?> searchInitialPosition(
    InitialPositionChecker checkFunction, [
    String? worldName,
  ]) async {
    final renderableTiledMap = (await loadTiledComponent()).tileMap;

    for (final renderableLayer in renderableTiledMap.renderableLayers) {
      final layer = renderableLayer.layer;
      if (layer.type != LayerType.objectGroup) {
        continue;
      }

      final objects = (layer as ObjectGroup).objects;
      for (final object in objects) {
        final result = checkFunction.call(
          layer,
          object,
          initialPosition,
          worldName,
        );
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  /// Every map should be initialized after spatial grid initialization.
  /// This function triggers the process. After it the map is loaded and mounted
  /// into the [game].
  /// You can use function's result for any of you purposes (for example, to
  /// parse any additional parameters), but you also would just ignore it.
  /// There is no need to call this function manually. If you have listed
  /// the map in [HasSpatialGridFramework.initializeSpatialGrid] function,
  /// it will be called automatically.
  Future<TiledComponent> init(T game) async {
    _game ??= game;
    tileBuilderContextProvider =
        TileBuilderContextProvider<TiledMapLoader, C>(parent: this);

    final renderableTiledMap = (await loadTiledComponent()).tileMap;

    if (preloadTileSets) {
      await _preloadTileSets(renderableTiledMap.map);
    }

    _processTileType(tileMap: renderableTiledMap);

    if (globalObjectBuilder != null) {
      var layerPriority = 0;
      for (final renderableLayer in renderableTiledMap.renderableLayers) {
        layerPriority++;
        final layer = renderableLayer.layer;
        if (layer.type != LayerType.objectGroup) {
          continue;
        }

        final objects = (layer as ObjectGroup).objects;
        for (final object in objects) {
          final processor = globalObjectBuilder![object.type];
          if (processor != null) {
            final layerInfo = LayerInfo(layer.name, layerPriority);
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
            final context = TileBuilderContext<C>(
              tiledObject: object,
              absolutePosition: position,
              size: size,
              cellRect: rect,
              contextProvider: tileBuilderContextProvider,
              layerInfo: layerInfo,
            );
            processor(context);
          }
        }
      }
    }

    return tiledComponent!;
  }

  Future<void> _preloadTileSets(TiledMap map) =>
      game.tilesetManager.addFromMap(map);

  /// Core build function. Reimplement it only when you have good understanding,
  /// what to do!
  @mustCallSuper
  Future<void> cellBuilder(Cell cell, Component rootComponent) async {
    final contextList = tileBuilderContextProvider.getContextListForCell(cell);
    if (contextList == null || contextList.isEmpty) {
      return;
    }

    game.layersManager.customLayerBuilder = customLayerBuilder;

    for (final context in contextList) {
      final builderType =
          context.tileDataProvider?.tile.type ?? context.tiledObject?.type;
      if (context.removed) {
        continue;
      } else {
        cell.tileBuilderContextProvider = tileBuilderContextProvider;
        await _layerBuilder(cell, builderType, context, rootComponent);
      }

      await cellPostBuilder?.call(context);
    }
  }

  Future<void> _layerBuilder(
    Cell cell,
    String? builderType,
    TileBuilderContext<C> context,
    Component rootComponent,
  ) async {
    final layerInfo = context.layerInfo;
    var layerProcessor = layerBuilders?[layerInfo.name];
    var runTileBuilder = false;
    if (layerProcessor != null) {
      runTileBuilder = await layerProcessor(layerInfo, context);
    } else {
      final builderKeys = layerBuilders?.keys;
      if (builderKeys != null) {
        final searchSubstring = _matchWildcard(layerInfo.name, builderKeys);
        if (searchSubstring != null) {
          layerProcessor = layerBuilders![searchSubstring];
        }
      }
      if (layerProcessor != null) {
        runTileBuilder = await layerProcessor(layerInfo, context);
      } else {
        runTileBuilder = true;
      }
    }

    if (runTileBuilder) {
      await _tileBuilder(cell, builderType, context, rootComponent);
    }
  }

  Future<void> _tileBuilder(
    Cell cell,
    String? builderType,
    TileBuilderContext<C> context,
    Component rootComponent,
  ) async {
    var processor = tileBuilders?[builderType];
    if (processor != null) {
      await processor(context);
    } else {
      final builderKeys = tileBuilders?.keys;
      if (builderKeys != null && builderType != null) {
        final searchSubstring = _matchWildcard(builderType, builderKeys);
        if (searchSubstring != null) {
          processor = tileBuilders![searchSubstring];
        }
      }
      if (processor != null) {
        await processor(context);
      } else {
        await notFoundBuilder?.call(context);
      }
    }
  }

  String? _matchWildcard(String builderType, Iterable<String> builderKeys) {
    for (final searchSubstring in builderKeys) {
      if (!searchSubstring.contains('*')) {
        continue;
      }
      final search = searchSubstring.replaceFirst('*', '').trim();
      if (search.matchAsPrefix(builderType) != null) {
        return searchSubstring;
      }
    }
    return null;
  }

  /// This tile builder merges all tiles into single image. Useful for
  /// rendering tiled maps background layers.
  Future<CellLayer?> genericTileBuilder(TileBuilderContext context) async {
    final provider = context.tileDataProvider;
    if (provider == null) {
      return null;
    }
    final component = await TileComponent.fromProvider(provider);
    component.currentCell = context.cell;
    component.position = context.absolutePosition;
    component.size = context.size;
    var priority = -100;
    if (context.priorityOverride != null) {
      priority = context.priorityOverride!;
    } else {
      priority = context.layerInfo.priority;
    }
    CellLayer? cellLayer;
    if (component.sprite != null) {
      cellLayer = game.layersManager.addComponent(
        component: component,
        layerName: 'static-${context.layerInfo.name}',
        layerType: MapLayerType.static,
        componentsStorageMode: LayerComponentsStorageMode.removeAfterCompile,
        priority: priority,
        renderMode: LayerRenderMode.image,
      );
    } else if (component.animation != null) {
      cellLayer = game.layersManager.addComponent(
        component: component,
        layerName: 'animated-${context.layerInfo.name}',
        layerType: MapLayerType.animated,
        componentsStorageMode: LayerComponentsStorageMode.removeAfterCompile,
        priority: priority,
      );
    }
    return cellLayer;
  }

  /// Is useful when working with worlds with multiple maps and areas without
  /// any map at all
  static int cellPointsOutsideOfMap(Cell cell) {
    final checkList = [
      cell.rect.topLeft,
      cell.rect.bottomLeft,
      cell.rect.topRight,
      cell.rect.bottomRight,
    ];
    for (final map in TiledMapLoader.loadedMaps) {
      if (map.mapRect == Rect.zero) {
        continue;
      }
      final tmpList = checkList.toList();
      for (final cellPoint in tmpList) {
        if (map.mapRect.contains(cellPoint)) {
          checkList.remove(cellPoint);
        }
        if (checkList.isEmpty) {
          return 0;
        }
      }
    }

    return checkList.length;
  }

  static Map<TiledMapLoader, Rect> mapsRectsOnCell(Cell cell) {
    final mapRects = <TiledMapLoader, Rect>{};
    final pointsOutsideMap = cellPointsOutsideOfMap(cell);
    if (pointsOutsideMap >= 4) {
      return mapRects;
    } else if (pointsOutsideMap == 0) {
      cell.fullyInsideMap = true;
    }

    for (final map in TiledMapLoader.loadedMaps) {
      if (map.mapRect == Rect.zero) {
        continue;
      }

      final intersection = map.mapRect.intersect(cell.rect);
      if (intersection.width <= 0 || intersection.height <= 0) {
        continue;
      }
      mapRects[map] = intersection;
    }
    return mapRects;
  }

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

  void _processTileType({
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
            final absolutePosition = Vector2(
                  xOffset.toDouble() * tileMap.map.tileWidth,
                  yOffset.toDouble() * tileMap.map.tileWidth,
                ) +
                initialPosition;

            final size = Vector2(
              tileMap.map.tileWidth.toDouble(),
              tileMap.map.tileWidth.toDouble(),
            );
            final tileCenter = absolutePosition + size / 2;

            TileCache? cache;
            if (preloadTileSets) {
              final name = tileset.name;
              final type = tileData.type;
              if (name != null && type != null) {
                cache = getPreloadedTileData(name, type);
              }
            }

            final tileDataProvider = TileDataProvider(tileData, tileset, cache);

            Rect rect;
            if (lazyLoad) {
              rect = game.spatialGrid.getCellRectAtPosition(tileCenter);
            } else {
              final cell = game.spatialGrid.createNewCellAtPosition(tileCenter);
              rect = cell.rect;
            }
            tileBuilderContextProvider.addContext(
              TileBuilderContext<C>(
                tileDataProvider: tileDataProvider,
                absolutePosition: absolutePosition,
                size: size,
                cellRect: rect,
                contextProvider: tileBuilderContextProvider,
                layerInfo: layerInfo,
              ),
            );
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
          final objectCenter = position + size / 2;
          Rect rect;
          if (lazyLoad) {
            rect = game.spatialGrid.getCellRectAtPosition(objectCenter);
          } else {
            final cell = game.spatialGrid.createNewCellAtPosition(objectCenter);
            rect = cell.rect;
          }

          tileBuilderContextProvider.addContext(
            TileBuilderContext<C>(
              tiledObject: object,
              absolutePosition: position,
              size: size,
              cellRect: rect,
              contextProvider: tileBuilderContextProvider,
              layerInfo: layerInfo,
            ),
          );
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

  static void disposeAll() {
    for (final map in loadedMaps) {
      map.tileBuilderContextProvider.clearContextStorage();
      map._game = null;
    }
    loadedMaps.clear();
  }
}
