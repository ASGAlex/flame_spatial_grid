import 'package:flame_spatial_grid/src/components/utility/scheduler/action_provider.dart';
import 'package:flame_spatial_grid/src/components/utility/scheduler/scheduler.dart';

mixin WithActionProviderMixin {
  late final ScheduledActionProvider scheduledActionProvider;

  void onScheduledAction(
    double dt,
    ScheduledActionType type,
    bool permanent,
  );
}
