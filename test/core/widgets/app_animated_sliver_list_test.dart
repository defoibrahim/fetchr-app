import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_animated_sliver_list.dart';

import 'widget_harness.dart';

const _rowHeight = 50.0;
final _insert = AppAnimatedSliverList.defaultInsert.duration;
final _remove = AppAnimatedSliverList.defaultRemove.duration;

// An animation is done only once its time has passed, so a pump of exactly
// its duration leaves it one tick short.
const _tick = Duration(milliseconds: 1);

late ValueNotifier<List<String>> _keys;
late List<String> _taps;

/// A row that counts its own taps, to show whose state survives.
class _Tile extends StatefulWidget {
  const _Tile(this.label);

  final String label;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  var taps = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('tile-${widget.label}'),
    height: _rowHeight,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _taps.add(widget.label);
        setState(() => taps++);
      },
      child: Text('${widget.label} $taps'),
    ),
  );
}

Future<void> _pump(WidgetTester tester, List<String> keys) async {
  useView(tester);
  _keys = ValueNotifier(keys);
  addTearDown(_keys.dispose);
  _taps = [];
  await tester.pumpWidget(
    themed(
      ValueListenableBuilder(
        valueListenable: _keys,
        builder: (_, keys, _) => CustomScrollView(
          slivers: [
            AppAnimatedSliverList<String>(
              keys: keys,
              itemBuilder: (_, key) => _Tile(key),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Sets the keys, then pumps the frame that takes them and the one the
/// animations start on.
Future<void> _set(WidgetTester tester, List<String> keys) async {
  _keys.value = keys;
  await tester.pump();
  await tester.pump();
}

Finder _tile(String key) => find.byKey(ValueKey('tile-$key'));

Finder _nearest(Finder of, Type type) =>
    find.ancestor(of: of, matching: find.byType(type)).first;

double _height(WidgetTester tester, String key, {int at = 0}) =>
    tester.getSize(_nearest(_tile(key).at(at), Align)).height;

double _opacity(WidgetTester tester, String key, {int at = 0}) => tester
    .widget<FadeTransition>(_nearest(_tile(key).at(at), FadeTransition))
    .opacity
    .value;

double _top(WidgetTester tester, String key, {int at = 0}) =>
    tester.getTopLeft(_tile(key).at(at)).dy;

List<String> _order(WidgetTester tester) {
  final tiles = tester.widgetList<_Tile>(find.byType(_Tile)).toList();
  final tops = {
    for (final tile in tiles)
      tile.label: tester.getTopLeft(find.byWidget(tile)).dy,
  };
  return tops.keys.toList()..sort((a, b) => tops[a]!.compareTo(tops[b]!));
}

void main() {
  test(
    'rows arrive over 300 ms decelerating and leave over 200 accelerating',
    () {
      expect(
        AppAnimatedSliverList.defaultInsert,
        const MotionSpec(Motion.emphasis, Motion.enter),
      );
      expect(
        AppAnimatedSliverList.defaultRemove,
        const MotionSpec(Motion.base, Motion.exit),
      );
    },
  );

  testWidgets('the first build is in place, with nothing to animate', (
    tester,
  ) async {
    await _pump(tester, ['a', 'b', 'c']);

    expect(await tester.pumpAndSettle(), 1);
    for (final key in ['a', 'b', 'c']) {
      expect(_height(tester, key), _rowHeight);
      expect(_opacity(tester, key), 1);
    }
    expect(_order(tester), ['a', 'b', 'c']);
  });

  testWidgets('a new key grows, fades and rises into place', (tester) async {
    await _pump(tester, ['a', 'b']);

    await _set(tester, ['a', 'x', 'b']);
    expect(_height(tester, 'x'), 0);
    expect(_opacity(tester, 'x'), 0);

    await tester.pump(_insert ~/ 2);
    expect(_height(tester, 'x'), inExclusiveRange(0, _rowHeight));
    expect(_opacity(tester, 'x'), inExclusiveRange(0, 1));
    // Rising: the row sits lower than the top of its slot.
    final slot = tester.getTopLeft(_nearest(_tile('x'), Align)).dy;
    expect(_top(tester, 'x'), greaterThan(slot));

    await tester.pump(_insert ~/ 2 + _tick);
    expect(_height(tester, 'x'), _rowHeight);
    expect(_opacity(tester, 'x'), 1);
    expect(_top(tester, 'x'), _rowHeight);
    expect(_order(tester), ['a', 'x', 'b']);
    expect(await tester.pumpAndSettle(), 1);
  });

  testWidgets('a key that is gone folds away where it was', (tester) async {
    await _pump(tester, ['a', 'b', 'c']);

    await _set(tester, ['a', 'c']);
    await tester.pump(_remove ~/ 2);
    expect(_order(tester), ['a', 'b', 'c']);
    expect(_height(tester, 'b'), inExclusiveRange(0, _rowHeight));
    expect(_opacity(tester, 'b'), inExclusiveRange(0, 1));
    expect(_top(tester, 'c'), inExclusiveRange(_rowHeight, 2 * _rowHeight));

    await tester.pump(_remove ~/ 2 + _tick);
    expect(_tile('b'), findsNothing);
    expect(_top(tester, 'c'), _rowHeight);
    expect(_order(tester), ['a', 'c']);
  });

  testWidgets('a leaving row takes no taps; the rows around it do', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, ['a', 'b', 'c']);
    expect(find.bySemanticsLabel('b 0'), findsOneWidget);

    await _set(tester, ['a', 'c']);
    await tester.pump(_remove ~/ 4);
    await tester.tap(_tile('b'), warnIfMissed: false);
    await tester.tap(_tile('c'));
    await tester.pump();

    expect(_taps, ['c']);
    expect(find.bySemanticsLabel('b 0'), findsNothing);
    expect(find.bySemanticsLabel('c 1'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a row keeps its state while one arrives above it', (
    tester,
  ) async {
    await _pump(tester, ['a', 'b']);
    await tester.tap(_tile('b'));
    await tester.tap(_tile('b'));
    await tester.pump();
    final state = tester.state<_TileState>(find.byType(_Tile).at(1));
    expect(state.taps, 2);

    await _set(tester, ['x', 'a', 'b']);
    await tester.pump(_insert + _tick);

    expect(find.text('b 2'), findsOneWidget);
    expect(tester.state<_TileState>(find.byType(_Tile).at(2)), same(state));
  });

  testWidgets('a moved key leaves its place and arrives at the new one', (
    tester,
  ) async {
    await _pump(tester, ['a', 'b', 'c']);
    await tester.tap(_tile('a'));
    await tester.pump();

    await _set(tester, ['c', 'a', 'b']);
    await tester.pump(_remove ~/ 2);
    // The old c still folds at the end while the new one grows at the top.
    expect(_tile('c'), findsNWidgets(2));
    expect(_top(tester, 'c', at: 0), lessThan(_top(tester, 'a')));

    await tester.pump(_insert + _tick);
    expect(_tile('c'), findsOneWidget);
    expect(_order(tester), ['c', 'a', 'b']);
    // The longest run that kept its order stayed put, state and all.
    expect(find.text('a 1'), findsOneWidget);
  });

  testWidgets('a key that comes back while it folds grows back (Undo)', (
    tester,
  ) async {
    await _pump(tester, ['a', 'b']);

    await _set(tester, ['a']);
    await tester.pump(_remove ~/ 2);
    await _set(tester, ['a', 'b']);
    await tester.pump(_remove ~/ 4);
    // The old row still folds while the new one grows back.
    expect(_tile('b'), findsNWidgets(2));

    await tester.pump(_insert + _tick);
    expect(_tile('b'), findsOneWidget);
    expect(_height(tester, 'b'), _rowHeight);
    expect(_opacity(tester, 'b'), 1);
    expect(_order(tester), ['a', 'b']);
  });

  testWidgets('unchanged keys rebuild rows without animating them', (
    tester,
  ) async {
    await _pump(tester, ['a', 'b']);

    await _set(tester, ['a', 'b']);

    expect(await tester.pumpAndSettle(), 1);
    expect(_height(tester, 'b'), _rowHeight);
  });

  testWidgets('under reduce motion rows arrive and leave at once', (
    tester,
  ) async {
    reduceMotion(tester);
    await _pump(tester, ['a', 'b', 'c']);

    await _set(tester, ['x', 'a', 'c']);

    expect(_tile('b'), findsNothing);
    expect(_height(tester, 'x'), _rowHeight);
    expect(_opacity(tester, 'x'), 1);
    expect(_order(tester), ['x', 'a', 'c']);
    expect(await tester.pumpAndSettle(), 1);
  });
}
