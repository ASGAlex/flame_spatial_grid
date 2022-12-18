import 'package:flame/extensions.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flutter/foundation.dart';

mixin RepaintOnDemand on HasGridSupport {
  final _repaintNotifier = _ActionNotifier();

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

mixin UpdateOnDemand on HasGridSupport {
  final _updateNotifier = _ActionNotifier();

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

class _ActionNotifier extends ChangeNotifier {
  bool _isActionNeeded = true;

  set isActionNeeded(bool doAction) {
    _isActionNeeded = doAction;
    if (doAction) {
      notifyListeners();
    }
  }

  bool get isActionNeeded => _isActionNeeded;
}
