enum ExportFormat {
  markdown('Markdown', 'md'),
  pdf('PDF', 'pdf'),
  json('JSON', 'json');

  const ExportFormat(this.label, this.fileExtension);

  final String label;
  final String fileExtension;
}
