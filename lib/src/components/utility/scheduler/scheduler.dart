import 'package:flame_spatial_grid/src/components/utility/scheduler/action_provider.dart';

enum ScheduledActionType {
  afterUpdate,
  beforeUpdate,
  afterLogic,
  beforeLogic,
}

class ActionScheduler {
  final _scheduledAfterLogic = <ScheduledActionProvider>[];
  final _scheduledAfterLogicPermanent = <ScheduledActionProvider>[];

  final _scheduledBeforeLogic = <ScheduledActionProvider>[];
  final _scheduledBeforeLogicPermanent = <ScheduledActionProvider>[];

  final _scheduledAfterUpdate = <ScheduledActionProvider>[];
  final _scheduledAfterUpdatePermanent = <ScheduledActionProvider>[];

  final _scheduledBeforeUpdate = <ScheduledActionProvider>[];
  final _scheduledBeforeUpdatePermanent = <ScheduledActionProvider>[];

  void add(
    ScheduledActionProvider provider,
    ScheduledActionType type,
    bool permanent,
  ) {
    switch (type) {
      case ScheduledActionType.afterUpdate:
        if (permanent) {
          _scheduledAfterUpdatePermanent.add(provider);
        } else {
          _scheduledAfterUpdate.add(provider);
        }
        break;
      case ScheduledActionType.beforeUpdate:
        if (permanent) {
          _scheduledBeforeUpdatePermanent.add(provider);
        } else {
          _scheduledBeforeUpdate.add(provider);
        }
        break;
      case ScheduledActionType.afterLogic:
        if (permanent) {
          _scheduledAfterLogicPermanent.add(provider);
        } else {
          _scheduledAfterLogic.add(provider);
        }
        break;
      case ScheduledActionType.beforeLogic:
        if (permanent) {
          _scheduledBeforeLogicPermanent.add(provider);
        } else {
          _scheduledBeforeLogic.add(provider);
        }
        break;
    }
  }

  void remove(
    ScheduledActionProvider provider,
    ScheduledActionType type,
    bool permanent,
  ) {
    final list = _getStorageByType(type, permanent);
    list.remove(provider);
  }

  void runActions(double dt, ScheduledActionType type) {
    final list = _getStorageByType(type, false);
    for (final item in list) {
      item.runningAction = true;
      item.onScheduledAction(dt, type, false);
      item.runningAction = false;
    }
    list.clear();

    final listPermanent = _getStorageByType(type, true);
    for (final item in listPermanent) {
      item.runningAction = true;
      item.onScheduledAction(dt, type, true);
      item.runningAction = false;
    }
  }

  List<ScheduledActionProvider> _getStorageByType(
    ScheduledActionType type,
    bool permanent,
  ) {
    switch (type) {
      case ScheduledActionType.afterUpdate:
        return permanent
            ? _scheduledAfterUpdatePermanent
            : _scheduledAfterUpdate;
      case ScheduledActionType.beforeUpdate:
        return permanent
            ? _scheduledBeforeUpdatePermanent
            : _scheduledBeforeUpdate;
      case ScheduledActionType.afterLogic:
        return permanent ? _scheduledAfterLogicPermanent : _scheduledAfterLogic;
      case ScheduledActionType.beforeLogic:
        return permanent
            ? _scheduledBeforeLogicPermanent
            : _scheduledBeforeLogic;
    }
  }
}
