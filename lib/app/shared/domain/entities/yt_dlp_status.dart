import 'package:equatable/equatable.dart';

class YtDlpStatus extends Equatable {
  const YtDlpStatus({this.version, this.checkedAt, required this.autoUpdate});

  /// Null when native cannot report one: the bundled copy is in use.
  final String? version;

  /// The last successful update.
  final DateTime? checkedAt;
  final bool autoUpdate;

  YtDlpStatus withAutoUpdate(bool enabled) =>
      YtDlpStatus(version: version, checkedAt: checkedAt, autoUpdate: enabled);

  @override
  List<Object?> get props => [version, checkedAt, autoUpdate];
}
