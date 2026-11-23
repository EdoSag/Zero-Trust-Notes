enum ExportFormat {
  markdown('Markdown', 'md'),
  /// One Markdown file per note, with pictures and files, zipped (N-7).
  markdownFolder('Markdown folder', 'zip'),
  pdf('PDF', 'pdf'),
  json('JSON', 'json');

  const ExportFormat(this.label, this.fileExtension);

  final String label;
  final String fileExtension;
}
