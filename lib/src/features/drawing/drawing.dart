import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum DrawingTool { pen, highlighter, eraser }

/// One line drawn with a finger or a stylus.
@immutable
class Stroke {
  const Stroke({
    required this.points,
    required this.color,
    required this.width,
    this.highlighter = false,
    this.pressures,
  });

  /// In the drawing's own coordinates (see [Drawing.size]).
  final List<Offset> points;
  final Color color;
  final double width;
  final bool highlighter;

  /// A stylus's pressure (0..1) at each point; null for a finger.
  final List<double>? pressures;

  Stroke extended(Offset point, [double? pressure]) => Stroke(
    points: [...points, point],
    color: color,
    width: width,
    highlighter: highlighter,
    pressures: pressures == null ? null : [...pressures!, pressure ?? 0.5],
  );

  /// Whether [point] is within [radius] of this line.
  bool hits(Offset point, double radius) {
    final reach = radius + width / 2;
    if (points.length == 1) return (points.first - point).distance <= reach;
    for (var i = 1; i < points.length; i++) {
      if (_distanceToSegment(point, points[i - 1], points[i]) <= reach) return true;
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  // Compact: coordinates to a tenth of a point, as one flat list.
  Map<String, Object?> toJson() => {
    'c': color.toARGB32(),
    'w': width,
    if (highlighter) 'h': true,
    'p': [
      for (final o in points) ...[(o.dx * 10).round(), (o.dy * 10).round()],
    ],
    if (pressures != null) 'f': [for (final f in pressures!) (f * 100).round()],
  };

  static Stroke? fromJson(Object? json) {
    if (json is! Map) return null;
    final flat = json['p'];
    if (flat is! List || flat.length < 2) return null;
    final points = <Offset>[
      for (var i = 0; i + 1 < flat.length; i += 2)
        Offset((flat[i] as num) / 10, (flat[i + 1] as num) / 10),
    ];
    final f = json['f'];
    return Stroke(
      points: points,
      color: Color((json['c'] as num?)?.toInt() ?? 0xFF000000),
      width: (json['w'] as num?)?.toDouble() ?? 3,
      highlighter: json['h'] == true,
      pressures: f is List && f.length == points.length
          ? [for (final v in f) (v as num) / 100]
          : null,
    );
  }
}

/// A drawing: its strokes on a canvas of [size]. Kept (gzipped JSON, as an
/// encrypted attachment) next to the picture made from it, so it can be
/// edited later.
@immutable
class Drawing {
  const Drawing({required this.size, this.strokes = const []});

  final Size size;
  final List<Stroke> strokes;

  bool get isEmpty => strokes.isEmpty;

  static const mimeType = 'application/vnd.zerotrust.drawing+json';
  static const fileName = 'drawing.json.gz';

  Uint8List encode() => Uint8List.fromList(
    gzip.encode(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'w': size.width,
          'h': size.height,
          's': [for (final s in strokes) s.toJson()],
        }),
      ),
    ),
  );

  static Drawing? decode(Uint8List bytes) {
    try {
      final json = jsonDecode(utf8.decode(gzip.decode(bytes)));
      if (json is! Map) return null;
      final strokes = json['s'];
      return Drawing(
        size: Size((json['w'] as num).toDouble(), (json['h'] as num).toDouble()),
        strokes: [
          if (strokes is List)
            for (final s in strokes) ?Stroke.fromJson(s),
        ],
      );
    } on Object {
      return null;
    }
  }

  /// A PNG of the drawing on white paper, at [pixelRatio] times its size.
  Future<Uint8List> toPng({double pixelRatio = 2}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    paintStrokes(canvas, strokes);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}

/// Paints [strokes] in order: highlighter lines are see-through and flat,
/// pen lines are round and follow a stylus's pressure.
void paintStrokes(Canvas canvas, List<Stroke> strokes) {
  for (final s in strokes) {
    final paint = Paint()
      ..color = s.highlighter ? s.color.withValues(alpha: 0.35) : s.color
      ..style = PaintingStyle.stroke
      ..strokeCap = s.highlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = s.highlighter ? BlendMode.multiply : BlendMode.srcOver;
    if (s.points.length == 1) {
      canvas.drawCircle(s.points.first, s.width / 2, Paint()..color = paint.color);
      continue;
    }
    final pressures = s.pressures;
    if (pressures == null || s.highlighter) {
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (var i = 1; i < s.points.length; i++) {
        // Smooth through midpoints so fast strokes don't look jagged.
        final a = s.points[i - 1];
        final b = s.points[i];
        final mid = (a + b) / 2;
        path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
      }
      path.lineTo(s.points.last.dx, s.points.last.dy);
      canvas.drawPath(path, paint..strokeWidth = s.width);
    } else {
      for (var i = 1; i < s.points.length; i++) {
        final pressure = (pressures[i - 1] + pressures[i]) / 2;
        paint.strokeWidth = s.width * (0.4 + 1.2 * pressure);
        canvas.drawLine(s.points[i - 1], s.points[i], paint);
      }
    }
  }
}
