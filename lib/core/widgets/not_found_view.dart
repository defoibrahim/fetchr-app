import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import 'app_button.dart';
import 'empty_view.dart';

/// The page for a route nobody registered. Navigation is the app's job, so
/// `onHome` comes from the router.
class NotFoundView extends StatelessWidget {
  const NotFoundView({super.key, required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: EmptyView(
        message: 'This page does not exist.',
        action: AppButton(
          label: 'Go home',
          icon: Assets.icons.home,
          expanded: false,
          onPressed: onHome,
        ),
      ),
    );
  }
}
