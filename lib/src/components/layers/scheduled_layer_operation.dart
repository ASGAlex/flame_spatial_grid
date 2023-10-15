import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

@immutable
class ScheduledLayerOperation {
  const ScheduledLayerOperation({
    required this.cellLayer,
    required this.compileToSingleLayer,
    required this.optimizeCollisions,
    this.stateAfterOperation,
  });

  final CellLayer cellLayer;
  final bool optimizeCollisions;
  final bool compileToSingleLayer;
  final CellState? stateAfterOperation;

  void run() {
    if (cellLayer.isRemovedLayer) {
      return;
    }
    if (optimizeCollisions) {
      cellLayer.collisionOptimizer.optimize();
    }
    if (compileToSingleLayer) {
      cellLayer.compileToSingleLayer(cellLayer.components);
      cellLayer.postCompileActions();
    }
    if (stateAfterOperation != null &&
        cellLayer.currentCell?.state != stateAfterOperation) {
      cellLayer.currentCell?.state = stateAfterOperation!;
    }
  }
}
