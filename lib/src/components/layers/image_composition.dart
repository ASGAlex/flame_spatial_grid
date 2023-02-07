import 'dart:ui';

import 'package:flame/extensions.dart';

/// Clone of the [ImageComposition] because it is not designed fine enough to
/// accept inheritance
///
class ImageCompositionExt {
  ImageCompositionExt({
    this.defaultBlendMode = BlendMode.srcOver,
    this.defaultAntiAlias = false,
  });

  final List<_Fragment> _composes = [];

  final BlendMode defaultBlendMode;

  final bool defaultAntiAlias;

  void add(
    Image image,
    Vector2 position, {
    Rect? source,
    double angle = 0,
    Vector2? anchor,
    bool? isAntiAlias,
    BlendMode? blendMode,
  }) {
    final imageRect = image.getBoundingRect();
    source ??= imageRect;
    anchor ??= source.toVector2() / 2;
    blendMode ??= defaultBlendMode;
    isAntiAlias ??= defaultAntiAlias;

    assert(
      imageRect.topLeft <= source.topLeft &&
          imageRect.bottomRight >= source.bottomRight,
      'Source rect should fit within the image',
    );

    _composes.add(
      _Fragment(
        image,
        position,
        source,
        angle,
        anchor,
        isAntiAlias,
        blendMode,
      ),
    );
  }

  void clear() => _composes.clear();

  /// Compose all the images into a single composition.
  Image compose() {
    // Rect used to determine how big the output image will be.
    var output = Rect.zero;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    for (final compose in _composes) {
      final image = compose.image;
      final position = compose.position;
      final source = compose.source;
      final rotation = compose.angle;
      final anchor = compose.anchor;
      final isAntiAlias = compose.isAntiAlias;
      final blendMode = compose.blendMode;
      final destination = Rect.fromLTWH(0, 0, source.width, source.height);
      final realDest = destination.translate(position.x, position.y);

      canvas
        ..save()
        ..translateVector(position)
        ..translateVector(anchor)
        ..rotate(rotation)
        ..translateVector(-anchor)
        ..drawImageRect(
          image,
          source,
          destination,
          Paint()
            ..blendMode = blendMode
            ..isAntiAlias = isAntiAlias,
        )
        ..restore();

      // Expand the output so it can be used later on when the output image gets
      // created.
      output = output.expandToInclude(realDest);
    }

    /// THIS IS THE ONLY DIFFERENCE FROM ORIGINAL CLASS
    final picture = recorder.endRecording();
    final image =
        picture.toImageSync(output.width.toInt(), output.height.toInt());
    picture.dispose();
    return image;
  }
}

class _Fragment {
  _Fragment(
    this.image,
    this.position,
    this.source,
    this.angle,
    this.anchor,
    this.isAntiAlias,
    this.blendMode,
  );

  /// The image that will be composed.
  final Image image;

  /// The position where the [image] will be composed.
  final Vector2 position;

  /// The source on the [image] that will be composed.
  final Rect source;

  /// The angle (in radians) used to rotate the [image] around it's [anchor].
  final double angle;

  /// The point around which the [image] will be rotated
  /// (defaults to the centre of the [source]).
  final Vector2 anchor;

  final bool isAntiAlias;

  /// The [BlendMode] that will be used when composing the [image].
  final BlendMode blendMode;
}
