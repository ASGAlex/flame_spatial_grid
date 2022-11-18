import 'package:flame/components.dart';

import 'cell.dart';

typedef CellBuilderFunction = Future Function(
    Cell cell, Component parentComponent);

class CellBuilder {
  CellBuilder({required this.builder, required this.parentComponent});

  final Component parentComponent;
  final CellBuilderFunction builder;

  Future build(Cell cell) {
    return builder.call(cell, parentComponent);
  }
}
