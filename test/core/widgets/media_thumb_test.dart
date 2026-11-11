import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/gen/fonts.gen.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/core/widgets/media_thumb.dart';
import 'package:grabby/core/widgets/stripes.dart';

import 'widget_harness.dart';

/// An image that always fails to load.
class _BrokenImage extends ImageProvider<_BrokenImage> {
  @override
  Future<_BrokenImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _BrokenImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Future<ImageInfo>.error('broken'));
}

const _network = NetworkImage('https://example.com/t.jpg');

Color? _fillOf(WidgetTester tester, Finder child) {
  final box = tester.widget<DecoratedBox>(
    find.ancestor(of: child, matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;

    Future<void> pump(WidgetTester tester, Widget thumb) => tester.pumpWidget(
      themed(
        Align(alignment: Alignment.topLeft, child: thumb),
        theme: theme,
      ),
    );

    group(mode, () {
      testWidgets('shows stripes when there is no image', (tester) async {
        await pump(tester, const MediaThumb(width: 84, height: 48));

        expect(find.byType(Stripes), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(tester.getSize(find.byType(MediaThumb)), const Size(84, 48));
      });

      testWidgets('the audio tile is an audioTile fill with a music note', (
        tester,
      ) async {
        await pump(
          tester,
          const MediaThumb(width: 84, height: 48, isAudio: true),
        );

        expect(find.byType(Stripes), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == tokens.audioTile,
          ),
          findsOneWidget,
        );
        final icon = tester.widget<AppIcon>(find.byType(AppIcon));
        expect(icon.icon, Assets.icons.music);
        expect(icon.size, 22.r);
        expect(icon.color, tokens.accent);
      });

      testWidgets('AudioTile fills its box and scales the icon size', (
        tester,
      ) async {
        await pump(
          tester,
          const SizedBox(
            width: 120,
            height: 80,
            child: AudioTile(iconSize: 56),
          ),
        );

        final tile = find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == tokens.audioTile,
        );
        expect(tester.getSize(tile), const Size(120, 80));
        final icon = tester.widget<AppIcon>(find.byType(AppIcon));
        expect(icon.icon, Assets.icons.music);
        expect(icon.size, 56.r);
        expect(icon.color, tokens.accent);
        expect(tester.getCenter(find.byType(AppIcon)), tester.getCenter(tile));

        await pump(
          tester,
          const SizedBox.square(dimension: 80, child: AudioTile()),
        );
        expect(tester.widget<AppIcon>(find.byType(AppIcon)).size, 22.r);
      });

      testWidgets('the duration badge shows only when a duration is given', (
        tester,
      ) async {
        await pump(
          tester,
          const MediaThumb(width: 84, height: 48, duration: '12:48'),
        );
        expect(find.text('12:48'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('12:48')).style!.fontFamily,
          FontFamily.jetBrainsMono,
        );
        expect(_fillOf(tester, find.text('12:48')), tokens.mediaScrim);
        expect(
          tester.widget<Text>(find.text('12:48')).style!.color,
          tokens.onMedia,
        );

        await pump(
          tester,
          const MediaThumb(width: 84, height: 48, duration: ''),
        );
        expect(find.byType(Text), findsNothing);

        await pump(tester, const MediaThumb(width: 84, height: 48));
        expect(find.byType(Text), findsNothing);
      });

      testWidgets('the duration badge sits 4 dp from the bottom right', (
        tester,
      ) async {
        await pump(
          tester,
          const MediaThumb(width: 84, height: 48, duration: '0:58'),
        );

        final thumb = tester.getRect(find.byType(MediaThumb));
        final badge = tester.getRect(
          find
              .ancestor(
                of: find.text('0:58'),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(thumb.right - badge.right, closeTo(4.r, 0.01));
        expect(thumb.bottom - badge.bottom, closeTo(4.r, 0.01));
      });

      testWidgets('the live badge is an error fill at the top left', (
        tester,
      ) async {
        await pump(
          tester,
          const MediaThumb(width: 84, height: 48, isLive: true),
        );

        expect(find.text('LIVE'), findsOneWidget);
        final style = tester.widget<Text>(find.text('LIVE')).style!;
        expect(style.color, tokens.onError);
        expect(style.fontWeight, FontWeight.w600);
        expect(_fillOf(tester, find.text('LIVE')), tokens.error);
        final thumb = tester.getRect(find.byType(MediaThumb));
        final badge = tester.getRect(
          find
              .ancestor(
                of: find.text('LIVE'),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(badge.left - thumb.left, closeTo(4.r, 0.01));
        expect(badge.top - thumb.top, closeTo(4.r, 0.01));
      });

      testWidgets('dimmed is 60% opacity', (tester) async {
        await pump(
          tester,
          const MediaThumb(width: 84, height: 48, dimmed: true),
        );
        expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.6);

        await pump(tester, const MediaThumb(width: 84, height: 48));
        expect(find.byType(Opacity), findsNothing);
      });

      testWidgets('the corners take the radius, scaled', (tester) async {
        await pump(tester, const MediaThumb(width: 84, height: 48, radius: 8));

        final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
        expect(clip.borderRadius, BorderRadius.circular(8.r));
      });

      testWidgets('a load error falls back to the stripes', (tester) async {
        await pump(
          tester,
          MediaThumb(image: _BrokenImage(), width: 84, height: 48),
        );
        await tester.pumpAndSettle();

        // The base layer and the error builder's copy.
        expect(find.byType(Stripes), findsNWidgets(2));
      });

      testWidgets('an infinite width takes the parent width and the ratio', (
        tester,
      ) async {
        await pump(
          tester,
          const SizedBox(
            width: 200,
            child: MediaThumb(width: double.infinity, aspectRatio: 1.6),
          ),
        );

        expect(tester.getSize(find.byType(MediaThumb)), const Size(200, 125));
      });
    });
  }

  group('decode size', () {
    const pixelRatio = 3.0;

    Future<ResizeImage> pumpThumb(
      WidgetTester tester, {
      required double width,
      required double height,
    }) async {
      tester.view.devicePixelRatio = pixelRatio;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        themed(
          Center(
            child: MediaThumb(image: _network, width: width, height: height),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image)).image;
      expect(image, isA<ResizeImage>());
      return image as ResizeImage;
    }

    // One cached side, so the image keeps its aspect ratio. The decoded pixels
    // must still cover the box, whichever way the source is oriented.
    for (final (name, width, height) in [
      ('a 64 dp square', 64.0, 64.0),
      ('a 16:9 header', 112.0, 63.0),
      ('a wide strip', 160.0, 40.0),
    ]) {
      group(name, () {
        testWidgets('a landscape 16:9 source stays sharp', (tester) async {
          final cached = await pumpThumb(tester, width: width, height: height);

          final decodedWidth = cached.width!;
          final decodedHeight = decodedWidth * 9 / 16;
          expect(decodedWidth, greaterThanOrEqualTo(width * pixelRatio));
          expect(decodedHeight, greaterThanOrEqualTo(height * pixelRatio - 1));
        });

        testWidgets('a portrait 9:16 source stays sharp', (tester) async {
          final cached = await pumpThumb(tester, width: width, height: height);

          // Portrait: the cached side is the width and covers the box width.
          expect(cached.width!, greaterThanOrEqualTo(width * pixelRatio));
        });

        testWidgets('decodes far below a full-size source', (tester) async {
          final cached = await pumpThumb(tester, width: width, height: height);

          expect(cached.width, lessThan(1080));
          expect(cached.height, isNull);
        });
      });
    }

    testWidgets('an infinite width decodes at the parent width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = pixelRatio;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        themed(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              child: MediaThumb(
                image: _network,
                width: double.infinity,
                aspectRatio: 1.6,
              ),
            ),
          ),
        ),
      );

      final cached =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(cached.width, greaterThanOrEqualTo(200 * pixelRatio));
    });
  });
}
