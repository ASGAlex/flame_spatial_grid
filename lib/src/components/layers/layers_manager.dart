import 'dart:collection';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

class LayersManager {
  LayersManager(this.game);

  @internal
  final layers = HashMap<Cell, HashMap<String, CellLayer>>();

  HasSpatialGridFramework game;

  @internal
  final Component layersRootComponent = Component();

  addLayer(CellLayer layer) {
    final cell = layer.currentCell;
    if (cell == null) {
      throw 'layer must have a cell';
    }
    if (layers[cell] == null) {
      layers[cell] = HashMap<String, CellLayer>();
    }
    layers[cell]?[layer.name] = layer;
    layersRootComponent.add(layer);
  }

  void removeLayer({required String name, required Cell cell}) {
    final layer = layers[cell]?.remove(name);
    if (layer != null) {
      layersRootComponent.remove(layer);
    }
  }

  CellLayer? getLayer({required String name, required Cell cell}) =>
      layers[cell]?[name];

  CellLayer addComponent({
    required HasGridSupport component,
    required MapLayerType layerType,
    required String layerName,
    bool absolutePosition = true,
    bool optimizeCollisions = true,
    int priority = 1,
  }) {
    final cell = component.currentCell;
    if (cell == null) {
      throw 'Cell must be specified!';
    }
    CellLayer? layer = getLayer(name: layerName, cell: cell);
    final isNew = layer == null;
    switch (layerType) {
      case MapLayerType.static:
        if (component is! SpriteComponent) {
          throw 'Component ${component.runtimeType} must be SpriteComponent!';
        }
        if (isNew) {
          layer = CellStaticLayer(cell, name: layerName);
        }
        break;
      case MapLayerType.animated:
        if (component is! SpriteAnimationComponent) {
          throw 'Component ${component.runtimeType} must be SpriteAnimationComponent!';
        }
        if (isNew) {
          layer = CellStaticAnimationLayer(cell, name: layerName);
        }
        break;
      case MapLayerType.trail:
        if (isNew) {
          layer = CellTrailLayer(cell, name: layerName);
        }
        break;
    }

    if (absolutePosition) {
      component.position = component.position - cell.rect.topLeft.toVector2();
    }
    layer.add(component);

    if (isNew) {
      addLayer(layer);
      layer.priority = priority;
      layer.optimizeCollisions = optimizeCollisions;
    }

    return layer;
  }
}
