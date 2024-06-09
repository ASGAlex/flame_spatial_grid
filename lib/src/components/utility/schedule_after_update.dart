import 'package:flame/components.dart';
import 'package:meta/meta.dart';

mixin ScheduleAfterUpdateMixin on Component {
  bool _actionScheduled = false;
  bool _permanent = false;

  List<ScheduleAfterUpdateMixin> get scheduleAfterList;

  List<ScheduleAfterUpdateMixin> get scheduleAfterListPermanent;

  void scheduleAfterLogicAction({bool permanent = false}) {
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

  @internal
  void runAfterLogicAction(double dt) {
    if (!_permanent) {
      _actionScheduled = false;
    }
    onAfterLogic(dt);
  }

  void onAfterLogic(double dt) {}

  @override
  void onRemove() {
    if (_permanent) {
      scheduleAfterListPermanent.remove(this);
      _actionScheduled = false;
    }
    super.onRemove();
  }
}
