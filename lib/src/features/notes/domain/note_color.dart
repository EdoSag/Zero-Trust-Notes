import 'package:flutter/material.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// A note's background colour. Stored by [key], so the palette can be
/// retuned without touching saved notes.
enum NoteColor {
  none('none', 'Default', null, null),
  red('red', 'Red', Color(0xFFFAAFA8), Color(0xFF77172E)),
  orange('orange', 'Orange', Color(0xFFF39F76), Color(0xFF692B17)),
  yellow('yellow', 'Yellow', Color(0xFFFFF8B8), Color(0xFF7C4A03)),
  green('green', 'Green', Color(0xFFE2F6D3), Color(0xFF264D3B)),
  teal('teal', 'Teal', Color(0xFFB4DDD3), Color(0xFF0C625D)),
  blue('blue', 'Blue', Color(0xFFD4E4ED), Color(0xFF256377)),
  navy('navy', 'Dark blue', Color(0xFFAECCDC), Color(0xFF284255)),
  purple('purple', 'Purple', Color(0xFFD3BFDB), Color(0xFF472E5B)),
  pink('pink', 'Pink', Color(0xFFF6E2DD), Color(0xFF6C394F)),
  brown('brown', 'Brown', Color(0xFFE9E3D4), Color(0xFF4B443A)),
  gray('gray', 'Gray', Color(0xFFEFEFF1), Color(0xFF232427));

  const NoteColor(this.key, this.label, this._light, this._dark);

  final String key;

  /// English name (tests, logs). The UI uses [displayName].
  final String label;
  final Color? _light;
  final Color? _dark;

  /// The colour's name in the app's language.
  String get displayName {
    final l = currentL10n;
    return switch (this) {
      none => l.colorDefault,
      red => l.colorRed,
      orange => l.colorOrange,
      yellow => l.colorYellow,
      green => l.colorGreen,
      teal => l.colorTeal,
      blue => l.colorBlue,
      navy => l.colorNavy,
      purple => l.colorPurple,
      pink => l.colorPink,
      brown => l.colorBrown,
      gray => l.colorGray,
    };
  }

  static NoteColor fromKey(String? key) =>
      values.firstWhere((color) => color.key == key, orElse: () => none);

  /// The card colour for [brightness], or `null` for the theme's default.
  Color? background(Brightness brightness) => brightness == Brightness.dark ? _dark : _light;

  /// Google Keep Takeout colour names.
  static NoteColor fromKeep(String? name) => switch (name?.toUpperCase()) {
    'RED' => red,
    'ORANGE' => orange,
    'YELLOW' => yellow,
    'GREEN' => green,
    'TEAL' => teal,
    'BLUE' => blue,
    'CERULEAN' || 'DARK_BLUE' => navy,
    'PURPLE' => purple,
    'PINK' => pink,
    'BROWN' => brown,
    'GRAY' || 'GREY' => gray,
    _ => none,
  };
}
