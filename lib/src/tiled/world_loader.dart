import 'package:flame/components.dart';
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

  Future loadWorldData() async {
    worldData ??= await WorldData.fromFile('assets/tiles/$fileName');
  }

  Future<Vector2?> searchInitialPosition(
    InitialPositionChecker checkFunction,
  ) async {
    await loadWorldData();
    for (final map in maps) {
      final result = await map.searchInitialPosition(checkFunction, fileName);
      if (result != null) {
        return result;
      }
    }
    return null;
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
}
