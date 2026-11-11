import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/scale.dart';
import 'gallery_section.dart';

/// The Material controls the component themes restyle.
class ControlsSection extends StatefulWidget {
  const ControlsSection({super.key});

  @override
  State<ControlsSection> createState() => _ControlsSectionState();
}

class _ControlsSectionState extends State<ControlsSection> {
  var _switch = true;
  var _checked = true;
  var _radio = 0;
  var _chip = true;
  var _slider = .3;

  @override
  Widget build(BuildContext context) {
    return GallerySection(
      title: 'Controls',
      children: [
        GalleryExample(
          label: 'switch on and off',
          child: Row(
            spacing: Gap.md.w,
            children: [
              Switch(
                value: _switch,
                onChanged: (v) => setState(() => _switch = v),
              ),
              const Switch(value: false, onChanged: null),
            ],
          ),
        ),
        GalleryExample(
          label: 'checkbox checked and unchecked',
          child: Row(
            spacing: Gap.md.w,
            children: [
              Checkbox(
                value: _checked,
                onChanged: (v) => setState(() => _checked = v ?? false),
              ),
              Checkbox(
                value: !_checked,
                onChanged: (v) => setState(() => _checked = !(v ?? false)),
              ),
            ],
          ),
        ),
        GalleryExample(
          label: 'radio',
          child: RadioGroup<int>(
            groupValue: _radio,
            onChanged: (v) => setState(() => _radio = v ?? 0),
            child: Row(
              spacing: Gap.md.w,
              children: const [Radio<int>(value: 0), Radio<int>(value: 1)],
            ),
          ),
        ),
        GalleryExample(
          label: 'chips selected and not',
          child: Wrap(
            spacing: Gap.sm.w,
            children: [
              FilterChip(
                label: const Text('1080p'),
                selected: _chip,
                onSelected: (v) => setState(() => _chip = v),
              ),
              FilterChip(
                label: const Text('720p'),
                selected: !_chip,
                onSelected: (v) => setState(() => _chip = !v),
              ),
            ],
          ),
        ),
        GalleryExample(
          label: 'slider',
          child: Slider(
            value: _slider,
            onChanged: (v) => setState(() => _slider = v),
          ),
        ),
        const GalleryExample(
          label: 'spinner',
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }
}
