import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import '../utils/scale.dart';

const _dash = 4.0;
const _gap = 3.0;

/// A 1 dp dashed rounded outline (4 on, 3 off) in `borderStrong`, drawn over
/// [child]. [radius] is already scaled.
class DashedBorder extends StatelessWidget {
  const DashedBorder({super.key, required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: DashedBorderPainter(
      color: context.tokens.borderStrong,
      radius: radius,
      dash: _dash.r,
      gap: _gap.r,
    ),
    child: child,
  );
}

class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
    this.width = 1,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    // Half a stroke in, so the line stays inside the box.
    final rect = (Offset.zero & size).deflate(width / 2);
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + gap) {
        canvas.drawPath(
          metric.extractPath(at, math.min(at + dash, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      color != old.color ||
      radius != old.radius ||
      dash != old.dash ||
      gap != old.gap ||
      width != old.width;
}
