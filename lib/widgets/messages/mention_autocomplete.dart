import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Overlay shown when user types '@' in the compose area.
/// [participants] is a list of {id, name} maps.
class MentionAutocomplete extends StatelessWidget {
  final List<Map<String, String>> participants;
  final String query;
  final void Function(Map<String, String> participant) onSelected;

  const MentionAutocomplete({
    super.key,
    required this.participants,
    required this.query,
    required this.onSelected,
  });

  List<Map<String, String>> get _filtered {
    if (query.isEmpty) return participants;
    final lower = query.toLowerCase();
    return participants.where((p) {
      return (p['name'] ?? '').toLowerCase().contains(lower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final participant = filtered[index];
          final name = participant['name'] ?? '';
          final isRole = (participant['id'] ?? '').startsWith('__');
          return InkWell(
            onTap: () => onSelected(participant),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: isRole
                        ? Theme.of(context).colorScheme.tertiaryContainer
                        : Theme.of(context).colorScheme.primaryContainer,
                    child: isRole
                        ? Icon(
                            Icons.group,
                            size: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer,
                          )
                        : Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isRole ? '@$name' : name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isRole ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Parses typed text to detect an active @mention query.
/// Returns the query string after '@', or null if not in mention mode.
String? detectMentionQuery(String text, int cursorPosition) {
  if (cursorPosition <= 0) return null;
  final before = text.substring(0, cursorPosition);
  final lastAt = before.lastIndexOf('@');
  if (lastAt < 0) return null;

  // Ensure no space between @ and cursor
  final afterAt = before.substring(lastAt + 1);
  if (afterAt.contains(' ')) return null;

  return afterAt;
}

/// Replaces the active @mention with the selected participant name.
String applyMention(String text, int cursorPosition, String mentionName) {
  final lastAt = text.substring(0, cursorPosition).lastIndexOf('@');
  if (lastAt < 0) return text;
  final before = text.substring(0, lastAt);
  final after = text.substring(cursorPosition);
  return '$before@$mentionName $after';
}
