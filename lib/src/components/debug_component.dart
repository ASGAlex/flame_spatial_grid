import 'package:flame/components.dart';
import 'package:flame/image_composition.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/material.dart';

class SpatialGridDebugComponent extends PositionComponent
    with HasPaint<String> {
  SpatialGridDebugComponent(this.spatialGrid) : super(priority: -100);

  final SpatialGrid spatialGrid;

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
    TextPaint textPaintOK = TextPaint(
      style: const TextStyle(
          fontSize: 5.0, color: Colors.purple, fontWeight: FontWeight.bold),
    );
    final fill = getPaint('fill');
    final inactive = getPaint('inactive');
    final unloaded = getPaint('unloaded');
    final border = getPaint('border');
    for (final element in spatialGrid.cells.entries) {
      if (element.value.state == CellState.active) {
        canvas.drawRect(element.key, fill);
      } else if (element.value.state == CellState.inactive) {
        canvas.drawRect(element.key, inactive);
      } else {
        canvas.drawRect(element.key, unloaded);
      }
      canvas.drawRect(element.key, border);
      if (element.value.rawLeft != null) {
        final pos = Vector2(element.key.left + 2,
            element.key.bottom - element.key.size.height / 2);
        textPaintOK.render(canvas, 'L', pos);
      }
      if (element.value.rawRight != null) {
        final pos = Vector2(element.key.right - 8,
            element.key.bottom - element.key.size.height / 2);
        textPaintOK.render(canvas, 'R', pos);
      }
      if (element.value.rawTop != null) {
        final pos = Vector2(
            element.key.left + element.key.size.width / 2, element.key.top + 2);
        textPaintOK.render(canvas, 'T', pos);
      }
      if (element.value.rawBottom != null) {
        final pos = Vector2(element.key.left + element.key.size.width / 2,
            element.key.bottom - 15);
        textPaintOK.render(canvas, 'B', pos);
      }

      // textPaint.render(canvas, element.value.state.toString(),
      //     element.key.center.toVector2());
      // textPaint.render(
      //     canvas,
      //     "(${element.key.left},${element.key.top} - ${element.key.right}, ${element.key.bottom})",
      //     element.key.center.toVector2());
    }
  }
}
