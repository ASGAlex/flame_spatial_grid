import 'package:flame_spatial_grid/src/components/utility/scheduler/action_provider.dart';
import 'package:flame_spatial_grid/src/components/utility/scheduler/scheduler.dart';

mixin WithActionProviderMixin {
  ScheduledActionProvider? _scheduledActionProvider;

  ScheduledActionProvider get scheduledActionProvider =>
      _scheduledActionProvider!;

  void initActionProvider(ScheduledActionProvider provider) {
    if (_scheduledActionProvider != null) {
      _scheduledActionProvider!.onDisposeActionProvider();
    }
    _scheduledActionProvider = provider;
  }

  void onScheduledAction(
    double dt,
    ScheduledActionType type,
    bool permanent,
  );
}
