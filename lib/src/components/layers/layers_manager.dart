import 'dart:collection';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

class LayersRootComponent extends Component with UpdateOnDemand {}

/// The class provides easy-to-use API layer to access game layer's
/// Every layer is added into [layersRootComponent] to optimize priority
/// recalculation.
///
class LayersManager {
  LayersManager(this.game);

  @internal
  final layers = HashMap<Cell, HashMap<String, CellLayer>>();

  HasSpatialGridFramework game;

  final layersRootComponent = <int, LayersRootComponent>{};

  /// Adding manually created [CellLayer] into [layersRootComponent].
  /// Usually there is no need to use this function, try [addComponent] instead.
  void addLayer(CellLayer layer) {
    final cell = layer.currentCell;
    if (cell == null) {
      throw 'layer must have a cell';
    }
    if (layers[cell] == null) {
      layers[cell] = HashMap<String, CellLayer>();
    }
    layers[cell]?[layer.name] = layer;

    var storage = layersRootComponent[layer.priority];
    if (storage == null) {
      storage = layersRootComponent[layer.priority] = LayersRootComponent();
      storage.priority = layer.priority;
      game.rootComponent.add(storage);
    }
    storage.add(layer);
  }

  /// Removes layer from game tree.
  /// Usually there is no need to manually remove any layer. Each layer is
  /// managed by the Framework and will be automatically removed in cell's
  /// removal or if the layer become empty, without components inside.
  void removeLayer({required String name, required Cell cell}) {
    final cellLayers = layers[cell];
    if (cellLayers == null) {
      return;
    }
    final layer = cellLayers.remove(name);
    layer?.removeFromParent();
    if (cellLayers.isEmpty) {
      layers.remove(cell);
    }
  }

  /// Gets a layer by it's unique [name] and [cell].
  CellLayer? getLayer({required String name, required Cell cell}) =>
      layers[cell]?[name];

  /// Most useful function for end-user usage. It adds the [component] into
  /// new or existing layer with unique [layerName]. [layerType] enum is the
  /// parameter for layer's factory, which type will the new layer be. See
  /// [MapLayerType] for future details.
  /// Change [priority] to set whole layer's priority. Please note that each
  /// [addComponent] call will rewrite it's value to last one.
  /// If your component have position in cell's relative coordinate space,
  /// change [absolutePosition] to false.
  /// If you layer does not contain any collideable components, it is
  /// recommended to switch [optimizeCollisions] parameter to 'false'.
  /// Change [isRenewable] to "false" if you are sure that components will
  /// newer be changed, added or removed to the layer.
  CellLayer addComponent({
    required PositionComponent component,
    required MapLayerType layerType,
    required String layerName,
    Cell? currentCell,
    bool absolutePosition = true,
    bool optimizeCollisions = true,
    LayerRenderMode renderMode = LayerRenderMode.auto,
    bool isRenewable = true,
    int? priority,
  }) {
    Cell? cell;
    if (currentCell == null && component is HasGridSupport) {
      cell = component.currentCell ?? game.findCellForComponent(component);
    } else if (currentCell != null) {
      cell = currentCell;
    }
    if (cell == null) {
      throw 'The "component" should be "HasGridSupport" subtype or '
          '"currentCell" parameter should be passed.';
    }
    var layer = getLayer(name: layerName, cell: cell);
    final isNew = layer == null;
    switch (layerType) {
      case MapLayerType.static:
        if (isNew) {
          layer =
              CellStaticLayer(cell, name: layerName, isRenewable: isRenewable);
        }
        break;
      case MapLayerType.animated:
        if (component is! SpriteAnimationComponent) {
          throw 'Component ${component.runtimeType} '
              'must be SpriteAnimationComponent!';
        }
        if (isNew) {
          layer = CellStaticAnimationLayer(
            cell,
            name: layerName,
            isRenewable: isRenewable,
          );
        }
        break;
      case MapLayerType.trail:
        if (isNew) {
          layer =
              CellTrailLayer(cell, name: layerName, isRenewable: isRenewable);
        }
        break;
    }

    if (absolutePosition) {
      component.position
          .setFrom(component.position - cell.rect.topLeft.toVector2());
    }

    if (layerType == MapLayerType.trail) {
      layer.add(component);
    } else {
      if (component.isMounted) {
        component.parent = layer;
      } else {
        layer.add(component);
      }
    }

    if (isNew) {
      layer.priority = priority ?? component.priority;
      addLayer(layer);
      layer.optimizeCollisions = optimizeCollisions;
      layer.renderMode = renderMode;
    }

    return layer;
  }

  Future waitForComponents() {
    final futures = <Future>[];
    for (final cellLayerList in layers.values) {
      for (final layer in cellLayerList.values) {
        futures.add(layer.waitForComponents());
      }
    }
    return Future.wait<void>(futures);
  }

  void rescanLayersForUpdate() {
    for (final entry in layersRootComponent.entries) {
      entry.value.isUpdateNeeded = true;
    }
  }
}
