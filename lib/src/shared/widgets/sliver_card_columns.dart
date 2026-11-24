import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Cards in columns, each one in the column that is shortest so far (Keep's
/// grid), building only the cards around what is on screen.
///
/// Where a card goes depends on the height of every card before it. This
/// sliver remembers each card's height by its id ([itemIds]) once it has
/// been laid out, and works every position out again from those heights on
/// each layout. So the grid keeps its place whatever happens to the cards
/// it isn't showing: scrolled past entirely with more slivers below, cards
/// added, removed or moved above the screen, or the whole list replaced.
/// A card that hasn't been laid out yet counts as an average one until it
/// is.
class SliverCardColumns extends SliverMultiBoxAdaptorWidget {
  SliverCardColumns({
    super.key,
    required this.itemIds,
    required IndexedWidgetBuilder itemBuilder,
    required this.crossAxisCount,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
  }) : assert(crossAxisCount > 0),
       super(delegate: SliverChildBuilderDelegate(itemBuilder, childCount: itemIds.length));

  /// One id per card, in order. A card keeps its remembered height for as
  /// long as its id is in the list.
  final List<Object> itemIds;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  @override
  RenderSliverCardColumns createRenderObject(BuildContext context) => RenderSliverCardColumns(
    childManager: context as SliverMultiBoxAdaptorElement,
    itemIds: itemIds,
    crossAxisCount: crossAxisCount,
    mainAxisSpacing: mainAxisSpacing,
    crossAxisSpacing: crossAxisSpacing,
  );

  @override
  void updateRenderObject(BuildContext context, RenderSliverCardColumns renderObject) {
    renderObject
      ..itemIds = itemIds
      ..crossAxisCount = crossAxisCount
      ..mainAxisSpacing = mainAxisSpacing
      ..crossAxisSpacing = crossAxisSpacing;
  }
}

class RenderSliverCardColumns extends RenderSliverMultiBoxAdaptor {
  RenderSliverCardColumns({
    required super.childManager,
    required this._itemIds,
    required this._crossAxisCount,
    required this._mainAxisSpacing,
    required this._crossAxisSpacing,
  });

  /// Scrolling back by more cards than this starts from the card needed
  /// instead of putting back every card in between.
  static const _maxLeadingInserts = 32;

  List<Object> get itemIds => _itemIds;
  List<Object> _itemIds;
  set itemIds(List<Object> value) {
    if (listEquals(_itemIds, value)) return;
    _itemIds = value;
    _aligned = false;
    markNeedsLayout();
  }

  int get crossAxisCount => _crossAxisCount;
  int _crossAxisCount;
  set crossAxisCount(int value) {
    if (_crossAxisCount == value) return;
    _crossAxisCount = value;
    markNeedsLayout();
  }

  double get mainAxisSpacing => _mainAxisSpacing;
  double _mainAxisSpacing;
  set mainAxisSpacing(double value) {
    if (_mainAxisSpacing == value) return;
    _mainAxisSpacing = value;
    markNeedsLayout();
  }

  double get crossAxisSpacing => _crossAxisSpacing;
  double _crossAxisSpacing;
  set crossAxisSpacing(double value) {
    if (_crossAxisSpacing == value) return;
    _crossAxisSpacing = value;
    markNeedsLayout();
  }

  /// Heights of the cards laid out so far at [_width], by id.
  Map<Object, double> _measured = {};

  /// [_measured] in the order of [_itemIds]; NaN for a card not laid out
  /// yet. Only valid while [_aligned].
  Float64List _extents = Float64List(0);
  bool _aligned = false;

  /// The card width [_measured] holds for.
  double? _width;

  /// What a card not laid out yet counts as: the average of those that
  /// were. Changes only when the cards do, so positions don't drift from
  /// one frame to the next.
  double _guess = 120;

  void _align() {
    final count = _itemIds.length;
    final extents = Float64List(count);
    final kept = <Object, double>{};
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      final extent = _measured[_itemIds[i]];
      if (extent == null) {
        extents[i] = double.nan;
      } else {
        extents[i] = extent;
        kept[_itemIds[i]] = extent;
        sum += extent;
      }
    }
    if (kept.isNotEmpty) _guess = sum / kept.length;
    _extents = extents;
    _measured = kept; // Cards that are gone are forgotten.
    _aligned = true;
  }

  double _extentAt(int index) {
    final extent = _extents[index];
    return extent.isNaN ? _guess : extent;
  }

  /// The first of the shortest columns.
  static int _shortest(Float64List ends) {
    var column = 0;
    for (var i = 1; i < ends.length; i++) {
      if (ends[i] < ends[column]) column = i;
    }
    return column;
  }

  double _total(Float64List ends) {
    var end = 0.0;
    for (final e in ends) {
      end = math.max(end, e);
    }
    return math.max(0, end - mainAxisSpacing);
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverGridParentData) child.parentData = SliverGridParentData();
  }

  @override
  double childCrossAxisPosition(RenderBox child) =>
      (child.parentData! as SliverGridParentData).crossAxisOffset ?? 0;

  void _dropAllChildren() {
    if (firstChild != null) collectGarbage(childCount, 0);
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    childManager.didStartLayout();
    childManager.setDidUnderflow(false);

    final columns = crossAxisCount;
    final stride = (constraints.crossAxisExtent + crossAxisSpacing) / columns;
    final width = math.max(0.0, stride - crossAxisSpacing);
    final childConstraints = constraints.asBoxConstraints(crossAxisExtent: width);
    if (width != _width) {
      // Another width, other heights.
      _measured.clear();
      _width = width;
      _aligned = false;
    }
    if (!_aligned) _align();

    final count = _itemIds.length;
    final windowStart = constraints.scrollOffset + constraints.cacheOrigin;
    final windowEnd = windowStart + constraints.remainingCacheExtent;
    final showsNothing = constraints.remainingCacheExtent <= 0;
    final mirrored = axisDirectionIsReversed(constraints.crossAxisDirection);

    // Where each column ends so far, which is where its next card starts.
    final ends = Float64List(columns);

    // 1. Go past the cards that end before the window, by their heights
    // alone.
    var index = 0;
    while (index < count) {
      final column = _shortest(ends);
      final extent = _extentAt(index);
      if (!showsNothing && ends[column] + extent >= windowStart) break;
      ends[column] += extent + mainAxisSpacing;
      index++;
    }
    final first = index;
    if (first == count) {
      // Nothing of this grid is near the screen.
      _dropAllChildren();
      final extent = _total(ends);
      geometry = SliverGeometry(scrollExtent: extent, maxPaintExtent: extent);
      childManager.didFinishLayout();
      return;
    }

    // 2. Line the children up with [first]: `child` is the one at [first]
    // if there is one, `before` the one just ahead of it.
    var leadingGarbage = 0;
    RenderBox? child = firstChild;
    RenderBox? before;
    if (child != null) {
      final firstIndex = indexOf(child);
      if (firstIndex > first) {
        // Scrolled back: put the cards ahead of the first child back.
        if (firstIndex - first > _maxLeadingInserts) {
          child = null;
        } else {
          while (child != null && indexOf(child) > first) {
            child = insertAndLayoutLeadingChild(childConstraints, parentUsesSize: true);
          }
        }
      } else {
        while (child != null && indexOf(child) < first) {
          before = child;
          leadingGarbage++;
          child = childAfter(child);
        }
        final hasFirst = child != null && indexOf(child) == first;
        final canAppend = child == null && before != null && indexOf(before) == first - 1;
        if (!hasFirst && !canAppend) child = null;
      }
      if (child == null && !(before != null && indexOf(before) == first - 1)) {
        // The children are somewhere else entirely: start over at [first].
        _dropAllChildren();
        before = null;
        leadingGarbage = 0;
      }
    }
    if (firstChild == null) {
      if (!addInitialChild(index: first, layoutOffset: ends[_shortest(ends)])) {
        final extent = _total(ends);
        geometry = SliverGeometry(scrollExtent: extent, maxPaintExtent: extent);
        childManager.didFinishLayout();
        return;
      }
      child = firstChild;
    }

    // 3. Lay out and place the cards from [first] until every column
    // reaches past the window.
    var reachedEnd = false;
    var shownEnd = 0.0;
    RenderBox? previous = before;
    while (true) {
      if (index >= count) {
        reachedEnd = true;
        break;
      }
      final column = _shortest(ends);
      if (index > first && ends[column] >= windowEnd) break;
      if (child == null || indexOf(child) != index) {
        child = insertAndLayoutChild(childConstraints, after: previous, parentUsesSize: true);
        if (child == null) {
          reachedEnd = true;
          break;
        }
      } else {
        child.layout(childConstraints, parentUsesSize: true);
      }
      final extent = paintExtentOf(child);
      if (_extents[index] != extent) {
        _extents[index] = extent;
        _measured[_itemIds[index]] = extent;
      }
      final data = child.parentData! as SliverGridParentData;
      data.layoutOffset = ends[column];
      data.crossAxisOffset = (mirrored ? columns - 1 - column : column) * stride;
      shownEnd = math.max(shownEnd, ends[column] + extent);
      ends[column] += extent + mainAxisSpacing;
      previous = child;
      child = childAfter(child);
      index++;
    }

    // 4. Let go of the children outside the window.
    var trailingGarbage = 0;
    while (child != null) {
      trailingGarbage++;
      child = childAfter(child);
    }
    collectGarbage(leadingGarbage, trailingGarbage);

    // 5. The rest of the cards, by their heights alone, for the full length.
    for (var i = index; i < count; i++) {
      final column = _shortest(ends);
      ends[column] += _extentAt(i) + mainAxisSpacing;
    }
    final scrollExtent = _total(ends);
    final shownStart = childScrollOffset(firstChild!)!;
    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: calculatePaintOffset(constraints, from: shownStart, to: shownEnd),
      cacheExtent: calculateCacheOffset(constraints, from: shownStart, to: shownEnd),
      maxPaintExtent: scrollExtent,
      hasVisualOverflow:
          shownEnd > constraints.scrollOffset + constraints.remainingPaintExtent ||
          constraints.scrollOffset > 0.0,
    );
    if (reachedEnd) childManager.setDidUnderflow(true);
    childManager.didFinishLayout();
  }
}
