import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

mixin ClusterizedComponent on PositionComponent {
  bool isVisible = true;

  bool _isSuspended = false;

  bool get isSuspended => _isSuspended;

  set isSuspended(bool suspend) {
    if (_isSuspended != suspend) {
      if (suspend) {
        onSuspend();
      } else {
        onResume(_dtElapsedWhileSuspended);
        _dtElapsedWhileSuspended = 0;
      }
    }
    _isSuspended = suspend;
  }

  double _dtElapsedWhileSuspended = 0;

  @override
  void updateTree(double dt) {
    if (isSuspended) {
      _dtElapsedWhileSuspended += dt;
      updateSuspendedTree(_dtElapsedWhileSuspended);
    } else {
      super.updateTree(dt);
    }
  }

  /// Called instead of [updateTree] when component is suspended.
  /// [dtElapsedWhileSuspended] accumulates all [dt] values since
  /// component suspension
  void updateSuspendedTree(double dtElapsedWhileSuspended) {}

  /// Called when component state changes to "suspended". You should stop
  /// all undesired component's movements (for example) here
  void onSuspend() {}

  /// Called when component state changes from "suspended" to active.
  /// [dtElapsedWhileSuspended] accumulates all [dt] values since
  /// component suspension. Useful to calculate next animation step as if
  /// the component was never suspended.
  void onResume(double dtElapsedWhileSuspended) {}

  @override
  void renderTree(Canvas canvas) {
    if (isVisible) {
      super.renderTree(canvas);
    }
  }
}
