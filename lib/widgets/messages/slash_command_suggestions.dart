import 'package:flutter/material.dart';
import '../../utils/slash_commands.dart';
import '../../theme/theme.dart';

/// A floating popup listing matching slash commands while the user types.
class SlashCommandSuggestions extends StatelessWidget {
  final List<SlashCommand> commands;
  final void Function(SlashCommand) onSelected;

  const SlashCommandSuggestions({
    super.key,
    required this.commands,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (commands.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: commands.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final c = commands[i];
            return InkWell(
              onTap: () => onSelected(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      c.kind == SlashCommandKind.channelAction
                          ? Icons.bolt
                          : Icons.text_fields,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                              children: [
                                const TextSpan(text: '/'),
                                TextSpan(text: c.name),
                                TextSpan(
                                  text: '  ${c.usage.replaceFirst("/${c.name}", "").trim()}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.normal,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            c.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
