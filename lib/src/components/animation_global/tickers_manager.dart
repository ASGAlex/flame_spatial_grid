import 'dart:collection';

import 'package:flame/sprite.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class TickersManager {
  final _tickers = HashMap<String, SpriteAnimationTicker>();

  SpriteAnimationTicker getTicker(
    String animationType,
    SpriteAnimation animation,
  ) {
    var ticker = _tickers[animationType];
    return ticker ??=
        _tickers[animationType] = SpriteAnimationTickerGlobal(animation);
  }

  void update(double dt) {
    for (final ticker in _tickers.values) {
      ticker.update(dt);
    }
  }
}
