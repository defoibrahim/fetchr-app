import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'inert.dart';

/// A sliver list of one row per key that animates what changes between two
/// builds: a new key grows, fades and rises into place, a key that is gone
/// folds and fades away where it was, and a key that moved is both. A key that
/// comes back (Undo) grows back.
///
/// The first build does not animate, and neither does a row built later
/// because it scrolled in. A row keeps its element, and so its state, while
/// rows come and go around it. A leaving row is the last widget built for its
/// key, and it takes no taps, focus or semantics. Rows must not carry a
/// GlobalKey: the leaving copy is built again from the same widget.
class AppAnimatedSliverList<K extends Object> extends StatefulWidget {
  const AppAnimatedSliverList({
    super.key,
    required this.keys,
    required this.itemBuilder,
  });

  static const defaultInsert = MotionSpec(Motion.emphasis, Motion.enter);
  static const defaultRemove = MotionSpec(Motion.base, Motion.exit);

  /// How far a new row rises into place, in design dp.
  static const _rise = 8.0;

  /// One per row, unique, in order.
  final List<K> keys;
  final Widget Function(BuildContext context, K key) itemBuilder;
  @override
  State<AppAnimatedSliverList<K>> createState() =>
      _AppAnimatedSliverListState<K>();
}

class _AppAnimatedSliverListState<K extends Object>
    extends State<AppAnimatedSliverList<K>> {
  final _list = GlobalKey<SliverAnimatedListState>();
  late final List<K> _keys = List.of(widget.keys);
  late Map<K, int> _index = _indexOf(_keys);

  // The last widget built for each key on screen: what a leaving row shows.
  final _built = <K, Widget>{};
  var _leaving = 0;

  static Map<T, int> _indexOf<T>(List<T> keys) => {
    for (final (i, key) in keys.indexed) key: i,
  };

  @override
  void initState() {
    super.initState();
    assert(_unique(widget.keys));
  }

  static bool _unique(List<Object> keys) => keys.toSet().length == keys.length;

  @override
  void didUpdateWidget(AppAnimatedSliverList<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.keys;
    assert(_unique(next));
    if (listEquals(_keys, next)) return;
    final list = _list.currentState!;
    final insert = context
        .motionOf(AppAnimatedSliverList.defaultInsert)
        .duration;
    final remove = context
        .motionOf(AppAnimatedSliverList.defaultRemove)
        .duration;
    final stays = _staying(_keys, next);
    // Removals from the end, so each index is still the one on screen; then
    // insertions from the start, so each lands where `next` has it.
    for (var i = _keys.length - 1; i >= 0; i--) {
      final key = _keys[i];
      if (stays.contains(key)) continue;
      _keys.removeAt(i);
      final shown = _built.remove(key);
      final ghost = ValueKey((key, _leaving++));
      list.removeItem(
        i,
        (context, animation) => _Row(
          key: ghost,
          animation: animation,
          curve: AppAnimatedSliverList.defaultRemove.curve.flipped,
          rise: 0,
          leaving: true,
          child: shown ?? const SizedBox.shrink(),
        ),
        duration: remove,
      );
    }
    for (var i = 0; i < next.length; i++) {
      if (i < _keys.length && _keys[i] == next[i]) continue;
      _keys.insert(i, next[i]);
      list.insertItem(i, duration: insert);
    }
    assert(listEquals(_keys, next));
    _index = _indexOf(_keys);
  }

  /// The keys of [old] that keep their place: the longest run of them that
  /// [next] has in the same order. Every other old key leaves, and comes back
  /// where [next] puts it if it is still there.
  static Set<T> _staying<T extends Object>(List<T> old, List<T> next) {
    final at = _indexOf(next);
    final kept = [
      for (final key in old)
        if (at[key] case final i?) (key, i),
    ];
    // Patience sorting on the new positions: tails[l] is the index in `kept`
    // ending the best increasing run of length l + 1.
    final tails = <int>[];
    final before = List<int>.filled(kept.length, -1);
    for (var k = 0; k < kept.length; k++) {
      final position = kept[k].$2;
      var lo = 0;
      var hi = tails.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (kept[tails[mid]].$2 < position) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      if (lo > 0) before[k] = tails[lo - 1];
      if (lo == tails.length) {
        tails.add(k);
      } else {
        tails[lo] = k;
      }
    }
    final stays = <T>{};
    for (var k = tails.isEmpty ? -1 : tails.last; k >= 0; k = before[k]) {
      stays.add(kept[k].$1);
    }
    return stays;
  }

  Widget _item(BuildContext context, int index, Animation<double> animation) {
    final key = _keys[index];
    final child = widget.itemBuilder(context, key);
    _built[key] = child;
    return _Row(
      key: _RowKey(key),
      animation: animation,
      curve: AppAnimatedSliverList.defaultInsert.curve,
      rise: AppAnimatedSliverList._rise.h,
      leaving: false,
      child: child,
    );
  }

  int? _find(Key key) => key is _RowKey<K> ? _index[key.value] : null;

  @override
  Widget build(BuildContext context) => SliverAnimatedList(
    key: _list,
    initialItemCount: _keys.length,
    itemBuilder: _item,
    findChildIndexCallback: _find,
  );
}

class _RowKey<K> extends ValueKey<K> {
  const _RowKey(super.value);
}

/// One row, the same widgets whether it is arriving, staying or leaving, so a
/// row's state survives the moment its animation ends.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.animation,
    required this.curve,
    required this.rise,
    required this.leaving,
    required this.child,
  });

  final Animation<double> animation;
  final Curve curve;
  final double rise;
  final bool leaving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = animation.drive(CurveTween(curve: curve));
    return Inert(
      inert: leaving,
      child: _Grow(
        animation: t,
        rise: rise,
        child: FadeTransition(opacity: t, child: child),
      ),
    );
  }
}

/// Height from nothing to the child's, top first, with the child rising
/// [rise] into place. It clips only while the row is short of its height, so a
/// card's shadow or ripple is never cut off at rest.
class _Grow extends AnimatedWidget {
  const _Grow({
    required Animation<double> animation,
    required this.rise,
    required this.child,
  }) : super(listenable: animation);

  final double rise;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value.clamp(0.0, 1.0);
    return ClipRect(
      clipBehavior: t < 1 ? Clip.hardEdge : Clip.none,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        heightFactor: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * rise),
          child: child,
        ),
      ),
    );
  }
}
