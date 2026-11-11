import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';

const _width = 36.0;
const _height = 4.0;

class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _width.w,
      height: _height.h,
      decoration: BoxDecoration(
        color: context.tokens.borderStrong,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
    );
  }
}
