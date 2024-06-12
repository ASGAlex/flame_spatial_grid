import 'package:flame_spatial_grid/src/components/utility/scheduler/scheduler.dart';

typedef ScheduledActionFunction = void Function(
  double dt,
  ScheduledActionType type,
  bool permanent,
);

class ScheduledActionProvider {
  ScheduledActionProvider({
    required this.scheduler,
    required this.actionFunction,
  });

  final ActionScheduler scheduler;
  final ScheduledActionFunction actionFunction;

  final _scheduled = <ScheduledActionType, bool>{};

  void scheduleAction(ScheduledActionType type, bool permanent) {
    if (!isScheduled(type, permanent)) {
      scheduler.add(this, type, permanent);
      _scheduled[type] = permanent;
    }
  }

  void removeAction(ScheduledActionType type, bool permanent) {
    if (isScheduled(type, permanent)) {
      scheduler.remove(this, type, permanent);
      _scheduled.remove(type);
    }
  }

  bool isScheduled(ScheduledActionType type, bool permanent) {
    final isPermanentSchedule = _scheduled[type];
    if (isPermanentSchedule == null) {
      return false;
    }
    return permanent ? isPermanentSchedule : !isPermanentSchedule;
  }

  void onScheduledAction(
    double dt,
    ScheduledActionType type,
    bool permanent,
  ) {
    actionFunction(dt, type, permanent);
  }

  void onDisposeActionProvider() {
    for (final type in _scheduled.keys) {
      scheduler.remove(this, type, _scheduled[type]!);
    }
    _scheduled.clear();
  }
}
