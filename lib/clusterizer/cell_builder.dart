import 'package:cluisterizer_test/clusterizer/clusterized_component.dart';
import 'package:flame/components.dart';

import 'cell.dart';

typedef CellBuilderFunction = Future<List<ClusterizedComponent>> Function(
    Cell cell, Component parentComponent);

class CellBuilder {
  CellBuilder({required this.builder, Component? parentComponent});

  late Component rootComponent;
  final CellBuilderFunction builder;

  Future build(Cell cell) async {
    final componentsList = await builder.call(cell, rootComponent);
    for (var component in componentsList) {
      component.currentCell = cell;
      cell.components.add(component);
      rootComponent.add(component);
    }
  }
}
