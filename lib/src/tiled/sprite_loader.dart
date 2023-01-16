import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:tiled/tiled.dart';

extension SpriteLoader on Tile {
  Future<Sprite> getSprite(Tileset tileset) {
    final src = image?.source ?? tileset.image?.source;
    if (src == null) {
      throw 'Cant load sprite without image';
    }

    var position = imageRect?.topLeft.toVector2();
    var size = imageRect?.size.toVector2();
    if ((position == null && size == null) || size == Vector2.zero()) {
      final tileWidth = tileset.tileWidth;
      final tileHeight = tileset.tileHeight;
      if (tileWidth != null && tileHeight != null) {
        final maxColumns = _maxColumns(tileset);
        final row = ((localId + 0.9) ~/ maxColumns) + 1;
        final column = (localId + 1) - ((row - 1) * maxColumns);
        position = Vector2(
          ((column - 1) * tileWidth).toDouble(),
          ((row - 1) * tileHeight).toDouble(),
        );
        size = Vector2(tileWidth.toDouble(), tileHeight.toDouble());
      }
    }

    if (position != null && size != null) {
      return Sprite.load(src, srcPosition: position, srcSize: size);
    }
    throw "Can't determine sprite image size";
  }

  Future<SpriteAnimation?> getSpriteAnimation(Tileset tileset) async {
    if (animation.isEmpty) {
      return null;
    }
    final src = image?.source ?? tileset.image?.source;
    if (src == null) {
      throw 'Cant load sprite without image';
    }

    final spriteList = <Sprite>[];
    final stepTimes = <double>[];

    for (final frame in animation) {
      final frameTile = Tile(localId: frame.tileId);
      final sprite = await frameTile.getSprite(tileset);
      spriteList.add(sprite);
      stepTimes.add(frame.duration / 1000);
    }
    return SpriteAnimation.variableSpriteList(spriteList, stepTimes: stepTimes);
  }

  int _maxColumns(Tileset tileset) {
    final maxWidth = tileset.image?.width;
    final tileWidth = tileset.tileWidth;
    if (maxWidth == null || tileWidth == null) {
      throw 'No tile dimensions';
    }

    return maxWidth ~/ tileWidth;
  }
}
