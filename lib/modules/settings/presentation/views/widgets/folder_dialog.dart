import 'package:flutter/material.dart';

import '../../../../../app/shared/download_prefs_provider.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_text_field.dart';
import '../../../../../core/widgets/confirm_dialog.dart';

// What RequestBuilder.safeFolder strips or rewrites natively. Rejecting it
// here means the name the user sees is the name the folder gets.
final _forbidden = RegExp(r'[\\/:*?"<>|]');

String? validateFolderName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Enter a folder name';
  if (_forbidden.hasMatch(name)) {
    return 'Use no / \\ : * ? " < > | in the name';
  }
  if (name.startsWith('.')) return "A name can't start with a dot";
  return null;
}

/// The trimmed new name, or null when the user cancels.
Future<String?> showFolderDialog(BuildContext context, String current) =>
    showDialog<String>(
      context: context,
      builder: (_) => _FolderDialog(current: current),
    );

class _FolderDialog extends StatefulWidget {
  const _FolderDialog({required this.current});

  final String current;

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(Gap.xl.r),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.lg.h,
            children: [
              Text(
                'Save folder',
                style: DialogTheme.of(context).titleTextStyle,
              ),
              AppTextField(
                controller: _controller,
                label: 'Folder name',
                hint: DownloadPrefs.defaultFolder,
                validator: validateFolderName,
              ),
              DialogActions(confirmLabel: 'Save', onConfirm: _save),
            ],
          ),
        ),
      ),
    );
  }
}
