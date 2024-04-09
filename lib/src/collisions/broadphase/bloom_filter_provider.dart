part of '../broadphase.dart';

class BloomFilterProvider {
  BloomFilter<int>? _checkByTypeCacheBloomTrue;

  //ignore: use_late_for_private_fields_and_variables
  BloomFilter<int>? _checkByTypeCacheBloomFalse;

  void init(Map<int, bool> result) {
    _checkByTypeCacheBloomTrue = BloomFilter<int>(result.length, 0.01);
    _checkByTypeCacheBloomFalse = BloomFilter<int>(result.length, 0.01);
    for (final item in result.entries) {
      if (item.value) {
        _checkByTypeCacheBloomTrue!.add(item: item.key);
      } else {
        _checkByTypeCacheBloomFalse!.add(item: item.key);
      }
    }
  }

  bool? check(int key) {
    if (_checkByTypeCacheBloomTrue == null) {
      return null;
    }

    return _checkByTypeCacheBloomTrue!.contains(item: key);
    // if (collide) {
    //   final noCollide = _checkByTypeCacheBloomFalse!.contains(item: key);
    //   if (!noCollide) {
    //     return true;
    //   } else {
    //     return false;
    //   }
    // } else {
    //   return false;
    // }
  }

  int generateKey(Type type1, Type type2) => type1.hashCode & type2.hashCode;
}
