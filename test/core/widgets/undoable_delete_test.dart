import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/core/widgets/app_snackbar.dart';
import 'package:grabby/core/widgets/undoable_delete.dart';

import '../../support/snackbar.dart';
import 'widget_harness.dart';

const _failure = StorageFailure();

/// One row whose delete button is unmounted by `hide`, like a list tile.
class _Host extends StatefulWidget {
  const _Host({required this.log, required this.commit});

  final List<String> log;
  final Future<Result<bool>> Function() commit;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  var _visible = true;

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox();
    return Builder(
      builder: (rowContext) => TextButton(
        onPressed: () => unawaited(
          runUndoableDelete(
            rowContext,
            message: 'File deleted',
            hide: () {
              widget.log.add('hide');
              setState(() => _visible = false);
            },
            restore: () {
              widget.log.add('restore');
              setState(() => _visible = true);
            },
            commit: () {
              widget.log.add('commit');
              return widget.commit();
            },
          ),
        ),
        child: const Text('Delete'),
      ),
    );
  }
}

void main() {
  late List<String> log;

  Future<void> start(
    WidgetTester tester,
    Future<Result<bool>> Function() commit,
  ) async {
    log = [];
    await tester.pumpWidget(themed(_Host(log: log, commit: commit)));
    await tester.tap(find.text('Delete'));
    await pumpSnackbarIn(tester);
  }

  testWidgets('hides at once and offers Undo with the message', (tester) async {
    await start(tester, () async => const Ok(true));

    expect(log, ['hide']);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('File deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Undo restores and never commits', (tester) async {
    await start(tester, () async => const Ok(true));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(log, ['hide', 'restore']);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a timeout commits and keeps the item hidden', (tester) async {
    await start(tester, () async => const Ok(true));
    expect(log, ['hide']);

    await pumpUndoExpired(tester);

    expect(log, ['hide', 'commit']);
    expect(find.text('Delete'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('another snackbar commits the delete', (tester) async {
    await start(tester, () async => const Ok(true));

    AppSnackbar.show(tester.element(find.byType(Scaffold)), 'Other');
    await tester.pumpAndSettle();

    expect(log, ['hide', 'commit']);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('a declined system dialog restores silently', (tester) async {
    await start(tester, () async => const Ok(false));

    await pumpUndoExpired(tester);

    expect(log, ['hide', 'commit', 'restore']);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an Err restores and shows the failure message', (tester) async {
    await start(tester, () async => const Err(_failure));

    await pumpUndoExpired(tester);

    expect(log, ['hide', 'commit', 'restore']);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text(_failure.message), findsOneWidget);
    expect(
      tester.widget<AppIcon>(find.byType(AppIcon)).icon,
      Assets.icons.alertCircle,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a slow commit leaves the item hidden until it answers', (
    tester,
  ) async {
    final answer = Completer<Result<bool>>();
    await start(tester, () => answer.future);

    await pumpUndoExpired(tester);
    expect(log, ['hide', 'commit']);
    expect(find.text('Delete'), findsNothing);

    answer.complete(const Ok(true));
    await tester.pumpAndSettle();

    expect(log, ['hide', 'commit']);
    expect(find.text('Delete'), findsNothing);
  });
}
