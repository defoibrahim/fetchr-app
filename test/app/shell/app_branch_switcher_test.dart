import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shell/app_branch_switcher.dart';

import '../../core/widgets/widget_harness.dart';

const _duration = AppBranchSwitcher.duration;
const _fadeOut = AppBranchSwitcher.fadeOut;
const _tick = Duration(milliseconds: 1);

late ValueNotifier<int> _index;
late List<int> _taps;

/// A full-window page that counts its taps and reports whether its tickers
/// and heroes run.
class _Page extends StatefulWidget {
  const _Page(this.index);

  final int index;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  var taps = 0;

  bool get ticking => TickerMode.valuesOf(context).enabled;
  bool get heroes => context.findAncestorWidgetOfExactType<HeroMode>()!.enabled;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      _taps.add(widget.index);
      setState(() => taps++);
    },
    child: Center(child: Text('page ${widget.index} $taps')),
  );
}

Future<void> _pump(WidgetTester tester) async {
  useView(tester);
  _index = ValueNotifier(0);
  addTearDown(_index.dispose);
  _taps = [];
  await tester.pumpWidget(
    themed(
      ValueListenableBuilder(
        valueListenable: _index,
        builder: (_, index, _) => AppBranchSwitcher(
          currentIndex: index,
          children: const [_Page(0), _Page(1), _Page(2)],
        ),
      ),
    ),
  );
}

/// Switches, then pumps the frame that takes the switch and the one the
/// fade starts on.
Future<void> _go(WidgetTester tester, int index) async {
  _index.value = index;
  await tester.pump();
  await tester.pump();
}

Finder _page(int index) => find.byWidgetPredicate(
  (widget) => widget is _Page && widget.index == index,
  skipOffstage: false,
);

_PageState _state(WidgetTester tester, int index) =>
    tester.state<_PageState>(_page(index));

T _nearest<T extends Widget>(WidgetTester tester, int index) => tester
    .widget<T>(find.ancestor(of: _page(index), matching: find.byType(T)).first);

double _opacity(WidgetTester tester, int index) =>
    _nearest<FadeTransition>(tester, index).opacity.value;

double _scale(WidgetTester tester, int index) =>
    _nearest<ScaleTransition>(tester, index).scale.value;

bool _offstage(WidgetTester tester, int index) =>
    _nearest<Offstage>(tester, index).offstage;

void main() {
  testWidgets('the first build shows the current tab at rest', (tester) async {
    await _pump(tester);

    expect(await tester.pumpAndSettle(), 1);
    expect(_opacity(tester, 0), 1);
    expect(_scale(tester, 0), 1);
    expect(_offstage(tester, 0), isFalse);
    expect(_offstage(tester, 1), isTrue);
    expect(_offstage(tester, 2), isTrue);
  });

  testWidgets('the old tab fades out over 90 ms, then the new one fades in '
      'from 98%', (tester) async {
    await _pump(tester);

    await _go(tester, 1);
    expect(_opacity(tester, 0), 1);
    expect(_opacity(tester, 1), 0);
    expect(_offstage(tester, 0), isFalse);
    expect(_offstage(tester, 1), isFalse);

    await tester.pump(_fadeOut ~/ 2);
    expect(_opacity(tester, 0), inExclusiveRange(0, 1));
    expect(_opacity(tester, 1), 0);

    await tester.pump(_fadeOut ~/ 2);
    expect(_opacity(tester, 0), 0);
    expect(_opacity(tester, 1), 0);
    expect(_scale(tester, 1), closeTo(AppBranchSwitcher.scaleFrom, 1e-9));

    await tester.pump((_duration - _fadeOut) ~/ 2);
    expect(_opacity(tester, 1), inExclusiveRange(0, 1));
    expect(_scale(tester, 1), inExclusiveRange(AppBranchSwitcher.scaleFrom, 1));

    await tester.pump((_duration - _fadeOut) ~/ 2 + _tick);
    expect(_opacity(tester, 1), 1);
    expect(_scale(tester, 1), 1);
    expect(_offstage(tester, 0), isTrue);
    expect(await tester.pumpAndSettle(), 1);
  });

  testWidgets('only the current tab ticks and flies heroes, even mid-fade', (
    tester,
  ) async {
    await _pump(tester);
    expect(_state(tester, 0).ticking, isTrue);
    expect(_state(tester, 0).heroes, isTrue);

    await _go(tester, 1);
    await tester.pump(_fadeOut ~/ 2);

    expect(_state(tester, 0).ticking, isFalse);
    expect(_state(tester, 0).heroes, isFalse);
    expect(_state(tester, 1).ticking, isTrue);
    expect(_state(tester, 1).heroes, isTrue);
  });

  testWidgets('a tap during the fade goes to the new tab only', (tester) async {
    await _pump(tester);

    await _go(tester, 1);
    // The old tab still shows, the new one not yet.
    await tester.pump(_fadeOut ~/ 3);
    await tester.tapAt(tester.getCenter(find.byType(AppBranchSwitcher)));
    await tester.pump(_duration);

    expect(_taps, [1]);
  });

  testWidgets('every tab keeps its state across switches', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('page 0 0'));
    await tester.pump();
    final state = _state(tester, 0);

    await _go(tester, 2);
    await tester.pumpAndSettle();
    await _go(tester, 0);
    await tester.pumpAndSettle();

    expect(_state(tester, 0), same(state));
    expect(find.text('page 0 1'), findsOneWidget);
  });

  testWidgets('a switch mid-fade fades out what shows, from where it was', (
    tester,
  ) async {
    await _pump(tester);
    await _go(tester, 1);
    await tester.pump(_fadeOut ~/ 2);
    final shown = _opacity(tester, 0);

    await _go(tester, 2);
    // Tab 0 still shows more than tab 1, so it is the one fading out.
    expect(_opacity(tester, 0), closeTo(shown, 1e-9));
    expect(_offstage(tester, 1), isTrue);

    await tester.pump(_fadeOut ~/ 2);
    expect(_opacity(tester, 0), lessThan(shown));

    await tester.pumpAndSettle();
    expect(_opacity(tester, 2), 1);
    expect(_offstage(tester, 0), isTrue);
  });

  testWidgets('under reduce motion the switch is instant', (tester) async {
    reduceMotion(tester);
    await _pump(tester);

    _index.value = 1;
    await tester.pump();

    expect(_opacity(tester, 1), 1);
    expect(_scale(tester, 1), 1);
    expect(_offstage(tester, 0), isTrue);
    expect(await tester.pumpAndSettle(), 1);
  });
}
