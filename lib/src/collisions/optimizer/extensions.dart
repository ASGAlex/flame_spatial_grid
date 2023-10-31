import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/src/collisions/optimizer/collision_optimizer.dart';

extension ToRectSpecial on PositionComponent {
  Rect toRectSpecial() {
    final cache = CollisionOptimizer.rectCache[this];
    if (cache != null) {
      return cache;
    } else {
      final parentPosition = (parent as PositionComponent?)?.position;
      if (parentPosition == null) {
        return Rect.zero;
      }
      final cache = Rect.fromLTWH(
        parentPosition.x + position.x,
        parentPosition.y + position.y,
        size.x,
        size.y,
      );
      CollisionOptimizer.rectCache[this] = cache;
      return cache;
    }
  }
}
