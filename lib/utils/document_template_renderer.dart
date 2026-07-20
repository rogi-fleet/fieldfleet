class DocumentTemplateRenderer {
  const DocumentTemplateRenderer._();

  static String render(String template, Map<String, dynamic> context) {
    return _renderBlock(template, context);
  }

  static String _renderBlock(String template, Map<String, dynamic> context) {
    String rendered = template;

    // Process {{#if key}}...{{else}}...{{/if}} conditional blocks first.
    // The body must not contain another {{#if so that nested conditionals are
    // resolved innermost-first across do-while iterations.
    final ifRegex =
        RegExp(r'\{\{#if\s+([\w.]+)\}\}((?:(?!\{\{#if\b)[\s\S])*?)\{\{/if\}\}');
    bool replacedIf;
    do {
      replacedIf = false;
      rendered = rendered.replaceAllMapped(ifRegex, (match) {
        replacedIf = true;
        final key = match.group(1)!.trim();
        final body = match.group(2)!;
        final value = _getNestedValue(context, key);
        final truthy = _isTruthy(value);

        // Split on optional {{else}}
        final elseParts = body.split(RegExp(r'\{\{else\}\}'));
        final trueBlock = elseParts[0];
        final falseBlock = elseParts.length > 1 ? elseParts[1] : '';

        return truthy
            ? _renderBlock(trueBlock, context)
            : _renderBlock(falseBlock, context);
      });
    } while (replacedIf);

    // Render loop sections so loop tags are not consumed as placeholders.
    // Supports nested loops like categories -> items.
    final loopRegex = RegExp(r'\{\{#([\w.]+)\}\}([\s\S]*?)\{\{/\1\}\}');
    bool replacedLoop;
    do {
      replacedLoop = false;
      rendered = rendered.replaceAllMapped(loopRegex, (match) {
        replacedLoop = true;
        final key = match.group(1)!.trim();
        final content = match.group(2)!;
        final items = _getNestedValue(context, key);

        if (items is! List) {
          return '';
        }

        final buffer = StringBuffer();
        for (final item in items) {
          if (item is Map) {
            final localContext = <String, dynamic>{
              ...context,
              ...Map<String, dynamic>.from(item),
            };
            buffer.write(_renderBlock(content, localContext));
          } else {
            buffer.write(_renderBlock(content, context));
          }
        }
        return buffer.toString();
      });
    } while (replacedLoop);

    // Replace placeholders (excluding loop markers).
    final placeholderRegex = RegExp(r'\{\{(?![#/])([^}]+)\}\}');
    rendered = rendered.replaceAllMapped(placeholderRegex, (match) {
      final key = match.group(1)!.trim();
      final value = _getNestedValue(context, key);
      return _escapeMarkdown(value?.toString() ?? '');
    });

    return rendered;
  }

  /// Escape markdown-significant characters in substituted values so they
  /// render as literal text rather than injecting formatting.
  static String _escapeMarkdown(String value) {
    // Only escape leading chars that change block-level meaning, and inline
    // formatting markers. We preserve newlines and normal punctuation.
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('*', '\\*')
        .replaceAll('_', '\\_')
        .replaceAll('`', '\\`')
        .replaceAll('~', '\\~')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]');
  }

  /// A value is truthy if it is non-null, non-empty, non-zero, and not false.
  static bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  static dynamic _getNestedValue(Map<String, dynamic> context, String key) {
    final parts = key.split('.');
    dynamic current = context;

    for (final part in parts) {
      final cleanPart = part.trim();
      if (cleanPart.isEmpty) return null;

      if (current is Map<String, dynamic>) {
        current = current[cleanPart];
      } else if (current is Map) {
        current = current[cleanPart];
      } else if (current is List) {
        if (current.isEmpty) return null;

        final index = int.tryParse(cleanPart);
        if (index != null) {
          if (index < 0 || index >= current.length) return null;
          current = current[index];
          continue;
        }

        final first = current.first;
        if (first is Map<String, dynamic>) {
          current = first[cleanPart];
        } else if (first is Map) {
          current = first[cleanPart];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }

    return current;
  }
}
