import 'package:flame/components.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class WorldLoader {
  WorldLoader({required this.fileName, required this.mapLoader});

  final String fileName;
  WorldData? worldData;
  final Map<String, TiledMapLoader> mapLoader;
  late final HasSpatialGridFramework game;

  Future init(HasSpatialGridFramework game) async {
    this.game = game;
    worldData = await WorldData.fromFile('assets/tiles/$fileName');
    final futures = <Future>[];
    for (final map in maps) {
      futures.add(map.init(game));
    }

    await Future.wait(futures);
    TiledMapLoader.loadedMaps.addAll(maps);
  }

  List<TiledMapLoader> get maps {
    final result = <TiledMapLoader>[];
    final data = worldData;
    if (data == null) return result;
    for (final map in data.maps) {
      final loader = mapLoader[map.fileName.replaceAll('.tmx', '')];
      if (loader == null) continue;
      loader.initialPosition = Vector2(map.x.toDouble(), map.y.toDouble());
      loader.fileName = map.fileName;
      result.add(loader);
    }

    return result;
  }
}
