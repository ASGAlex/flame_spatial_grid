// automatically generated by the FlatBuffers compiler, do not modify
// ignore_for_file: unused_import, unused_field, unused_element, unused_local_variable

library optimizer;

import 'dart:typed_data' show Uint8List;

import 'package:flame_spatial_grid/src/collisions/optimizer/isolate/flat_buffers/flat_buffers_optimizer.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;

class OverlappingSearchRequest {
  OverlappingSearchRequest._(this._bc, this._bcOffset);
  factory OverlappingSearchRequest(List<int> bytes) {
    final rootRef = fb.BufferContext.fromBytes(bytes);
    return reader.read(rootRef, 0);
  }

  static const fb.Reader<OverlappingSearchRequest> reader =
      _OverlappingSearchRequestReader();

  final fb.BufferContext _bc;
  final int _bcOffset;

  List<BoundingHitbox>? get hitboxes =>
      const fb.ListReader<BoundingHitbox>(BoundingHitbox.reader)
          .vTableGetNullable(_bc, _bcOffset, 4);
  int get maximumItemsInGroup =>
      const fb.Int32Reader().vTableGet(_bc, _bcOffset, 6, 0);

  @override
  String toString() {
    return 'OverlappingSearchRequest{hitboxes: $hitboxes, maximumItemsInGroup: $maximumItemsInGroup}';
  }

  OverlappingSearchRequestT unpack() => OverlappingSearchRequestT(
      hitboxes: hitboxes?.map((e) => e.unpack()).toList(),
      maximumItemsInGroup: maximumItemsInGroup);

  static int pack(fb.Builder fbBuilder, OverlappingSearchRequestT? object) {
    if (object == null) return 0;
    return object.pack(fbBuilder);
  }
}

class OverlappingSearchRequestT implements fb.Packable {
  List<BoundingHitboxT>? hitboxes;
  int maximumItemsInGroup;

  OverlappingSearchRequestT({this.hitboxes, this.maximumItemsInGroup = 0});

  @override
  int pack(fb.Builder fbBuilder) {
    final int? hitboxesOffset = hitboxes == null
        ? null
        : fbBuilder.writeList(hitboxes!.map((b) => b.pack(fbBuilder)).toList());
    fbBuilder.startTable(2);
    fbBuilder.addOffset(0, hitboxesOffset);
    fbBuilder.addInt32(1, maximumItemsInGroup);
    return fbBuilder.endTable();
  }

  @override
  String toString() {
    return 'OverlappingSearchRequestT{hitboxes: $hitboxes, maximumItemsInGroup: $maximumItemsInGroup}';
  }
}

class _OverlappingSearchRequestReader
    extends fb.TableReader<OverlappingSearchRequest> {
  const _OverlappingSearchRequestReader();

  @override
  OverlappingSearchRequest createObject(fb.BufferContext bc, int offset) =>
      OverlappingSearchRequest._(bc, offset);
}

class OverlappingSearchRequestBuilder {
  OverlappingSearchRequestBuilder(this.fbBuilder);

  final fb.Builder fbBuilder;

  void begin() {
    fbBuilder.startTable(2);
  }

  int addHitboxesOffset(int? offset) {
    fbBuilder.addOffset(0, offset);
    return fbBuilder.offset;
  }

  int addMaximumItemsInGroup(int? maximumItemsInGroup) {
    fbBuilder.addInt32(1, maximumItemsInGroup);
    return fbBuilder.offset;
  }

  int finish() {
    return fbBuilder.endTable();
  }
}

class OverlappingSearchRequestObjectBuilder extends fb.ObjectBuilder {
  final List<BoundingHitboxObjectBuilder>? _hitboxes;
  final int? _maximumItemsInGroup;

  OverlappingSearchRequestObjectBuilder({
    List<BoundingHitboxObjectBuilder>? hitboxes,
    int? maximumItemsInGroup,
  })  : _hitboxes = hitboxes,
        _maximumItemsInGroup = maximumItemsInGroup;

  /// Finish building, and store into the [fbBuilder].
  @override
  int finish(fb.Builder fbBuilder) {
    final int? hitboxesOffset = _hitboxes == null
        ? null
        : fbBuilder.writeList(
            _hitboxes!.map((b) => b.getOrCreateOffset(fbBuilder)).toList());
    fbBuilder.startTable(2);
    fbBuilder.addOffset(0, hitboxesOffset);
    fbBuilder.addInt32(1, _maximumItemsInGroup);
    return fbBuilder.endTable();
  }

  /// Convenience method to serialize to byte list.
  @override
  Uint8List toBytes([String? fileIdentifier]) {
    final fbBuilder = fb.Builder(deduplicateTables: false);
    fbBuilder.finish(finish(fbBuilder), fileIdentifier);
    return fbBuilder.buffer;
  }
}
