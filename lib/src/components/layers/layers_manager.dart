import 'dart:collection';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

/// The class provides easy-to-use API layer to access game layer's
/// Every layer is added into [layersRootComponent] to optimize priority
/// recalculation.
///
class LayersManager {
  LayersManager(this.game);

  @internal
  final layers = HashMap<Cell, HashMap<String, CellLayer>>();

  HasSpatialGridFramework game;

  final Component layersRootComponent = Component();

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
    layersRootComponent.add(layer);
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
    required HasGridSupport component,
    required MapLayerType layerType,
    required String layerName,
    bool absolutePosition = true,
    bool optimizeCollisions = true,
    bool isRenewable = true,
    int priority = 1,
  }) {
    var cell = component.currentCell;
    cell ??= component.currentCell =
        game.spatialGrid.findExistingCellByPosition(component.position);
    cell ??= component.currentCell =
        game.spatialGrid.createNewCellAtPosition(component.position);
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

    layer.add(component);

    if (isNew) {
      addLayer(layer);
      layer.priority = priority;
      layer.optimizeCollisions = optimizeCollisions;
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
}
