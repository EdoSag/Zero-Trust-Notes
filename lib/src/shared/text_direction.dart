import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

/// The direction a piece of note text reads in, from its first letter that
/// has one: Hebrew or Arabic text reads right to left even in the English
/// app, like Keep does. Null (follow the app) when there's no such letter
/// yet.
TextDirection? textDirectionOf(String text) {
  if (Bidi.startsWithRtl(text)) return TextDirection.rtl;
  if (Bidi.startsWithLtr(text)) return TextDirection.ltr;
  return null;
}
