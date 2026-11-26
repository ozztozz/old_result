import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// `**kalın**` markdown vurgularını ve yapılandırılmış başlık/madde formatını
/// ek paket gerektirmeden şık biçimde render eden widget.
class FormattedSummaryView extends StatelessWidget {
  const FormattedSummaryView({
    super.key,
    required this.text,
    required this.baseStyle,
    this.headingStyle,
    this.boldColor,
    this.bulletColor,
    this.sectionBackground,
  });

  final String text;
  final TextStyle baseStyle;
  final TextStyle? headingStyle;
  final Color? boldColor;
  final Color? bulletColor;
  final Color? sectionBackground;

  static const _knownHeadings = <String>{
    'temel seçme müsabakası ve derece kriterleri',
    'kadro kotası ve tamamlama / eleme kuralları',
    'müsabakaya katılım kuralları',
    'antrenör seçim kriterleri',
  };

  static bool _isHeadingLine(String line, String? nextLine) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('#')) return true;

    final cleaned = trimmed
        .replaceAll('**', '')
        .replaceAll(RegExp(r'[:：]+$'), '')
        .trim()
        .toLowerCase();
    if (_knownHeadings.contains(cleaned)) return true;

    // Madde işareti değilse ve sonraki satır madde işaretiyle başlıyorsa başlık kabul et
    final isBullet = trimmed.startsWith('- ') || trimmed.startsWith('• ');
    final nextIsBullet = nextLine != null &&
        (nextLine.trimLeft().startsWith('- ') ||
            nextLine.trimLeft().startsWith('• '));
    if (!isBullet && nextIsBullet && trimmed.length <= 72) {
      return true;
    }
    return false;
  }

  /// Önizleme için `**` işaretlerini ve fazla boşlukları temizler.
  static String plainPreview(String raw) {
    return raw
        .replaceAll('**', '')
        .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  List<InlineSpan> _parseInlineBold(String input, TextStyle style) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*');
    var lastEnd = 0;

    for (final match in regex.allMatches(input)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: input.substring(lastEnd, match.start),
          style: style,
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: style.copyWith(
          fontWeight: FontWeight.w700,
          color: boldColor ?? style.color,
        ),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < input.length) {
      spans.add(TextSpan(
        text: input.substring(lastEnd),
        style: style,
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return const SizedBox.shrink();

    final effectiveHeadingStyle = headingStyle ??
        baseStyle.copyWith(
          fontSize: (baseStyle.fontSize ?? 14) + 0.5,
          fontWeight: FontWeight.w700,
          color: boldColor ?? baseStyle.color,
        );
    final accent = bulletColor ?? boldColor ?? baseStyle.color ?? Colors.teal;

    final widgets = <Widget>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final nextLine = i + 1 < lines.length ? lines[i + 1] : null;

      if (_isHeadingLine(line, nextLine)) {
        final headingText = line
            .replaceAll(RegExp(r'^#+\s*'), '')
            .replaceAll('**', '')
            .trim();
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 14, bottom: 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: sectionBackground ?? accent.withAlpha(18),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(color: accent, width: 3),
                ),
              ),
              child: Text(headingText, style: effectiveHeadingStyle),
            ),
          ),
        );
        continue;
      }

      if (line.startsWith('- ') || line.startsWith('• ')) {
        final content = line.substring(2).trim();
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: _parseInlineBold(content, baseStyle)),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            TextSpan(children: _parseInlineBold(line, baseStyle)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

/// Duyuru / Reglaman özetini okunabilir tam görünümde açan modal bottom sheet.
Future<void> showAnnouncementDetailSheet(
  BuildContext context, {
  required String title,
  String subtitle = '',
  List<String> tags = const [],
  required String summary,
  List<String> notes = const [],
  VoidCallback? onOpenPdf,
}) {
  final palette = context.palette;

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.94,
        expand: false,
        builder: (_, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.textMuted.withAlpha(90),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (tags.isNotEmpty) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: tags
                                  .map(
                                    (t) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.accent.withAlpha(24),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        t,
                                        style: TextStyle(
                                          fontFamily: AppTextStyles.fontFamily,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: palette.accent,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            title,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                              height: 1.25,
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 12.5,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: Icon(Icons.close_rounded, color: palette.textMuted),
                      tooltip: 'Kapat',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: palette.textMuted.withAlpha(40)),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (summary.isNotEmpty)
                          FormattedSummaryView(
                            text: summary,
                            baseStyle: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13.5,
                              height: 1.5,
                              color: palette.textPrimary,
                            ),
                            boldColor: palette.textPrimary,
                            bulletColor: palette.accent,
                          ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Önemli Notlar',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: palette.accent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...notes.map(
                            (n) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '• ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: palette.accent,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      n,
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 13,
                                        height: 1.4,
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (onOpenPdf != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onOpenPdf();
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Resmi PDF Belgesini Aç'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}
