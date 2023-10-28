import 'package:flame/components.dart';

abstract interface class MacroObjectInterface {
  Vector2 get macroSize;

  Vector2 get macroPosition;
}

class MacroObject {
  MacroObject({required this.size, required this.position});

  final Vector2 size;
  final Vector2 position;

  int _index = 0;

  void _expandTo(MacroObject other) {}
}

/// хз мне ничего тут не нравится. надо подумать и переписать.
/// Идея в том, чтобы было хранилице объектов, чтобы по хитбоксам
/// раскидать только ссылки, и в случае мерджа двух объектов просто
/// подменялись ссылки

class MacroObjectsStorage {
  final List<MacroObject> _objects = [];
  final _lastIndex = 0;

  void add(MacroObject object) {
    _objects.add(object);
    object._index = _objects.length - 1;
  }

  void mergeObjects(MacroObject one, MacroObject two) {
    one._expandTo(two);
  }
}
