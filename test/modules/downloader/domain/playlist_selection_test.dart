import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/modules/downloader/domain/entities/playlist_selection.dart';

void main() {
  group('all', () {
    test('ticks every entry', () {
      final selection = PlaylistSelection.all(3);

      expect(selection.total, 3);
      expect(selection.count, 3);
      expect(selection.allSelected, isTrue);
      expect(
        [for (var i = 0; i < 3; i++) selection.isSelected(i)],
        [true, true, true],
      );
      expect(selection.indexes, [0, 1, 2]);
    });

    test('is not "all selected" for an empty playlist', () {
      final selection = PlaylistSelection.all(0);

      expect(selection.count, 0);
      expect(selection.allSelected, isFalse);
      expect(selection.indexes, isEmpty);
    });
  });

  group('toggle', () {
    test('unticks a ticked entry and ticks it again', () {
      final off = PlaylistSelection.all(3).toggle(1);

      expect(off.isSelected(1), isFalse);
      expect(off.count, 2);
      expect(off.allSelected, isFalse);
      expect(off.indexes, [0, 2]);

      final on = off.toggle(1);

      expect(on.isSelected(1), isTrue);
      expect(on.allSelected, isTrue);
      expect(on, PlaylistSelection.all(3));
    });

    test('leaves the original untouched', () {
      final selection = PlaylistSelection.all(3);

      selection.toggle(0);

      expect(selection.count, 3);
    });

    test('ignores an index outside the playlist', () {
      final selection = PlaylistSelection.all(3);

      expect(selection.toggle(-1), selection);
      expect(selection.toggle(3), selection);
      expect(selection.isSelected(3), isFalse);
      expect(selection.isSelected(-1), isFalse);
    });

    test('lists the ticked entries ascending whatever the toggle order', () {
      final selection = PlaylistSelection.all(
        5,
      ).toggle(4).toggle(0).toggle(2).toggle(4);

      expect(selection.indexes, [1, 3, 4]);
    });
  });

  group('toggleAll', () {
    test('unticks everything when everything is ticked', () {
      final none = PlaylistSelection.all(4).toggleAll();

      expect(none.count, 0);
      expect(none.indexes, isEmpty);
      expect(none.allSelected, isFalse);
    });

    test('ticks everything from none', () {
      final all = PlaylistSelection.all(4).toggleAll().toggleAll();

      expect(all, PlaylistSelection.all(4));
    });

    test('ticks everything from a partial selection', () {
      final all = PlaylistSelection.all(4).toggle(2).toggleAll();

      expect(all.allSelected, isTrue);
      expect(all.indexes, [0, 1, 2, 3]);
    });

    test('does nothing for an empty playlist', () {
      final selection = PlaylistSelection.all(0).toggleAll();

      expect(selection.count, 0);
      expect(selection.allSelected, isFalse);
    });
  });

  test('compares by value', () {
    expect(PlaylistSelection.all(3), PlaylistSelection.all(3));
    expect(PlaylistSelection.all(3), isNot(PlaylistSelection.all(4)));
    expect(
      PlaylistSelection.all(3).toggle(0),
      PlaylistSelection.all(3).toggle(0),
    );
    expect(
      PlaylistSelection.all(3).toggle(0),
      isNot(PlaylistSelection.all(3).toggle(1)),
    );
  });
}
