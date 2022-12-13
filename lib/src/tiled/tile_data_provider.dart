import 'dart:async';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/image_composition.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flutter/foundation.dart';

/// Utility class allows to process each map tile individually
/// Usage example:
/// ``` dart
/// final mapComponent = await TiledComponent.load('map.tmx', Vector2.all(16));
/// TileProcessor.processTileType(
///   tileMap: mapComponent.tileMap,
///   processorByType: <String, TileProcessorFunc>{
///     'water': ((tile, position, size) {
///       /// Create here a new object, save tile data or process it
///       /// a way your game logics need
///     }),
///   },
///   layersToLoad: [
///   'water',
/// ]);
/// ```
/// You can process individual computations for each tile inside [TileBuilderFunction].
/// Use [getSprite] to get [Sprite] object.
/// Use [getSpriteAnimation] to get [SpriteAnimation] object of the tile.
/// Use [getCollisionRect] to load [RectangleHitbox] if it had been specified in Tiled
///
/// You usually do not need to create the class manually. Call [TileDataProvider.processTileType], and
/// it will do the rest of work.
///
/// If you need to process another map, it might be useful to call [TileDataProvider.clearCache]
/// if new map's tiles are very different from previous one.
class TileDataProvider {
  static final Map<String, Sprite> _spriteCache = {};
  static final Map<String, SpriteAnimation> _spriteAnimationCache = {};
  static final Map<String, Image> _imageCache = {};

  TileDataProvider(this.tile, this.tileset);

  Tile tile;
  Tileset tileset;

  RectangleHitbox? getCollisionRect() {
    if (tile.objectGroup?.type == LayerType.objectGroup) {
      final grp = tile.objectGroup as ObjectGroup;
      if (grp.objects.isNotEmpty) {
        final obj = grp.objects.first;
        return RectangleHitbox(
            size: Vector2(obj.width, obj.height),
            position: Vector2(obj.x, obj.y));
      }
    }
    return null;
  }

  static clearCache() {
    _spriteAnimationCache.clear();
    _spriteCache.clear();
    _imageCache.clear();
  }

  Future<Sprite> getSprite([int tileId = -1]) async {
    if (tileId == -1) {
      tileId = tile.localId;
    }
    final image = tileset.image;
    if (image == null) throw 'Cant load sprite without image';

    final src = image.source;
    if (src == null) throw 'Cant load sprite without image';

    final key = src + tileId.toString() + (tileset.name ?? '');
    var cachedSprite = _getSpriteCache(key);
    if (cachedSprite == null) {
      Image? spriteSheetImg = _getImageCache(src);
      if (spriteSheetImg == null) {
        spriteSheetImg = await Flame.images.load(src);
        _imageCache[src] = spriteSheetImg;
      }
      final maxColumns = _maxColumns(image);
      final row = ((tileId + 0.9) ~/ maxColumns) + 1;
      final column = (tileId + 1) - ((row - 1) * maxColumns);

      cachedSprite = Sprite(spriteSheetImg,
          srcPosition: Vector2(((column - 1) * tileset.tileWidth!).toDouble(),
              ((row - 1) * tileset.tileHeight!).toDouble()),
          srcSize: Vector2(
              tileset.tileWidth!.toDouble(), tileset.tileHeight!.toDouble()));
      _spriteCache[key] = cachedSprite;
    }
    return cachedSprite;
  }

  Future<SpriteAnimation?> getSpriteAnimation() async {
    final image = tileset.image;
    if (image == null) throw 'Cant load sprite without image';

    final src = image.source;
    if (src == null) throw 'Cant load sprite without image';

    final key = src + tile.localId.toString() + (tileset.name ?? '');
    var cachedAnimation = _getAnimationCache(key);
    if (cachedAnimation == null) {
      if (tile.animation.isEmpty) return null;
      final List<Sprite> spriteList = [];
      final List<double> stepTimes = [];
      for (final frame in tile.animation) {
        final sprite = await getSprite(frame.tileId);
        spriteList.add(sprite);
        stepTimes.add(frame.duration / 1000);
      }
      cachedAnimation =
          SpriteAnimation.variableSpriteList(spriteList, stepTimes: stepTimes);
      _spriteAnimationCache[key] = cachedAnimation;
    }
    return cachedAnimation;
  }

  int _maxColumns(TiledImage image) {
    final maxWidth = image.width;
    final tileWidth = tileset.tileWidth;
    if (maxWidth == null || tileWidth == null) throw 'No tile dimensions';

    return maxWidth ~/ tileWidth;
  }

  Image? _getImageCache(String image) {
    try {
      return _imageCache[image];
    } catch (e) {
      return null;
    }
  }

  Sprite? _getSpriteCache(String key) {
    try {
      return _spriteCache[key];
    } catch (e) {
      return null;
    }
  }

  SpriteAnimation? _getAnimationCache(String key) {
    try {
      return _spriteAnimationCache[key];
    } catch (e) {
      return null;
    }
  }
}

@immutable
class CellBuilderContext {
  const CellBuilderContext(this.tileBuilder, this.position, this.size);

  final Vector2 position;
  final Vector2 size;
  final TileDataProvider tileBuilder;
}
