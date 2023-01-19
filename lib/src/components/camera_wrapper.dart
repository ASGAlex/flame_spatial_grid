import 'package:flame/components.dart';
import 'package:flame/experimental.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';

/// Camera wrapper allows to attach [CameraComponent] as a "trackedComponent"
/// in [HasSpatialGridFramework] game. Every movement of the camera will be
/// handled by spatial grid af if it would be simple [PositionComponent].
///
/// There is no need to add the component manually into a game. Just
/// specify it as a parameter "trackedComponent" for
/// [HasSpatialGridFramework.initializeSpatialGrid] function
///
/// With this wrapper there is no need to make manual calls of
/// [HasSpatialGridFramework.onAfterZoom] to make recalculation of visible
/// grid's cells.
///
/// Please notice, that this wrapper only works with Flame's "experimental"
/// camera API. Old camera does not supported, you need to control everything
/// manually in cause you use old API.
class SpatialGridCameraWrapper extends PositionComponent
    with HasGridSupport, HasGameReference<HasSpatialGridFramework> {
  SpatialGridCameraWrapper(this.cameraComponent) {
    // ignore: invalid_use_of_internal_member
    cameraComponent.viewfinder.transform.offset.addListener(onPositionChange);
    // ignore: invalid_use_of_internal_member
    cameraComponent.viewfinder.transform.scale.addListener(onAfterZoom);
  }

  final CameraComponent cameraComponent;

  /// Camera's viewfinder tracking.
  void onPositionChange() {
    position.setFrom(cameraComponent.viewfinder.position);
  }

  /// Camera's viewfinder zoom tracking
  /// Reimplement if you need to do additional actions on zoom change
  void onAfterZoom() {
    try {
      game.onAfterZoom();
    } catch (e) {}
  }
}
