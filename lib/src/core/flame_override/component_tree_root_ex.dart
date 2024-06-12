import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/src/components/core/component_tree_root.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:meta/meta.dart';

/// **ComponentTreeRoot** is a component that can be used as a root node of a
/// component tree.
///
/// This class is just a regular [Component], with some additional
/// functionality, namely: it contains global lifecycle events for the component
/// tree.
class ComponentTreeRootEx extends ComponentTreeRoot {
  ComponentTreeRootEx({
    super.children,
    super.key,
  });


  @override
  @internal
  void enqueueAdd(Component child, Component parent) {
    if(child is HasGridSupport && this is FlameGame) {
      child.game = this as FlameGame;
    }
    super.enqueueAdd(child, parent);
  }
}