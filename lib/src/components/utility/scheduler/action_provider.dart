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

  bool runningAction = false;

  void scheduleFunction(
    ScheduledActionType type,
    ScheduledActionFunction actionFunctionCallback,
  ) {
    final actionProvider = ScheduledActionProvider(
      scheduler: scheduler,
      actionFunction: actionFunctionCallback,
    );
    actionProvider.scheduleAction(type, false);
  }

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
    return _scheduled.containsKey(type);
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
