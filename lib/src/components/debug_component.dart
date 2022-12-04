import 'package:flame/components.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';
import 'package:flutter/material.dart';

class ClusterizerDebugComponent extends PositionComponent
    with HasPaint<String> {
  ClusterizerDebugComponent(this.clusterizer);

  final Clusterizer clusterizer;

  @override
  void updateTree(double dt) {}

  @override
  onLoad() {
    final paintFill = Paint();
    paintFill.style = PaintingStyle.fill;
    paintFill.color = Colors.lightGreen;
    setPaint('fill', paintFill);

    final paintFillInactive = Paint();
    paintFillInactive.style = PaintingStyle.fill;
    paintFillInactive.color = Colors.blueGrey;
    setPaint('inactive', paintFillInactive);

    final paintFillUnloaded = Paint();
    paintFillUnloaded.style = PaintingStyle.fill;
    paintFillUnloaded.color = Colors.black54;
    setPaint('unloaded', paintFillUnloaded);

    final paintBorder = Paint();
    paintBorder.style = PaintingStyle.stroke;
    paintBorder.color = Colors.redAccent;
    paintBorder.strokeWidth = 1;
    setPaint('border', paintBorder);

    return null;
  }

  @override
  void render(Canvas canvas) {
    TextPaint textPaint = TextPaint(
      style: TextStyle(
        fontSize: 5.0,
      ),
    );
    final fill = getPaint('fill');
    final inactive = getPaint('inactive');
    final unloaded = getPaint('unloaded');
    final border = getPaint('border');
    for (final element in clusterizer.cells.entries) {
      if (element.value.state == CellState.active) {
        canvas.drawRect(element.key, fill);
      } else if (element.value.state == CellState.inactive) {
        canvas.drawRect(element.key, inactive);
      } else {
        canvas.drawRect(element.key, unloaded);
      }
      canvas.drawRect(element.key, border);

      // textPaint.render(canvas, element.value.state.toString(),
      //     element.key.center.toVector2());
      // textPaint.render(
      //     canvas,
      //     "(${element.key.left},${element.key.top} - ${element.key.right}, ${element.key.bottom})",
      //     element.key.center.toVector2());
    }
  }
}
