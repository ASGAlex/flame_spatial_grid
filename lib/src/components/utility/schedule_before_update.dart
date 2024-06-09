import 'package:flame/components.dart';
import 'package:meta/meta.dart';

mixin ScheduleBeforeUpdateMixin on Component {
  bool _actionScheduled = false;
  bool _permanent = false;

  List<ScheduleBeforeUpdateMixin> get scheduleBeforeList;

  List<ScheduleBeforeUpdateMixin> get scheduleBeforeListPermanent;

  void scheduleBeforeLogicAction({bool permanent = false}) {
    if (!_actionScheduled) {
      if (permanent) {
        _permanent = true;
        scheduleBeforeListPermanent.add(this);
      } else {
        try {
          scheduleBeforeList.add(this);
          _actionScheduled = true;
        } catch (_) {}
      }
    }
  }

  @internal
  void runBeforeLogicAction(double dt) {
    if (!_permanent) {
      _actionScheduled = false;
    }
    onBeforeLogic(dt);
  }

  void onBeforeLogic(double dt) {}

  @override
  void onRemove() {
    if (_permanent) {
      scheduleBeforeListPermanent.remove(this);
      _actionScheduled = false;
    }
    super.onRemove();
  }
}
