part of '../broadphase.dart';

class Comparator {
  late final BloomFilterProvider _bloomFilter;
  PureTypeCheck? _globalPureTypeCheck;

  final _checkByTypeCache = <int, bool>{};

  bool componentFullTypeCheck(
    PureTypeCheckInterface active,
    PureTypeCheckInterface potential, {
    bool potentialCanBeActive = false,
  }) {
    final aType = active.runtimeType;
    final pType = potential.runtimeType;
    final canToCollide = globalTypeCheck(
      aType,
      pType,
      potentialCanBeActive: potentialCanBeActive,
    );

    if (canToCollide) {
      return active.pureTypeCheck(pType) && potential.pureTypeCheck(aType);
    }
    return false;
  }

  bool globalTypeCheck(
    Type active,
    Type potential, {
    bool potentialCanBeActive = false,
  }) {
    final key = _bloomFilter.generateKey(
      active,
      potential,
    );
    var canToCollide = true;
    final bloomCheck = _bloomFilter.check(key);
    if (bloomCheck == null) {
      final cache = _checkByTypeCache[key];
      if (cache == null) {
        canToCollide = _globalTypeCheckNoBloom(
          active,
          potential,
          potentialCanBeActive: potentialCanBeActive,
        );
        _checkByTypeCache[key] = canToCollide;
      } else {
        canToCollide = cache;
      }
    } else {
      canToCollide = bloomCheck;
    }

    return canToCollide;
  }

  bool _globalTypeCheckNoBloom(
    Type active,
    Type potential, {
    bool potentialCanBeActive = false,
  }) {
    if (_globalPureTypeCheck == null) {
      return true;
    }

    final canCollide = _globalPureTypeCheck!.call(
      active,
      potential,
    );
    if (potentialCanBeActive) {
      return canCollide &&
          _globalPureTypeCheck!.call(
            potential,
            active,
          );
    }
    return canCollide;
  }

  void clear() => _checkByTypeCache.clear();
}
