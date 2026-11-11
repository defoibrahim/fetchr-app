import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// The thumbnail placeholder: bands at 135 degrees, `band` dp wide, like the
/// mockups' `repeating-linear-gradient(135deg, a 0 band, b band 2*band)`.
class Stripes extends StatelessWidget {
  const Stripes({super.key, this.band = 8});

  final double band;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox.expand(
      child: CustomPaint(
        painter: _StripesPainter(
          first: tokens.stripeA,
          second: tokens.stripeB,
          band: band,
        ),
      ),
    );
  }
}

class _StripesPainter extends CustomPainter {
  const _StripesPainter({
    required this.first,
    required this.second,
    required this.band,
  });

  final Color first;
  final Color second;
  final double band;

  @override
  void paint(Canvas canvas, Size size) {
    // The gradient line runs corner to corner along 135 degrees, so its length
    // is the box projected on that direction.
    final length = (size.width + size.height) * math.sqrt1_2;
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(size.width / 2, size.height / 2)
      ..rotate(math.pi / 4);
    final bandPaint = Paint();
    var index = 0;
    for (var x = -length / 2; x < length / 2; x += band) {
      bandPaint.color = index.isEven ? first : second;
      // Tall enough to cover the box whatever the rotation.
      canvas.drawRect(Rect.fromLTWH(x, -length, band, length * 2), bandPaint);
      index++;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripesPainter old) =>
      old.first != first || old.second != second || old.band != band;
}
