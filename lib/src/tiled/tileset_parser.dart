import 'package:flame/flame.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:xml/xml.dart';

class TilesetParser {
  static Future<Tileset> fromFile(String fileName) async {
    final contents = await Flame.bundle.loadString('assets/tiles/$fileName');
    return parseTsx(contents);
  }

  static Tileset parseTsx(String xml) {
    final xmlElement = XmlDocument.parse(xml).rootElement;
    if (xmlElement.name.local != 'tileset') {
      throw 'XML is not in TSX format';
    }
    final parser = XmlParser(xmlElement);
    return Tileset.parse(
      parser,
    );
  }
}
