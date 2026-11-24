import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/src/shared/widgets/sliver_card_columns.dart';

/// Card heights by id, so a card keeps its height wherever it moves.
double heightOf(int id) => 40.0 + (id * 37) % 150;

const spacing = 8.0;
const screen = Size(400, 600);

/// Where each card of [ids] belongs: in the shortest column so far.
Map<int, Rect> expectedRects(List<int> ids, {int columns = 2, bool rtl = false}) {
  final width = (screen.width - spacing * (columns - 1)) / columns;
  final ends = List.filled(columns, 0.0);
  final rects = <int, Rect>{};
  for (final id in ids) {
    var column = 0;
    for (var i = 1; i < columns; i++) {
      if (ends[i] < ends[column]) column = i;
    }
    final shown = rtl ? columns - 1 - column : column;
    rects[id] = Rect.fromLTWH(shown * (width + spacing), ends[column], width, heightOf(id));
    ends[column] += heightOf(id) + spacing;
  }
  return rects;
}

class Grid extends StatelessWidget {
  const Grid({
    super.key,
    required this.ids,
    this.header = 0,
    this.footer = 0,
    this.columns = 2,
    this.rtl = false,
    this.controller,
  });

  final List<int> ids;
  final double header;
  final double footer;
  final int columns;
  final bool rtl;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    child: CustomScrollView(
      controller: controller,
      slivers: [
        if (header > 0) SliverToBoxAdapter(child: SizedBox(height: header)),
        SliverCardColumns(
          itemIds: ids,
          crossAxisCount: columns,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          itemBuilder: (context, index) => SizedBox(
            key: ValueKey('card_${ids[index]}'),
            height: heightOf(ids[index]),
            child: Text('${ids[index]}', textDirection: TextDirection.ltr),
          ),
        ),
        if (footer > 0)
          SliverToBoxAdapter(
            child: SizedBox(key: const Key('footer'), height: footer),
          ),
      ],
    ),
  );
}

void main() {
  Future<void> show(WidgetTester tester, Widget grid) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(grid);
  }

  /// Every card in the tree sits where [ids] puts it, [header] and the
  /// scroll taken into account, and the cards on screen are all there.
  void expectPlaced(
    WidgetTester tester,
    List<int> ids,
    ScrollController controller, {
    double header = 0,
    int columns = 2,
    bool rtl = false,
  }) {
    final expected = expectedRects(ids, columns: columns, rtl: rtl);
    final pixels = controller.position.pixels;
    var built = 0;
    for (final id in ids) {
      final card = find.byKey(ValueKey('card_$id'));
      final want = expected[id]!.shift(Offset(0, header - pixels));
      if (card.evaluate().isEmpty) {
        expect(
          want.bottom <= 0 || want.top >= screen.height,
          isTrue,
          reason: 'card $id belongs on screen at $want but is not built',
        );
        continue;
      }
      built++;
      final got = tester.getRect(card);
      expect(got.left, moreOrLessEquals(want.left, epsilon: 0.01), reason: 'card $id left');
      expect(got.top, moreOrLessEquals(want.top, epsilon: 0.01), reason: 'card $id top');
      expect(got.width, moreOrLessEquals(want.width, epsilon: 0.01), reason: 'card $id width');
    }
    expect(built, greaterThan(0));
    // Only what is near the screen is built.
    expect(built, lessThan(40));
  }

  /// Scrolls from where it is to [to] a part of a screen at a time, as a
  /// finger does, so every card on the way is laid out.
  Future<void> scrollTo(WidgetTester tester, ScrollController controller, double to) async {
    while (controller.position.pixels != to) {
      final from = controller.position.pixels;
      controller.jumpTo(to > from ? (from + 500).clamp(from, to) : (from - 500).clamp(to, from));
      await tester.pump();
    }
  }

  final ids = List.generate(300, (i) => i);

  testWidgets('each card goes in the shortest column, down the whole list', (tester) async {
    final controller = ScrollController();
    await show(tester, Grid(ids: ids, controller: controller));
    expectPlaced(tester, ids, controller);
    final end = expectedRects(ids).values.map((r) => r.bottom).reduce((a, b) => a > b ? a : b);

    // Scroll to the end one screen at a time, then back.
    while (controller.position.pixels < controller.position.maxScrollExtent) {
      controller.jumpTo(
        (controller.position.pixels + 500).clamp(0, controller.position.maxScrollExtent),
      );
      await tester.pump();
      expectPlaced(tester, ids, controller);
    }
    expect(controller.position.maxScrollExtent, moreOrLessEquals(end - screen.height, epsilon: 0.01));
    while (controller.position.pixels > 0) {
      controller.jumpTo((controller.position.pixels - 500).clamp(0, double.infinity));
      await tester.pump();
      expectPlaced(tester, ids, controller);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolls on past the grid into what comes after it', (tester) async {
    // The notes list: a short Pinned grid, then the other notes. The old
    // grid sent the scroll back up as soon as it was out of sight.
    for (final pinned in [1, 2, 3]) {
      final controller = ScrollController();
      final few = ids.take(pinned).toList();
      await show(
        tester,
        Grid(key: ValueKey(pinned), ids: few, footer: 5000, controller: controller),
      );
      for (var i = 0; i < 8; i++) {
        final before = controller.position.pixels;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(controller.position.pixels, greaterThan(before + 300), reason: '$pinned pinned');
      }
      // And the grid is back when scrolled up again.
      controller.jumpTo(0);
      await tester.pump();
      expectPlaced(tester, few, controller);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('keeps its place when cards above the screen come, go and move', (tester) async {
    final controller = ScrollController();
    await show(tester, Grid(ids: ids, header: 100, controller: controller));
    await scrollTo(tester, controller, 6000);
    expectPlaced(tester, ids, controller, header: 100);

    Future<void> change(List<int> next) async {
      await tester.pumpWidget(Grid(ids: next, header: 100, controller: controller));
      expect(controller.position.pixels, 6000, reason: 'the scroll must stay where it is');
      // Cards never laid out count as average ones, so the cards on
      // screen may not be exactly where they will end up; they are once
      // the list has been scrolled through from the top.
      await scrollTo(tester, controller, 0);
      await scrollTo(tester, controller, 6000);
      expectPlaced(tester, next, controller, header: 100);
      expect(tester.takeException(), isNull);
    }

    // A new card on top (a note was added, or edited and came first).
    await change([1000, ...ids]);
    // A sync lands: cards added in several places, one removed, one moved up.
    await change([1001, 1000, ...ids.take(50), 1002, ...ids.skip(50).where((id) => id != 60 && id != 250), 250]);
    // Nearly everything goes.
    await tester.pumpWidget(Grid(ids: const [5, 6, 7], header: 100, controller: controller));
    await tester.pump();
    expect(controller.position.pixels, 0);
    expectPlaced(tester, const [5, 6, 7], controller, header: 100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards already laid out are placed exactly when they move', (tester) async {
    final controller = ScrollController();
    await show(tester, Grid(ids: ids, controller: controller));
    await scrollTo(tester, controller, 6000);
    // An edited note comes to the top and another is deleted, both above
    // the screen. Their heights are known, so nothing needs scrolling
    // through again.
    final next = [80, ...ids.where((id) => id != 80 && id != 20)];
    await tester.pumpWidget(Grid(ids: next, controller: controller));
    expect(controller.position.pixels, 6000);
    expectPlaced(tester, next, controller);
    await scrollTo(tester, controller, 0);
    expectPlaced(tester, next, controller);
    expect(tester.takeException(), isNull);
  });

  testWidgets('right to left, the first column is on the right', (tester) async {
    final controller = ScrollController();
    await show(tester, Grid(ids: ids, columns: 3, rtl: true, controller: controller));
    expect(tester.getRect(find.byKey(const ValueKey('card_0'))).right, screen.width);
    expectPlaced(tester, ids, controller, columns: 3, rtl: true);
    await scrollTo(tester, controller, 3000);
    expectPlaced(tester, ids, controller, columns: 3, rtl: true);
  });

  testWidgets('a jump far away and a change of columns both land right', (tester) async {
    final controller = ScrollController();
    await show(tester, Grid(ids: ids, controller: controller));
    for (var at = 0.0; at <= 9000; at += 500) {
      controller.jumpTo(at);
      await tester.pump();
    }
    controller.jumpTo(200);
    await tester.pump();
    expectPlaced(tester, ids, controller);
    controller.jumpTo(8800);
    await tester.pump();
    expectPlaced(tester, ids, controller);

    // Three columns: other widths, so everything is measured again.
    await tester.pumpWidget(Grid(ids: ids, columns: 3, controller: controller));
    controller.jumpTo(0);
    await tester.pump();
    for (var at = 0.0; at <= 3000; at += 500) {
      controller.jumpTo(at);
      await tester.pump();
      expectPlaced(tester, ids, controller, columns: 3);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('taps reach the card under the finger', (tester) async {
    int? tapped;
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SliverCardColumns(
              itemIds: ids,
              crossAxisCount: 2,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => tapped = ids[index],
                child: Container(
                  key: ValueKey('card_${ids[index]}'),
                  height: heightOf(ids[index]),
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('card_1')));
    expect(tapped, 1);
    await tester.tap(find.byKey(const ValueKey('card_4')));
    expect(tapped, 4);
  });
}
