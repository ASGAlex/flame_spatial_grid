import 'package:flame/extensions.dart';
import 'package:flame_clusterizer/flame_clusterizer.dart';
import 'package:flutter/foundation.dart';

mixin RepaintOnDemand on ClusterizedComponent {
  final _repaintNotifier = _ActionNotifier();

  ChangeNotifier get repaintNotifier => _repaintNotifier;

  bool get isRepaintNeeded => _repaintNotifier.isActionNeeded;

  set isRepaintNeeded(bool repaint) {
    _repaintNotifier.isActionNeeded = repaint;
  }

  @override
  Future<void>? onLoad() {
    visibilityNotifier.addListener(_requestRepaint);
    return super.onLoad();
  }

  @override
  void onRemove() {
    visibilityNotifier.removeListener(_requestRepaint);
    super.onRemove();
  }

  void _requestRepaint() {
    isRepaintNeeded = true;
  }

  @override
  void renderTree(Canvas canvas) {
    if (isRepaintNeeded) {
      super.renderTree(canvas);
      _repaintNotifier.isActionNeeded = false;
    }
  }
}

mixin UpdateOnDemand on ClusterizedComponent {
  final _updateNotifier = _ActionNotifier();

  ChangeNotifier get updateNotifier => _updateNotifier;

  bool get isUpdateNeeded => _updateNotifier.isActionNeeded;

  set isUpdateNeeded(bool update) {
    _updateNotifier.isActionNeeded = update;
  }

  bool updateOnVisibilityOrSuspendChange = true;

  @override
  Future<void>? onLoad() {
    suspendNotifier.addListener(_requestUpdate);
    visibilityNotifier.addListener(_requestUpdate);
    return super.onLoad();
  }

  @override
  void onRemove() {
    suspendNotifier.removeListener(_requestUpdate);
    visibilityNotifier.removeListener(_requestUpdate);
    super.onRemove();
  }

  void _requestUpdate() {
    if (updateOnVisibilityOrSuspendChange) {
      isUpdateNeeded = true;
    }
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
