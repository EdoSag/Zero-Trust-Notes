import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../drawing/drawing.dart';
import '../image_text/image_text_reader.dart';

/// Handwriting to text: reads what was written on a drawing, on this phone.
///
/// The strokes are split into lines of writing, and each line is redrawn
/// on its own (black on white, at a size the recogniser reads best) and
/// read by the same open-source recogniser as "Text from image"
/// (Tesseract, English and Hebrew bundled with the app). Nothing is
/// uploaded and no extra model is downloaded.
///
/// Highlighter strokes are left out: they mark, they don't write.
Future<String> readHandwriting(
  Drawing drawing,
  ImageTextReader reader, {
  required String languages,
}) async {
  final lines = handwritingLines(drawing.strokes);
  final out = <String>[];
  for (final line in lines) {
    final png = await renderInkLine(line);
    final text = (await reader.read(png, languages: languages, singleLine: true)).trim();
    if (text.isNotEmpty) out.add(text);
  }
  return out.join('\n');
}

/// The pen strokes of [strokes] grouped into lines of writing, top to
/// bottom. Strokes that sit side by side (overlapping a good part of each
/// other's height) are one line; small marks (dots, accents, Hebrew
/// vowel points) join the nearest line instead of making their own.
List<List<Stroke>> handwritingLines(List<Stroke> strokes) {
  final ink = [
    for (final s in strokes)
      if (!s.highlighter && s.points.isNotEmpty) _Ink(s),
  ];
  if (ink.isEmpty) return const [];
  final heights = [for (final i in ink) i.height]..sort();
  final median = heights[heights.length ~/ 2];
  final small = math.max(4.0, median * 0.35);

  final lines = <_Line>[];
  final marks = <_Ink>[];
  for (final i in [...ink]..sort((a, b) => a.center.compareTo(b.center))) {
    if (i.height < small && i.width < median) {
      marks.add(i);
      continue;
    }
    _Line? best;
    var bestOverlap = 0.0;
    for (final line in lines) {
      final overlap = math.min(line.bottom, i.bottom) - math.max(line.top, i.top);
      final share = overlap / math.min(line.height, i.height).clamp(1.0, double.infinity);
      if (share > 0.4 && share > bestOverlap) {
        best = line;
        bestOverlap = share;
      }
    }
    if (best == null) {
      lines.add(_Line(i));
    } else {
      best.add(i);
    }
  }
  for (final mark in marks) {
    if (lines.isEmpty) {
      lines.add(_Line(mark));
      continue;
    }
    _Line nearest = lines.first;
    var distance = double.infinity;
    for (final line in lines) {
      final d = mark.center < line.top
          ? line.top - mark.center
          : mark.center > line.bottom
          ? mark.center - line.bottom
          : 0.0;
      if (d < distance) {
        distance = d;
        nearest = line;
      }
    }
    nearest.add(mark);
  }
  lines.sort((a, b) => a.top.compareTo(b.top));
  return [
    for (final line in lines) [for (final i in line.ink) i.stroke],
  ];
}

/// One line of writing as a PNG for the recogniser: black ink on white,
/// scaled so the line is about [lineHeight] pixels high, with a margin.
Future<Uint8List> renderInkLine(List<Stroke> line, {double lineHeight = 72}) async {
  var left = double.infinity, top = double.infinity;
  var right = -double.infinity, bottom = -double.infinity;
  for (final s in line) {
    for (final p in s.points) {
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
  }
  final height = math.max(bottom - top, 1.0);
  final scale = (lineHeight / height).clamp(0.5, 8.0);
  const margin = 32.0;
  final width = ((right - left) * scale + margin * 2).ceil().clamp(1, 8000);
  final imageHeight = (height * scale + margin * 2).ceil().clamp(1, 2000);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), imageHeight.toDouble()),
    Paint()..color = Colors.white,
  );
  final paint = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    // Even ink, whatever pen width or pressure was used.
    ..strokeWidth = math.max(3.0, lineHeight / 14);
  Offset at(Offset p) => Offset((p.dx - left) * scale + margin, (p.dy - top) * scale + margin);
  for (final s in line) {
    if (s.points.length == 1) {
      canvas.drawCircle(at(s.points.first), paint.strokeWidth / 2, Paint()..color = Colors.black);
      continue;
    }
    final path = Path()..moveTo(at(s.points.first).dx, at(s.points.first).dy);
    for (final p in s.points.skip(1)) {
      final q = at(p);
      path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(path, paint);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, imageHeight);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _Ink {
  _Ink(this.stroke) {
    var t = double.infinity, b = -double.infinity, l = double.infinity, r = -double.infinity;
    for (final p in stroke.points) {
      t = math.min(t, p.dy);
      b = math.max(b, p.dy);
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
    }
    top = t;
    bottom = b;
    width = r - l;
  }

  final Stroke stroke;
  late final double top;
  late final double bottom;
  late final double width;
  double get height => bottom - top;
  double get center => (top + bottom) / 2;
}

class _Line {
  _Line(_Ink first) : top = first.top, bottom = first.bottom, ink = [first];

  double top;
  double bottom;
  final List<_Ink> ink;
  double get height => bottom - top;

  void add(_Ink i) {
    ink.add(i);
    top = math.min(top, i.top);
    bottom = math.max(bottom, i.bottom);
  }
}
