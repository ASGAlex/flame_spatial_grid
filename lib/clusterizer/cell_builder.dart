import 'package:cluisterizer_test/clusterizer/clusterized_component.dart';
import 'package:flame/components.dart';

import 'cell.dart';

typedef CellBuilderFunction = Future<List<ClusterizedComponent>> Function(
    Cell cell, Component parentComponent);

class CellBuilder {
  CellBuilder({required this.builder, Component? parentComponent});

  late Component parentComponent;
  final CellBuilderFunction builder;

  Future build(Cell cell) async {
    final componentsList = await builder.call(cell, parentComponent);
    for (var component in componentsList) {
      component.currentCell = cell;
      cell.components.add(component);
      parentComponent.add(component);
    }
  }
}
