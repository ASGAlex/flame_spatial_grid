import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

class LoadingProgressManager<M> {
  LoadingProgressManager(
    this.type,
    this.game, {
    int? min,
    this.max = 100,
  }) : min = min ?? LoadingProgressManager.lastProgressValue;

  static int lastProgressValue = 0;

  final String type;
  HasSpatialGridFramework game;

  final int min;
  final int max;

  int _progress = 0;

  int get progress => _progress;

  void setProgress(int value, [M? message]) {
    final converted = _convertValueForSubProcess(value);
    _progress = converted;
    lastProgressValue = converted;
    game.onLoadingProgress(LoadingProgressMessage<M>(progress, type, message));
  }

  void incrementProgress(int value, [M? message]) {
    final converted = _convertValueForSubProcess(value);
    final currentProgress = LoadingProgressManager.lastProgressValue;
    setProgress(currentProgress + converted, message);
  }

  int _convertValueForSubProcess(int value) {
    if (min == 0 && max == 100) {
      return value;
    }

    if (value == 0) {
      return min;
    }

    final diff = max - min;
    return min + (value * diff ~/ 100);
  }

  void resetProgress() {
    _progress = 0;
    lastProgressValue = 0;
  }
}

@immutable
class LoadingProgressMessage<M> {
  const LoadingProgressMessage(this.progress, this.type, this.data);

  final int progress;
  final String type;
  final M? data;
}
