import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// A widget that renders text with @mentions highlighted
/// 
/// Parses text content and renders @mentions with distinct styling.
/// Mentions are identified by the pattern @username (word characters after @).
class MentionText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? mentionStyle;
  final ValueChanged<String>? onMentionTap;

  const MentionText({
    super.key,
    required this.text,
    this.style,
    this.mentionStyle,
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = style ?? const TextStyle(fontSize: 13);
    final defaultMentionStyle = mentionStyle ?? TextStyle(
      fontSize: 13,
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
    );

    final spans = _parseTextWithMentions(text, defaultStyle, defaultMentionStyle);

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  List<InlineSpan> _parseTextWithMentions(
    String text, 
    TextStyle defaultStyle, 
    TextStyle mentionStyle,
  ) {
    final List<InlineSpan> spans = [];
    
    // Regex to match @mentions (@ followed by word characters, spaces allowed in names)
    // This matches @Name or @"Name with spaces" or @Name_Name patterns
    final mentionRegex = RegExp(r'@([\w\s]+?)(?=\s@|\s[^@]|$|\n|[.,!?;:])');
    
    int lastEnd = 0;
    
    for (final match in mentionRegex.allMatches(text)) {
      // Add text before the mention
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: defaultStyle,
        ));
      }
      
      // Add the mention with special styling
      final mentionText = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: onMentionTap != null 
                ? () => onMentionTap!(match.group(1)!) 
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
              decoration: BoxDecoration(
                color: mentionStyle.backgroundColor,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                mentionText,
                style: mentionStyle.copyWith(backgroundColor: Colors.transparent),
              ),
            ),
          ),
        ),
      );
      
      lastEnd = match.end;
    }
    
    // Add remaining text after the last mention
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: defaultStyle,
      ));
    }
    
    // If no mentions were found, return the original text
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: defaultStyle));
    }
    
    return spans;
  }
}
