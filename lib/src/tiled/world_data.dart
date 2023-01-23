import 'dart:convert';

import 'package:flame/flame.dart';
import 'package:meta/meta.dart';

class WorldData {
  WorldData({
    required this.type,
    required this.onlyShowAdjacentMaps,
    required this.maps,
  });

  final List<WorldMapData> maps;
  final bool onlyShowAdjacentMaps;
  final String type;

  static Future<WorldData> fromFile(String fileName) async {
    final source = await Flame.bundle.loadString(fileName);
    final dynamic data = jsonDecode(source);
    final type = _getField(data, 'type') as String;
    final onlyShowAdjacentMaps =
        _getField(data, 'onlyShowAdjacentMaps') as bool;
    final mapsRaw = _getField(data, 'maps') as Iterable;
    final maps = <WorldMapData>[];
    for (final mapData in mapsRaw) {
      maps.add(
        WorldMapData(
          width: _getField(mapData, 'width') as int,
          height: _getField(mapData, 'height') as int,
          x: _getField(mapData, 'x') as int,
          y: _getField(mapData, 'y') as int,
          fileName: _getField(mapData, 'fileName') as String,
        ),
      );
    }

    return WorldData(
      type: type,
      onlyShowAdjacentMaps: onlyShowAdjacentMaps,
      maps: maps,
    );
  }

  static dynamic _getField(dynamic data, String fieldName) {
    // ignore: avoid_dynamic_calls
    final dynamic value = data[fieldName];
    if (value == null) {
      throw 'Field "$fieldName" does not exists!';
    }
    return value;
  }
}

@immutable
class WorldMapData {
  const WorldMapData({
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    required this.fileName,
  });

  final int width;
  final int height;
  final int x;
  final int y;
  final String fileName;
}
