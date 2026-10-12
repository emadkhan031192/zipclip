/// Renders the user-configurable file name template.
///
/// Tokens: `{author}`, `{title}`, `{date}` (yyyyMMdd-HHmmss), `{quality}`.
/// Unknown tokens are left untouched. The result is sanitized for Android
/// file systems and capped at 120 characters (without extension).
abstract final class FileNameTemplate {
  static const String defaultTemplate = '{author}_{title}_{date}';

  static String render(
    String template, {
    required String author,
    required String title,
    required DateTime date,
    required String quality,
  }) {
    final dateStr = _formatDate(date);
    var out = template
        .replaceAll('{author}', author)
        .replaceAll('{title}', title)
        .replaceAll('{date}', dateStr)
        .replaceAll('{quality}', quality);
    out = _sanitize(out);
    if (out.isEmpty) out = 'zipclip_$dateStr';
    if (out.length > 120) out = out.substring(0, 120).trim();
    return out;
  }

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}-'
        '${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }

  static final _illegal = RegExp(r'[\\/:*?"<>|]');

  static String _sanitize(String s) {
    var out = s.replaceAll(_illegal, '');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Avoid names that are only dots, and trailing dots/spaces (Windows-hostile).
    out = out.replaceAll(RegExp(r'^[.]+'), '');
    out = out.replaceAll(RegExp(r'[. ]+$'), '');
    return out;
  }
}
