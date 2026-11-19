import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_fade_switcher.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/modules/library/presentation/views/widgets/player_controls.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../core/widgets/widget_harness.dart';
import 'player_view_harness.dart';

void main() {
  setUp(setUpPlayerHarness);

  group('the controls', () {
    testWidgets(
      'the play button reads Play while paused, Pause while playing',
      (tester) async {
        await pumpPlayer(tester, videoItem);
        expect(find.byTooltip('Play'), findsOneWidget);
        expect(find.byTooltip('Pause'), findsNothing);

        await emit(tester, playing, true);
        expect(find.byTooltip('Pause'), findsOneWidget);

        await emit(tester, playing, false);
        expect(find.byTooltip('Play'), findsOneWidget);
      },
    );

    testWidgets('starts out showing a player that is already playing', (
      tester,
    ) async {
      when(() => player.state).thenReturn(
        const PlayerState(playing: true, duration: Duration(minutes: 5)),
      );
      await pumpPlayer(tester, videoItem);

      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.text('0:00 / 5:00'), findsOneWidget);
    });

    testWidgets('a tap turns the icon at once; the report settles it', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);

      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(find.byTooltip('Pause'), findsOneWidget);

      // The player answers playing: nothing changes.
      await emit(tester, playing, true);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.pumpAndSettle();

      // It reports paused after all (the file ended): the icon follows.
      await emit(tester, playing, false);
      expect(find.byTooltip('Play'), findsOneWidget);
    });

    testWidgets('a failed toggle puts the icon back', (tester) async {
      when(
        () => player.playOrPause(),
      ).thenAnswer((_) async => throw StateError('gone'));
      await pumpPlayer(tester, videoItem);

      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Play'), findsOneWidget);
    });

    testWidgets('the play and pause glyphs morph: scale 0.6 up, 180 ms', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      final switcher = tester.widget<AppFadeSwitcher>(
        inControls(find.byType(AppFadeSwitcher)),
      );
      expect(switcher.scaleFrom, .6);
      expect(switcher.spec.duration, const Duration(milliseconds: 180));

      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(inControls(find.byType(AppIcon)), findsWidgets);
      expect(
        find.descendant(
          of: inControls(find.byType(AppFadeSwitcher)),
          matching: find.byType(AppIcon),
        ),
        findsNWidgets(2),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: inControls(find.byType(AppFadeSwitcher)),
          matching: find.byType(AppIcon),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the play button toggles playback', (tester) async {
      await pumpPlayer(tester, videoItem);

      await tester.tap(find.byTooltip('Play'));
      await tester.pump();

      verify(() => player.playOrPause()).called(1);
    });

    testWidgets('shows the position and the length', (tester) async {
      await pumpPlayer(tester, videoItem);
      expect(find.text('0:00 / 0:00'), findsOneWidget);

      await emit(tester, duration, const Duration(minutes: 12, seconds: 48));
      await emit(tester, position, const Duration(minutes: 4, seconds: 21));

      expect(find.text('4:21 / 12:48'), findsOneWidget);
    });

    testWidgets('a position tick redraws the time but not the buttons', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      final before = tester.widget(find.byTooltip('Play'));

      await emit(tester, position, const Duration(seconds: 7));

      expect(find.text('0:07 / 5:00'), findsOneWidget);
      expect(tester.widget(find.byTooltip('Play')), same(before));
    });

    testWidgets('a position that moved while hidden shows when it returns', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      final at = mediaPoint(tester, xFraction: .5);
      await tapMedia(tester, at);
      expect(overlayOpacity(tester), 0);

      await emit(tester, position, const Duration(seconds: 90));
      await tapMedia(tester, at);

      expect(overlayOpacity(tester), 1);
      expect(find.text('1:30 / 5:00'), findsOneWidget);
    });

    testWidgets('the 10 second buttons seek relative to the position', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      await emit(tester, position, const Duration(seconds: 60));

      await tester.tap(find.byTooltip('Forward 10 seconds'));
      await tester.pump();
      verify(() => player.seek(const Duration(seconds: 70))).called(1);

      await emit(tester, position, const Duration(seconds: 70));
      await tester.tap(find.byTooltip('Back 10 seconds'));
      await tester.pump();
      verify(() => player.seek(const Duration(seconds: 60))).called(1);
    });

    testWidgets('two quick taps add up before the player reports back', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      await emit(tester, position, const Duration(seconds: 60));

      await tester.tap(find.byTooltip('Forward 10 seconds'));
      await tester.tap(find.byTooltip('Forward 10 seconds'));
      await tester.pump();

      verify(() => player.seek(const Duration(seconds: 70))).called(1);
      verify(() => player.seek(const Duration(seconds: 80))).called(1);
      expect(find.text('1:20 / 5:00'), findsOneWidget);
    });

    testWidgets('seeking stops at the start and at the end', (tester) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      await emit(tester, position, const Duration(seconds: 4));

      await tester.tap(find.byTooltip('Back 10 seconds'));
      await tester.pump();
      verify(() => player.seek(Duration.zero)).called(1);

      await emit(tester, position, const Duration(seconds: 295));
      await tester.tap(find.byTooltip('Forward 10 seconds'));
      await tester.pump();
      verify(() => player.seek(const Duration(minutes: 5))).called(1);
    });

    testWidgets('a double tap on the left half goes back 10 seconds', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      await emit(tester, position, const Duration(seconds: 60));
      final at = mediaPoint(tester, xFraction: .15);

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 500));

      verify(() => player.seek(const Duration(seconds: 50))).called(1);
      expect(overlayOpacity(tester), 1);
    });

    testWidgets('a double tap on the right half goes forward 10 seconds', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      await emit(tester, position, const Duration(seconds: 60));
      final at = mediaPoint(tester, xFraction: .85);

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 500));

      verify(() => player.seek(const Duration(seconds: 70))).called(1);
    });

    testWidgets('a double-tap seek clicks', (tester) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      final at = mediaPoint(tester, xFraction: .85);
      final before = platformCalls.length;

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        platformCalls
            .skip(before)
            .where((call) => call.method == 'HapticFeedback.vibrate')
            .map((call) => call.arguments),
        ['HapticFeedbackType.selectionClick'],
      );
    });

    testWidgets('dragging the slider seeks once, where it lets go', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      await emit(tester, position, const Duration(seconds: 30));

      await tester.tapAt(tester.getCenter(find.byType(Slider)));
      await tester.pump();

      final seeks = verify(() => player.seek(captureAny())).captured;
      expect(seeks, hasLength(1));
      expect((seeks.single as Duration).inSeconds, closeTo(150, 1));
    });

    testWidgets('the slider cannot be dragged before the length is known', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);

      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    });
  });

  group('the overlay', () {
    testWidgets('starts shown', (tester) async {
      await pumpPlayer(tester, videoItem);

      expect(overlayOpacity(tester), 1);
    });

    testWidgets('a tap hides it and the next tap brings it back', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      final at = mediaPoint(tester, xFraction: .5);

      await tapMedia(tester, at);
      expect(overlayOpacity(tester), 0);

      await tapMedia(tester, at);
      expect(overlayOpacity(tester), 1);
    });

    testWidgets('a touch on the hidden overlay shows it as the finger lands', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      final at = mediaPoint(tester, xFraction: .5);
      await tapMedia(tester, at);
      expect(overlayOpacity(tester), 0);

      final gesture = await tester.startGesture(at);
      await tester.pump();
      // Well inside the 300 ms double-tap window.
      expect(overlayOpacity(tester), 1);
      final fade = overlayFade(tester);
      expect(fade.duration, Motion.fast);
      expect(fade.curve, Motion.enter);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      // The tap that brought it back does not hide it.
      expect(overlayOpacity(tester), 1);
    });

    testWidgets('it hides over 250 ms on the exit curve', (tester) async {
      await pumpPlayer(tester, videoItem);
      await tapMedia(tester, mediaPoint(tester, xFraction: .5));
      final fade = overlayFade(tester);
      expect(fade.opacity, 0);
      expect(fade.duration, Motion.medium);
      expect(fade.curve, Motion.exit);
    });

    testWidgets('a tap on the hidden overlay does not press a button', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      final centre = tester.getCenter(find.byType(PlayerControls).first);
      await tapMedia(tester, mediaPoint(tester, xFraction: .5));
      expect(overlayOpacity(tester), 0);

      await tapMedia(tester, centre);

      expect(overlayOpacity(tester), 1);
      verifyNever(() => player.playOrPause());
    });

    testWidgets(
      'a double tap on the hidden overlay seeks, even over the play button',
      (tester) async {
        await pumpPlayer(tester, videoItem);
        await emit(tester, duration, const Duration(minutes: 5));
        await emit(tester, position, const Duration(seconds: 60));
        // Right of centre, on the play button once the overlay is up.
        final play = tester.getCenter(find.byTooltip('Play'));
        await tapMedia(tester, mediaPoint(tester, xFraction: .5));
        expect(overlayOpacity(tester), 0);

        await tester.tapAt(play + const Offset(4, 0));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(play + const Offset(4, 0));
        await tester.pump(const Duration(milliseconds: 500));

        verify(() => player.seek(const Duration(seconds: 70))).called(1);
        verifyNever(() => player.playOrPause());
        expect(overlayOpacity(tester), 1);
      },
    );

    testWidgets('a double tap on the hidden overlay seeks over the slider', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      await emit(tester, position, const Duration(seconds: 60));
      final slider = tester.getRect(inControls(find.byType(Slider)));
      final at = Offset(slider.left + slider.width * .15, slider.center.dy);
      await tapMedia(tester, mediaPoint(tester, xFraction: .5));
      expect(overlayOpacity(tester), 0);

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 500));

      // Back 10 seconds, not a jump to where the finger was on the slider.
      final seeks = verify(() => player.seek(captureAny())).captured;
      expect(seeks, [const Duration(seconds: 50)]);
    });

    testWidgets('once a revealing tap settles, the buttons take taps again', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      await tapMedia(tester, mediaPoint(tester, xFraction: .5));
      expect(overlayOpacity(tester), 0);
      await tapMedia(tester, mediaPoint(tester, xFraction: .5));
      expect(overlayOpacity(tester), 1);

      await tester.tap(find.byTooltip('Play'));
      await tester.pump();

      verify(() => player.playOrPause()).called(1);
    });

    testWidgets('hides itself 3 seconds into playback', (tester) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, playing, true);

      await tester.pump(const Duration(milliseconds: 2900));
      expect(overlayOpacity(tester), 1);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 250));
      expect(overlayOpacity(tester), 0);
    });

    testWidgets('stays up during playback while a screen reader is on', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpPlayer(tester, videoItem);
      await emit(tester, playing, true);

      await tester.pump(const Duration(seconds: 10));

      expect(overlayOpacity(tester), 1);
      expect(find.byTooltip('Fullscreen'), findsOneWidget);
    });

    testWidgets('stays up while paused', (tester) async {
      await pumpPlayer(tester, videoItem);

      await tester.pump(const Duration(seconds: 10));

      expect(overlayOpacity(tester), 1);
    });

    testWidgets('pausing keeps it up, and playing again starts the timer', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, playing, true);
      await tester.pump(const Duration(seconds: 2));
      await emit(tester, playing, false);

      await tester.pump(const Duration(seconds: 10));
      expect(overlayOpacity(tester), 1);

      await emit(tester, playing, true);
      await tester.pump(const Duration(milliseconds: 3300));
      expect(overlayOpacity(tester), 0);
    });

    testWidgets('a touch restarts the 3 seconds', (tester) async {
      await pumpPlayer(tester, videoItem);
      await emit(tester, duration, const Duration(minutes: 5));
      await emit(tester, playing, true);
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byTooltip('Forward 10 seconds'));
      await tester.pump(const Duration(seconds: 2));
      expect(overlayOpacity(tester), 1);

      await tester.pump(const Duration(milliseconds: 1300));
      expect(overlayOpacity(tester), 0);
    });

    testWidgets('does not fade when the user asks for less motion', (
      tester,
    ) async {
      reduceMotion(tester);
      await pumpPlayer(tester, videoItem);

      await tapMedia(tester, mediaPoint(tester, xFraction: .5));

      expect(overlayFade(tester).duration, Duration.zero);
    });
  });

  group('fullscreen', () {
    Iterable<String?> chromeCalls(String method) => platformCalls
        .where((call) => call.method == method)
        .map((call) => call.arguments?.toString());

    testWidgets('goes immersive and landscape, and puts both back on exit', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);

      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
      expect(chromeCalls('SystemChrome.setPreferredOrientations'), [
        '[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]',
      ]);
      expect(chromeCalls('SystemChrome.setEnabledSystemUIMode'), [
        'SystemUiMode.immersiveSticky',
      ]);

      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Fullscreen'), findsOneWidget);
      expect(chromeCalls('SystemChrome.setPreferredOrientations').last, '[]');
      expect(
        chromeCalls('SystemChrome.setEnabledSystemUIMode').last,
        'SystemUiMode.edgeToEdge',
      );
    });

    testWidgets('the system back button leaves it too', (tester) async {
      await pumpPlayer(tester, videoItem);
      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byTooltip('Fullscreen'), findsOneWidget);
      expect(
        chromeCalls('SystemChrome.setEnabledSystemUIMode').last,
        'SystemUiMode.edgeToEdge',
      );
    });
  });
}
