import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

mixin ScheduleAfterUpdateMixin on Component {
  bool _actionScheduled = false;
  bool _permanent = false;

  List<ScheduleAfterUpdateMixin> get scheduleAfterList;

  List<ScheduleAfterUpdateMixin> get scheduleAfterListPermanent;

  void scheduleAfterUpdateAction({bool permanent = false}) {
    if (!_actionScheduled) {
      if (permanent) {
        _permanent = true;
        scheduleAfterListPermanent.add(this);
      } else {
        try {
          scheduleAfterList.add(this);
          _actionScheduled = true;
        } catch (_) {}
      }
    }
  }

  @protected
  void runAfterUpdateAction(double dt) {
    if (!_permanent) {
      _actionScheduled = false;
    }
    onAfterUpdate(dt);
  }

  void onAfterUpdate(double dt) {}

  @override
  void onRemove() {
    if (_permanent) {
      scheduleAfterListPermanent.remove(this);
      _actionScheduled = false;
    }
    super.onRemove();
  }
}
