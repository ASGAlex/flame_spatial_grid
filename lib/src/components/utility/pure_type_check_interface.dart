import 'package:flame_spatial_grid/flame_spatial_grid.dart';

abstract interface class PureTypeCheckInterface {
  /// Provides components type check to filter components at
  /// broadphase during collision detection.
  ///
  /// This is alternative to [HasSpatialGridFramework] method `pureTypeCheck`.
  /// It allows you to keep collision rules in component scope
  /// but have additional cost for performance.
  bool pureTypeCheck(Type other);
}
