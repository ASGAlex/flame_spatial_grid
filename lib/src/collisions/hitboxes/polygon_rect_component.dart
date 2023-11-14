import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/geometry.dart';
import 'package:meta/meta.dart';

class PolygonRectComponent extends ShapeComponent implements PolygonComponent {
  List<Vector2> _vertices;

  @override
  UnmodifiableListView<Vector2> get vertices => UnmodifiableListView(_vertices);

  // These lists are used to minimize the amount of objects that are created,
  // and only change the contained object if the corresponding `ValueCache` is
  // deemed outdated.
  late final List<Vector2> _globalVertices;
  late final List<LineSegment> _lineSegments;

  Rect _rect = Rect.zero;

  @override
  bool shrinkToBounds;

  @override
  bool manuallyPositioned;

  final _cachedGlobalVertices = ValueCache<List<Vector2>>();

  /// With this constructor you create your [PolygonComponent] from positions in
  /// anywhere in the 2d-space. It will automatically calculate the [size] of
  /// the Polygon (the bounding box) if no size it given.
  /// NOTE: Always define your polygon in a counter-clockwise fashion (in the
  /// screen coordinate system).
  PolygonRectComponent(
    this._vertices, {
    super.position,
    super.size,
    super.scale,
    super.angle,
    super.anchor,
    super.children,
    super.priority,
    super.paint,
    super.paintLayers,
    super.key,
    bool? shrinkToBounds,
  })  : assert(
          _vertices.length == 4,
          'Number of vertices are too few to create a rect polygon',
        ),
        shrinkToBounds = shrinkToBounds ?? size == null,
        manuallyPositioned = position != null {
    refreshVertices(newVertices: _vertices);

    final verticesLength = _vertices.length;
    _globalVertices = List.generate(
      verticesLength,
      (_) => Vector2.zero(),
      growable: false,
    );
    _lineSegments = List.generate(
      verticesLength,
      (_) => LineSegment.zero(),
      growable: false,
    );
  }

  /// With this constructor you define the [PolygonComponent] in relation to the
  /// [parentSize] of the shape.
  ///
  /// Example: `[[1.0, 0.0], [0.0, -1.0], [-1.0, 0.0], [0.0, 1.0]]`
  /// This will form a diamond shape within the bounding size box.
  /// NOTE: Always define your shape in a counter-clockwise fashion (in the
  /// screen coordinate system).
  PolygonRectComponent.relative(
    List<Vector2> relation, {
    required Vector2 parentSize,
    Vector2? position,
    Vector2? scale,
    double? angle,
    Anchor? anchor,
    int? priority,
    Paint? paint,
    List<Paint>? paintLayers,
    bool? shrinkToBounds,
    ComponentKey? key,
  }) : this(
          normalsToVertices(relation, parentSize),
          position: position,
          angle: angle,
          anchor: anchor,
          scale: scale,
          priority: priority,
          paint: paint,
          paintLayers: paintLayers,
          shrinkToBounds: shrinkToBounds,
          key: key,
        );

  @internal
  static List<Vector2> normalsToVertices(
    List<Vector2> normals,
    Vector2 size,
  ) {
    final halfSize = size / 2;
    return normals
        .map(
          (v) => v.clone()
            ..multiply(halfSize)
            ..add(halfSize),
        )
        .toList(growable: false);
  }

  // Used to not create new Vector2 objects when calculating the top left of the
  // bounds of the polygon.
  final _topLeft = Vector2.zero();

  @override
  @protected
  void refreshVertices({
    required List<Vector2> newVertices,
    bool? shrinkToBoundsOverride,
  }) {
    assert(
      newVertices.length == 4 && _vertices.length == 4,
      'A rect polygon must have 4 vertices',
    );
    _rect = Rect.fromLTRB(
      newVertices[0].x,
      newVertices[0].y,
      newVertices[2].x,
      newVertices[2].y,
    );
    _topLeft.setFrom(newVertices[0]);
    _vertices = newVertices;

    if (shrinkToBoundsOverride ?? shrinkToBounds) {
      size.setValues(_rect.width, _rect.height);
      if (!manuallyPositioned) {
        position = Anchor.topLeft.toOtherAnchorPosition(_topLeft, anchor, size);
      }
    }
  }

  /// gives back the shape vectors multiplied by the size and scale
  @override
  List<Vector2> globalVertices() {
    final scale = absoluteScale;
    final angle = absoluteAngle;
    final position = absoluteTopLeftPosition;
    if (!_cachedGlobalVertices.isCacheValid<dynamic>(<dynamic>[
      position,
      size,
      scale,
      angle,
    ])) {
      vertices.forEachIndexed((i, vertex) {
        _globalVertices[i]
          ..setFrom(vertex)
          ..sub(_topLeft)
          ..multiply(scale)
          ..add(position)
          ..rotate(angle, center: position);
      });
      if (scale.y.isNegative || scale.x.isNegative) {
        // Since the list will be clockwise we have to reverse it for it to
        // become counterclockwise.
        _reverseList(_globalVertices);
      }
      _cachedGlobalVertices.updateCache<dynamic>(
        _globalVertices,
        <dynamic>[position.clone(), size.clone(), scale.clone(), angle],
      );
    }
    return _cachedGlobalVertices.value!;
  }

  @override
  void render(Canvas canvas) {
    if (renderShape) {
      if (hasPaintLayers) {
        for (final paint in paintLayers) {
          canvas.drawRect(_rect, paint);
        }
      } else {
        canvas.drawRect(_rect, paint);
      }
    }
  }

  @override
  void renderDebugMode(Canvas canvas) {
    super.renderDebugMode(canvas);
    canvas.drawRect(_rect, paint);
  }

  /// Checks whether the polygon contains the [point].
  /// Note: The polygon needs to be convex for this to work.
  @override
  bool containsPoint(Vector2 point) {
    // If the size is 0 then it can't contain any points
    if (size.x == 0 || size.y == 0) {
      return false;
    }

    final vertices = globalVertices();
    for (var i = 0; i < vertices.length; i++) {
      final edge = getEdge(i, vertices: vertices);
      final isOutside = (edge.to.x - edge.from.x) * (point.y - edge.from.y) -
              (point.x - edge.from.x) * (edge.to.y - edge.from.y) >
          0;
      if (isOutside) {
        // Point is outside of convex polygon
        return false;
      }
    }
    return true;
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    if (size.x == 0 || size.y == 0) {
      return false;
    }
    for (var i = 0; i < _vertices.length; i++) {
      final edge = getEdge(i, vertices: vertices);
      final isOutside = (edge.to.x - edge.from.x) *
                  (point.y - edge.from.y + _topLeft.y) -
              (point.x - edge.from.x + _topLeft.x) * (edge.to.y - edge.from.y) >
          0;
      if (isOutside) {
        return false;
      }
    }
    return true;
  }

  /// Return all vertices as [LineSegment]s that intersect [rect], if [rect]
  /// is null return all vertices as [LineSegment]s.
  @override
  List<LineSegment> possibleIntersectionVertices(Rect? rect) {
    final rectIntersections = <LineSegment>[];
    if ((rect?.width == 0 || false) ||
        (rect?.height == 0 || false) ||
        width == 0 ||
        height == 0) {
      return rectIntersections;
    }
    final vertices = globalVertices();
    for (var i = 0; i < vertices.length; i++) {
      final edge = getEdge(i, vertices: vertices);
      if (rect?.intersectsSegment(edge.from, edge.to) ?? true) {
        rectIntersections.add(edge);
      }
    }
    return rectIntersections;
  }

  @override
  LineSegment getEdge(int i, {required List<Vector2> vertices}) {
    _lineSegments[i].from.setFrom(getVertex(i, vertices: vertices));
    _lineSegments[i].to.setFrom(getVertex(i + 1, vertices: vertices));
    return _lineSegments[i];
  }

  @override
  Vector2 getVertex(int i, {List<Vector2>? vertices}) {
    vertices ??= globalVertices();
    return vertices[i % vertices.length];
  }

  void _reverseList(List<Object> list) {
    for (var i = 0; i < list.length / 2; i++) {
      final temp = list[i];
      list[i] = list[list.length - 1 - i];
      list[list.length - 1 - i] = temp;
    }
  }
}
