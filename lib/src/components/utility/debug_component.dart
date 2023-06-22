import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/image_composition.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/material.dart';

class SpatialGridDebugComponent extends PositionComponent
    with HasPaint<String> {
  SpatialGridDebugComponent(this.spatialGrid) : super(priority: 10000);

  final SpatialGrid spatialGrid;

  @override
  void updateTree(double dt) {}

  @override
  FutureOr<void> onLoad() {
    const opacity = 0.8;
    final paintFill = Paint();
    paintFill.style = PaintingStyle.fill;
    paintFill.color = Colors.lightGreen.withOpacity(opacity);
    setPaint('fill', paintFill);

    final paintFillInactive = Paint();
    paintFillInactive.style = PaintingStyle.fill;
    paintFillInactive.color = Colors.blueGrey.withOpacity(opacity);
    setPaint('inactive', paintFillInactive);

    final paintFillUnloaded = Paint();
    paintFillUnloaded.style = PaintingStyle.fill;
    paintFillUnloaded.color = Colors.black54.withOpacity(opacity);
    setPaint('unloaded', paintFillUnloaded);

    final paintFillBroken = Paint();
    paintFillBroken.style = PaintingStyle.fill;
    paintFillBroken.color = Colors.orange.withOpacity(opacity);
    setPaint('broken', paintFillBroken);

    final paintBorder = Paint();
    paintBorder.style = PaintingStyle.stroke;
    paintBorder.color = Colors.redAccent.withOpacity(opacity);
    paintBorder.strokeWidth = 1;
    setPaint('border', paintBorder);

    return super.onLoad();
  }

  @override
  void render(Canvas canvas) {
    final textPaintOK = TextPaint(
      style: const TextStyle(
        fontSize: 5.0,
        color: Colors.purple,
        fontWeight: FontWeight.bold,
      ),
    );
    final fill = getPaint('fill');
    final inactive = getPaint('inactive');
    final unloaded = getPaint('unloaded');
    final broken = getPaint('broken');
    final border = getPaint('border');
    for (final element in spatialGrid.cells.entries) {
      if (element.value.state == CellState.active) {
        if (element.value.hasOutOfBoundsComponents) {
          canvas.drawRect(element.key, broken);
          textPaintOK.render(
            canvas,
            element.value.outOfBoundsCounter.toString(),
            element.key.center.toVector2(),
          );
        } else {
          canvas.drawRect(element.key, fill);
        }
      } else if (element.value.state == CellState.inactive) {
        if (element.value.hasOutOfBoundsComponents) {
          canvas.drawRect(element.key, broken);
          textPaintOK.render(
            canvas,
            element.value.outOfBoundsCounter.toString(),
            element.key.center.toVector2(),
          );
        } else {
          canvas.drawRect(element.key, inactive);
        }
      } else {
        if (element.value.hasOutOfBoundsComponents) {
          canvas.drawRect(element.key, broken);
          textPaintOK.render(
            canvas,
            element.value.outOfBoundsCounter.toString(),
            element.key.center.toVector2(),
          );
        } else {
          canvas.drawRect(element.key, unloaded);
        }
      }
      canvas.drawRect(element.key, border);
      if (element.value.rawLeft != null) {
        final pos = Vector2(
          element.key.left + 2,
          element.key.bottom - element.key.size.height / 2,
        );
        textPaintOK.render(canvas, 'L', pos);
      }
      if (element.value.rawRight != null) {
        final pos = Vector2(
          element.key.right - 8,
          element.key.bottom - element.key.size.height / 2,
        );
        textPaintOK.render(canvas, 'R', pos);
      }
      if (element.value.rawTop != null) {
        final pos = Vector2(
          element.key.left + element.key.size.width / 2,
          element.key.top + 2,
        );
        textPaintOK.render(canvas, 'T', pos);
      }
      if (element.value.rawBottom != null) {
        final pos = Vector2(
          element.key.left + element.key.size.width / 2,
          element.key.bottom - 15,
        );
        textPaintOK.render(canvas, 'B', pos);
      }
    }
  }
}
