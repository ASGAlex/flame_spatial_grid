import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid/src/components/utility/action_notifier.dart';
import 'package:flutter/foundation.dart';

mixin RepaintOnDemand on HasGridSupport {
  final _repaintNotifier = ActionNotifier();

  ChangeNotifier get repaintNotifier => _repaintNotifier;

  bool get isRepaintNeeded => _repaintNotifier.isActionNeeded;

  set isRepaintNeeded(bool repaint) {
    _repaintNotifier.isActionNeeded = repaint;
  }

  @override
  void renderTree(Canvas canvas) {
    if (isRepaintNeeded) {
      super.renderTree(canvas);
      _repaintNotifier.isActionNeeded = false;
    }
  }
}

mixin UpdateOnDemand on Component {
  final _updateNotifier = ActionNotifier();

  ChangeNotifier get updateNotifier => _updateNotifier;

  bool get isUpdateNeeded => _updateNotifier.isActionNeeded;

  set isUpdateNeeded(bool update) {
    _updateNotifier.isActionNeeded = update;
  }

  @override
  void updateTree(double dt) {
    if (isUpdateNeeded) {
      super.updateTree(dt);
      _updateNotifier.isActionNeeded = false;
    }
  }
}
