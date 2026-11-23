import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// Renders pages of a PDF on this phone (Android's own PdfRenderer, see
/// `PdfPages.kt`). Overridable in tests.
abstract interface class PdfPageSource {
  Future<int> open(Uint8List pdf);
  Future<Uint8List> page(int index, {required int width});
  Future<void> close();
}

/// Makes the page renderer for each PDF opened, or null where Notes can't
/// show PDFs itself (they then open in another app). Overridden in tests.
final pdfPageSourceProvider = Provider<PdfPageSource Function()?>(
  (ref) => AndroidPdfPageSource.supported ? AndroidPdfPageSource.new : null,
);

/// The phone's renderer. The decrypted PDF exists as a file in the app's
/// private cache only while it is shown.
class AndroidPdfPageSource implements PdfPageSource {
  static const _channel = MethodChannel('dev.sagron.zerotrustnotes/pdf');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  File? _file;
  bool _closed = false;

  @override
  Future<int> open(Uint8List pdf) async {
    if (_closed) throw StateError('Closed');
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'pdf_view'));
    await dir.create(recursive: true);
    final name = List.generate(16, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
    final file = File(p.join(dir.path, '$name.pdf'));
    _file = file;
    await file.writeAsBytes(pdf, flush: true);
    // Closed while writing: close found no file yet, so delete it here.
    if (_closed) {
      await _delete(file);
      throw StateError('Closed');
    }
    return (await _channel.invokeMethod<int>('pageCount', {'path': file.path})) ?? 0;
  }

  @override
  Future<Uint8List> page(int index, {required int width}) async {
    final file = _file;
    if (file == null) throw StateError('Not open');
    final png = await _channel.invokeMethod<Uint8List>('renderPage', {
      'path': file.path,
      'index': index,
      'width': width,
    });
    if (png == null) throw StateError('No page');
    return png;
  }

  @override
  Future<void> close() async {
    _closed = true;
    final file = _file;
    _file = null;
    if (file != null) await _delete(file);
  }

  static Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on Object {
      // Already gone; the cache folder is cleared with the app's cache.
    }
  }
}

/// A PDF attached to a note, page by page, with pinch to zoom.
class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({
    super.key,
    required this.title,
    required this.load,
    this.source,
    this.actions = const [],
  });

  final String title;

  /// The decrypted PDF.
  final Future<Uint8List> Function() load;
  final PdfPageSource? source;
  final List<Widget> actions;

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late final PdfPageSource _source = widget.source ?? AndroidPdfPageSource();
  int? _pages;
  bool _failed = false;
  final Map<int, Future<Uint8List>> _rendered = {};

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final pdf = await widget.load();
      // Closed while decrypting: no plain copy is written at all.
      if (!mounted) return;
      final count = await _source.open(pdf);
      if (!mounted) {
        // Closed while it opened: the copy dispose couldn't see goes now.
        await _source.close();
        return;
      }
      setState(() => _pages = count);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _source.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = _pages;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: widget.actions),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      body: _failed
          ? Center(child: Text(l10n.cantOpenPdf, textAlign: TextAlign.center))
          : pages == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(200, 2400);
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: ListView.builder(
                    key: const Key('pdf_pages'),
                    padding: const EdgeInsets.all(8),
                    itemCount: pages,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Semantics(
                        label: l10n.pdfPageNofM(index + 1, pages),
                        image: true,
                        child: FutureBuilder<Uint8List>(
                          future: _rendered[index] ??= _source.page(index, width: width),
                          builder: (context, snapshot) => switch (snapshot) {
                            AsyncSnapshot(:final data?) => Image.memory(
                              data,
                              key: ValueKey('pdf_page_$index'),
                              fit: BoxFit.fitWidth,
                              gaplessPlayback: true,
                            ),
                            AsyncSnapshot(hasError: true) => SizedBox(
                              height: 200,
                              child: Center(child: Text(l10n.cantOpenPdf)),
                            ),
                            _ => const AspectRatio(
                              aspectRatio: 1 / 1.414,
                              child: ColoredBox(
                                color: Colors.white,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            ),
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
