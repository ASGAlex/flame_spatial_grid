import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:tiled/tiled.dart';

extension SpriteLoader on Tile {
  Future<Sprite> getSprite(Tileset tileset) {
    final src = image?.source ?? tileset.image?.source;
    if (src == null) {
      throw 'Cant load sprite without image';
    }

    final drawRect = tileset.computeDrawRect(this);
    final position = Vector2(drawRect.left.toDouble(), drawRect.top.toDouble());
    final size = Vector2(drawRect.width.toDouble(), drawRect.height.toDouble());

    return Sprite.load(src, srcPosition: position, srcSize: size);
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

    final futures = <Future>[];
    for (final frame in animation) {
      final frameTile = Tile(localId: frame.tileId);
      final future = frameTile.getSprite(tileset).then((sprite) {
        spriteList.add(sprite);
        stepTimes.add(frame.duration / 1000);
        return sprite;
      });
      futures.add(future);
    }

    return Future.wait<void>(futures).then<SpriteAnimation>((value) {
      return SpriteAnimation.variableSpriteList(
        spriteList,
        stepTimes: stepTimes,
      );
    });
  }

  Rect? getCollisionRect() {
    final group = objectGroup;
    final type = group?.type;
    if (type == LayerType.objectGroup && group is ObjectGroup) {
      if (group.objects.isNotEmpty) {
        final obj = group.objects.first;
        return Rect.fromLTWH(obj.x, obj.y, obj.width, obj.height);
      }
    }
    return null;
  }
}

extension ConvertToAnimation on Sprite {
  SpriteAnimation toAnimation() =>
      SpriteAnimation.spriteList([this], stepTime: 100000);
}
