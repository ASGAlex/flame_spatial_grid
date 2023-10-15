import 'package:flame_spatial_grid/flame_spatial_grid.dart';

class MacroObjectsBuilder {
  final _layers = <String, Set<CellLayer>>{};

  void addLayer(CellLayer layer) {
    var layersSet = _layers[layer.name];
    if (layersSet == null) {
      layersSet = <CellLayer>{};
      _layers[layer.name] = layersSet;
    }
    layersSet.add(layer);
  }

  void removeLayer(CellLayer layer) {
    final layersSet = _layers[layer.name];
    if (layersSet != null) {
      layersSet.remove(layer);
    }
  }

  void buildMacroObjects() {
    for (final entry in _layers.entries) {
      final hitboxesToMerge = <BoundingHitbox>[];
      for (final layer in entry.value) {
        for (final component in layer.components) {
          if (component is! HasGridSupport) {
            continue;
          }
          hitboxesToMerge.add(component.boundingBox);
        }
      }
    }
  }

  // Iterable<GroupHitbox> _findOverlappingRects(GroupHitbox group) {
  //   final hitboxes =
  // }
}
