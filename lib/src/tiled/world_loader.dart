import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

typedef MapLoaderFactory = TiledMapLoader Function();

class WorldLoader {
  WorldLoader({
    required this.fileName,
    required this.mapLoader,
    this.loadWholeMap = true,
  });

  final String fileName;
  WorldData? worldData;
  final Map<String, MapLoaderFactory> mapLoader;
  late final HasSpatialGridFramework game;
  final List<TiledMapLoader> _maps = [];

  final bool loadWholeMap;
  TiledMapLoader? currentMap;
  Rect? _previousMapRect;

  bool currentMapChanged = false;

  Future loadWorldData() async {
    worldData ??= await WorldData.fromFile('assets/tiles/$fileName');
  }

  Future<(Vector2?, TiledMapLoader?)> searchInitialPosition(
    InitialPositionChecker checkFunction,
  ) async {
    await loadWorldData();
    for (final map in maps) {
      final result = await map.searchInitialPosition(checkFunction, fileName);
      if (result != null) {
        return (result, map);
      }
    }
    return (null, null);
  }

  Future init(HasSpatialGridFramework game) async {
    this.game = game;
    await loadWorldData();
    final futures = <Future>[];
    for (final map in maps) {
      futures.add(map.init(game));
    }

    await Future.wait<void>(futures);
    TiledMapLoader.loadedMaps.addAll(maps);
  }

  List<TiledMapLoader> get maps {
    if (_maps.isNotEmpty) {
      return _maps;
    }
    final data = worldData;
    if (data == null) {
      return _maps;
    }
    for (final map in data.maps) {
      var factory = mapLoader[map.fileName.replaceAll('.tmx', '')];
      if (factory == null) {
        final genericMapLoader = mapLoader['all'];
        if (genericMapLoader != null) {
          factory = genericMapLoader;
        } else {
          continue;
        }
      }
      final loader = factory.call();
      loader.initialPosition = Vector2(map.x.toDouble(), map.y.toDouble());
      loader.fileName = map.fileName;
      _maps.add(loader);
    }

    return _maps;
  }

  TiledMapLoader? updateCurrentMap(Vector2 position) {
    for (final map in maps) {
      if (map.mapRect.containsPoint(position)) {
        if (_previousMapRect != map.mapRect) {
          _previousMapRect = currentMap?.mapRect;
          currentMapChanged = true;
          currentMap = map;
        }
        return map;
      }
    }
    currentMap = null;
    return null;
  }

  Set<TiledMapLoader> findNeighbourMaps() {
    final centralMap = currentMap;
    if (centralMap == null) {
      return {};
    }

    final grid = SpatialGrid(
      cellSize: centralMap.mapRect.size,
      initialPosition: centralMap.mapRect.center.toVector2(),
    );
    final centralCell = grid.currentCell;
    if (centralCell == null) {
      return {};
    }

    final rectToCheck = List<Rect>.of(
      <Rect>[
        centralCell.right.rect,
        centralCell.right.top.rect,
        centralCell.right.bottom.rect,
        centralCell.left.rect,
        centralCell.left.top.rect,
        centralCell.left.bottom.rect,
        centralCell.top.rect,
        centralCell.bottom.rect,
      ],
      growable: false,
    );

    final neighbours = <TiledMapLoader>{};
    for (final rect in rectToCheck) {
      for (final map in maps) {
        if (map.mapRect.overlaps(rect)) {
          neighbours.add(map);
        }
      }
    }
    return neighbours;
  }
}
