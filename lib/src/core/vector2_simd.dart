import 'dart:typed_data';

import 'package:flame/components.dart';

extension Vector2SIMD on Vector2 {
  Float64x2 toFloat64x2() => Float64x2(x, y);

  static Vector2 fromFloat64x2(Float64x2 source) => Vector2(source.x, source.y);
}

extension Float64x2AsVector on Float64x2 {
  Float64x2 clone() => Float64x2(x, y);
}
