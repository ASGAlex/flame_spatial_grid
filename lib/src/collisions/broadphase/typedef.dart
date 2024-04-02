part of '../broadphase.dart';

typedef ExternalMinDistanceCheckSpatialGrid = bool Function(
  ShapeHitbox activeItem,
  ShapeHitbox potential,
);

typedef PureTypeCheck = bool Function(
  Type activeItemType,
  Type potentialItemType,
);

typedef ComponentExternalTypeCheck = bool Function(
  PositionComponent first,
  PositionComponent second,
);

enum RayTraceMode {
  allHitboxes,
  groupedHitboxes,
}

mixin DebuggerPause {}

class DummyHitbox extends BoundingHitbox {}
