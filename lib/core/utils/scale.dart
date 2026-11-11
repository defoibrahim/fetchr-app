import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_spacing.dart';

export 'package:flutter_screenutil/flutter_screenutil.dart' show SizeExtension;

const designSize = Size(375, 812);

// The only file that knows screenutil; the no-scaling variant makes this a
// pass-through and the extensions identities.
class ScaleScope extends StatelessWidget {
  const ScaleScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ScreenUtilInit(
    designSize: designSize,
    minTextAdapt: true,
    splitScreenMode: true,
    // From 600 dp the layout adds columns and a rail instead of growing:
    // .w/.h/.r/.sp are the design values. Read per call, so a resize flips it.
    enableScaleWH: () => ScreenUtil().screenWidth < Breakpoints.medium,
    builder: (_, child) => child!,
    child: child,
  );
}
