import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders message text as Slack-flavored markdown:
/// - **bold** / *italic* / `inline code` / ```code blocks```
/// - bulleted & numbered lists
/// - links auto-rendered (and tappable)
/// - special `@here` / `@channel` tokens highlighted
class MessageMarkdown extends StatelessWidget {
  final String content;
  final Color textColor;
  final Color codeBackground;
  final Color codeForeground;
  final Color linkColor;
  final Color mentionBackground;
  final Color mentionForeground;
  final double fontSize;
  final bool selectable;

  const MessageMarkdown({
    super.key,
    required this.content,
    required this.textColor,
    required this.codeBackground,
    required this.codeForeground,
    required this.linkColor,
    required this.mentionBackground,
    required this.mentionForeground,
    this.fontSize = 16,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    // Highlight @here and @channel by wrapping with bold + bg via markdown.
    // The markdown rendering doesn't natively know about chat mentions, so we
    // pre-process them into bold backticked-by-color spans (rendered as `code`
    // styling, which we color via the styleSheet's `code` style below).
    final processed = _highlightSpecialMentions(content);

    return MarkdownBody(
      data: processed,
      selectable: selectable,
      softLineBreak: true,
      onTapLink: (_, href, __) {
        if (href == null) return;
        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: textColor, fontSize: fontSize),
        a: TextStyle(
          color: linkColor,
          decoration: TextDecoration.underline,
          fontSize: fontSize,
        ),
        em: TextStyle(
          color: textColor,
          fontStyle: FontStyle.italic,
          fontSize: fontSize,
        ),
        strong: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
        code: TextStyle(
          color: codeForeground,
          backgroundColor: codeBackground,
          fontFamily: 'monospace',
          fontSize: fontSize - 1,
        ),
        codeblockDecoration: BoxDecoration(
          color: codeBackground,
          borderRadius: BorderRadius.circular(6),
        ),
        codeblockPadding: const EdgeInsets.all(10),
        blockquoteDecoration: BoxDecoration(
          color: codeBackground.withValues(alpha: 0.5),
          border: Border(left: BorderSide(color: linkColor, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        listBullet: TextStyle(color: textColor, fontSize: fontSize),
        h1: TextStyle(color: textColor, fontSize: fontSize + 6, fontWeight: FontWeight.bold),
        h2: TextStyle(color: textColor, fontSize: fontSize + 4, fontWeight: FontWeight.bold),
        h3: TextStyle(color: textColor, fontSize: fontSize + 2, fontWeight: FontWeight.bold),
        // Reduce default vertical padding so message bubbles stay tight.
        blockSpacing: 6,
      ),
    );
  }

  static final RegExp _specialMentionRegex =
      RegExp(r'(?<![A-Za-z0-9_])@(here|channel|everyone)\b', caseSensitive: false);

  /// Wrap @here/@channel/@everyone as bold backtick-styled tokens so they pop.
  String _highlightSpecialMentions(String input) {
    return input.replaceAllMapped(_specialMentionRegex, (m) {
      return '**`@${m.group(1)!.toLowerCase()}`**';
    });
  }
}
