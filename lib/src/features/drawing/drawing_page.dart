import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

import 'drawing.dart';

/// What [DrawingPage] hands back: the strokes (to edit again later) and the
/// picture made from them.
class DrawingResult {
  const DrawingResult({required this.drawing, required this.png});
  final Drawing drawing;
  final Uint8List png;
}

/// Draw or write by hand: pen (follows a stylus's pressure), highlighter
/// and eraser, six colours, three thicknesses, undo and redo. Once a stylus
/// touches the page, fingers no longer draw, so a resting palm leaves no
/// marks. Pops a [DrawingResult], or null when nothing changed.
class DrawingPage extends StatefulWidget {
  const DrawingPage({super.key, this.initial});

  final Drawing? initial;

  static Future<DrawingResult?> open(BuildContext context, {Drawing? initial}) =>
      Navigator.of(context).push<DrawingResult>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => DrawingPage(initial: initial)),
      );

  @override
  State<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage> {
  static const colors = [
    Color(0xFF1F1F1F),
    Color(0xFFD32F2F),
    Color(0xFF1976D2),
    Color(0xFF388E3C),
    Color(0xFFFBC02D),
    Color(0xFF7B1FA2),
  ];
  static const widths = [2.0, 4.0, 8.0];

  late List<Stroke> _strokes = [...?widget.initial?.strokes];
  final List<List<Stroke>> _undo = [];
  final List<List<Stroke>> _redo = [];
  Stroke? _current;
  DrawingTool _tool = DrawingTool.pen;
  Color _color = colors.first;
  double _width = widths[1];
  bool _stylusSeen = false;
  bool _saving = false;
  Size? _size;
  int? _pointer;

  bool get _changed => _undo.isNotEmpty;

  void _push(List<Stroke> next) {
    _undo.add(_strokes);
    _redo.clear();
    _strokes = next;
  }

  bool _accepts(PointerEvent e) {
    if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus) {
      _stylusSeen = true;
      return true;
    }
    return !_stylusSeen;
  }

  Offset _toDrawing(Offset local, double scale) => local / scale;

  void _down(PointerDownEvent e, double scale) {
    if (_pointer != null || !_accepts(e)) return;
    _pointer = e.pointer;
    final point = _toDrawing(e.localPosition, scale);
    final eraser = _tool == DrawingTool.eraser || e.kind == PointerDeviceKind.invertedStylus;
    if (eraser) {
      _undo.add(_strokes);
      _redo.clear();
      _erase(point);
      return;
    }
    final stylus = e.kind == PointerDeviceKind.stylus;
    setState(
      () => _current = Stroke(
        points: [point],
        color: _color,
        width: _tool == DrawingTool.highlighter ? _width * 4 : _width,
        highlighter: _tool == DrawingTool.highlighter,
        pressures: stylus ? [_pressure(e)] : null,
      ),
    );
  }

  double _pressure(PointerEvent e) {
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _move(PointerMoveEvent e, double scale) {
    if (e.pointer != _pointer) return;
    final point = _toDrawing(e.localPosition, scale);
    if (_current == null) {
      _erase(point);
      return;
    }
    if ((point - _current!.points.last).distance < 0.8) return;
    setState(() => _current = _current!.extended(point, _pressure(e)));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final stroke = _current;
    if (stroke == null) {
      // An eraser touch that removed nothing isn't a change to undo.
      if (_undo.isNotEmpty && identical(_undo.last, _strokes)) _undo.removeLast();
      setState(() {});
      return;
    }
    setState(() {
      _current = null;
      _push([..._strokes, stroke]);
    });
  }

  void _erase(Offset point) {
    final left = [
      for (final s in _strokes)
        if (!s.hits(point, 10)) s,
    ];
    if (left.length != _strokes.length) setState(() => _strokes = left);
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_strokes);
      _strokes = _undo.removeLast();
    });
  }

  void _redoLast() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_strokes);
      _strokes = _redo.removeLast();
    });
  }

  void _clear() {
    if (_strokes.isEmpty) return;
    setState(() => _push(const []));
  }

  Future<void> _save() async {
    final size = widget.initial?.size ?? _size;
    if (!_changed || size == null) {
      Navigator.of(context).pop();
      return;
    }
    if (_strokes.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.drawSomethingFirst),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final drawing = Drawing(size: size, strokes: _strokes);
    final png = await drawing.toPng();
    if (!mounted) return;
    Navigator.of(context).pop(DrawingResult(drawing: drawing, png: png));
  }

  Future<bool> _confirmDiscard() async {
    if (!_changed) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.discardDrawingQ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.keepDrawing),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.discard),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  String _colorName(BuildContext context, int i) {
    final l10n = context.l10n;
    return [
      l10n.colorBlack,
      l10n.colorRed,
      l10n.colorBlue,
      l10n.colorGreen,
      l10n.colorYellow,
      l10n.colorPurple,
    ][i];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.initial == null ? l10n.newDrawing : l10n.editDrawing),
          actions: [
            IconButton(
              tooltip: l10n.undo,
              icon: const Icon(Icons.undo),
              onPressed: _undo.isEmpty ? null : _undoLast,
            ),
            IconButton(
              tooltip: l10n.redo,
              icon: const Icon(Icons.redo),
              onPressed: _redo.isEmpty ? null : _redoLast,
            ),
            IconButton(
              tooltip: l10n.clearDrawing,
              icon: const Icon(Icons.layers_clear_outlined),
              onPressed: _strokes.isEmpty ? null : _clear,
            ),
            IconButton(
              key: const Key('drawing_save'),
              tooltip: l10n.saveDrawing,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = widget.initial?.size ?? (_size ??= constraints.biggest);
                      final scale = (constraints.maxWidth / size.width).clamp(
                        0.0,
                        constraints.maxHeight / size.height,
                      );
                      return Center(
                        child: SizedBox(
                          width: size.width * scale,
                          height: size.height * scale,
                          child: Semantics(
                            label: l10n.drawingCanvas,
                            child: Listener(
                              key: const Key('drawing_canvas'),
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (e) => _down(e, scale),
                              onPointerMove: (e) => _move(e, scale),
                              onPointerUp: _up,
                              onPointerCancel: _up,
                              child: ClipRect(
                                child: CustomPaint(
                                  painter: _CanvasPainter(
                                    strokes: _strokes,
                                    current: _current,
                                    scale: scale,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              _toolbar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    Widget tool(DrawingTool t, IconData icon, String label) => IconButton(
      key: Key('drawing_tool_${t.name}'),
      tooltip: label,
      isSelected: _tool == t,
      style: IconButton.styleFrom(backgroundColor: _tool == t ? scheme.secondaryContainer : null),
      icon: Icon(icon),
      onPressed: () => setState(() => _tool = t),
    );
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                tool(DrawingTool.pen, Icons.edit_outlined, l10n.pen),
                tool(DrawingTool.highlighter, Icons.border_color_outlined, l10n.highlighter),
                tool(DrawingTool.eraser, Icons.auto_fix_normal_outlined, l10n.eraser),
                const SizedBox(height: 32, child: VerticalDivider()),
                for (final w in widths)
                  IconButton(
                    tooltip: l10n.thickness(w.round()),
                    isSelected: _width == w,
                    style: IconButton.styleFrom(
                      backgroundColor: _width == w ? scheme.secondaryContainer : null,
                    ),
                    icon: Container(
                      width: w * 2 + 4,
                      height: w * 2 + 4,
                      decoration: BoxDecoration(color: scheme.onSurface, shape: BoxShape.circle),
                    ),
                    onPressed: () => setState(() => _width = w),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < colors.length; i++)
                  Semantics(
                    selected: _color == colors[i],
                    button: true,
                    label: _colorName(context, i),
                    excludeSemantics: true,
                    child: InkResponse(
                      key: Key('drawing_color_$i'),
                      onTap: () => setState(() {
                        _color = colors[i];
                        if (_tool == DrawingTool.eraser) _tool = DrawingTool.pen;
                      }),
                      radius: 24,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colors[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == colors[i] ? scheme.primary : scheme.outlineVariant,
                              width: _color == colors[i] ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({required this.strokes, required this.current, required this.scale});

  final List<Stroke> strokes;
  final Stroke? current;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    canvas.save();
    canvas.scale(scale);
    paintStrokes(canvas, [...strokes, ?current]);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.strokes != strokes || old.current != current || old.scale != scale;
}
