import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/scale.dart';
import '../../core/widgets/section_header.dart';

/// The callback of an example that has nothing to do.
void noop() {}

/// An overline title over a column of examples.
class GallerySection extends StatelessWidget {
  const GallerySection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: Gap.xl.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.md.h,
        children: [SectionOverline(title), ...children],
      ),
    );
  }
}

/// A caption over one example.
class GalleryExample extends StatelessWidget {
  const GalleryExample({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.sm.h,
      children: [GalleryCaption(label), child],
    );
  }
}

/// A muted caption line.
class GalleryCaption extends StatelessWidget {
  const GalleryCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context.type.caption.copyWith(color: context.tokens.textMuted),
    );
  }
}
