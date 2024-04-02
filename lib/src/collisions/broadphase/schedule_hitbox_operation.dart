part of '../broadphase.dart';

@internal
@immutable
class ScheduledHitboxOperation {
  const ScheduledHitboxOperation({
    required this.add,
    required this.active,
    required this.hitbox,
    required this.cell,
    required this.all,
  });

  const ScheduledHitboxOperation.addActive({
    required this.hitbox,
    required this.cell,
  })  : add = true,
        active = true,
        all = false;

  const ScheduledHitboxOperation.addPassive({
    required this.hitbox,
    required this.cell,
  })  : add = true,
        active = false,
        all = false;

  const ScheduledHitboxOperation.removeActive({
    required this.hitbox,
    required this.cell,
  })  : add = false,
        active = true,
        all = false;

  const ScheduledHitboxOperation.removePassive({
    required this.hitbox,
    required this.cell,
  })  : add = false,
        active = false,
        all = false;

  const ScheduledHitboxOperation.addToAll({
    required this.hitbox,
    required this.cell,
  })  : add = true,
        active = false,
        all = true;

  const ScheduledHitboxOperation.removeFromAll({
    required this.hitbox,
    required this.cell,
  })  : add = false,
        active = false,
        all = true;

  final bool add;
  final bool active;
  final bool all;
  final ShapeHitbox hitbox;
  final Cell cell;
}
