import 'package:equatable/equatable.dart';

/// Which entries of a playlist are ticked. It stores the unticked ones, since
/// a playlist starts fully ticked and a large one stays cheap to copy.
class PlaylistSelection extends Equatable {
  const PlaylistSelection._(this.total, this._unticked);

  factory PlaylistSelection.all(int total) =>
      PlaylistSelection._(total, const {});

  final int total;
  final Set<int> _unticked;

  int get count => total - _unticked.length;

  bool get allSelected => total > 0 && count == total;

  bool isSelected(int index) =>
      index >= 0 && index < total && !_unticked.contains(index);

  PlaylistSelection toggle(int index) {
    if (index < 0 || index >= total) return this;
    return PlaylistSelection._(total, {
      for (final i in _unticked)
        if (i != index) i,
      if (!_unticked.contains(index)) index,
    });
  }

  /// Everything when some or none is ticked, none when everything is.
  PlaylistSelection toggleAll() => allSelected
      ? PlaylistSelection._(total, {for (var i = 0; i < total; i++) i})
      : PlaylistSelection.all(total);

  /// The ticked entries, ascending and 0-based.
  List<int> get indexes => [
    for (var i = 0; i < total; i++)
      if (!_unticked.contains(i)) i,
  ];

  @override
  List<Object?> get props => [total, _unticked];
}
