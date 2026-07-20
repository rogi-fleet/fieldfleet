import 'package:flutter/material.dart';
import '../../theme/theme.dart';

const _kCommonEmojis = [
  '👍', '👎', '❤️', '😂', '😮', '😢', '🎉', '🔥', '👏', '🙏', '✅', '❌',
];

class ReactionPicker extends StatelessWidget {
  final void Function(String emoji) onEmojiSelected;

  const ReactionPicker({super.key, required this.onEmojiSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: _kCommonEmojis
            .map((emoji) => _EmojiButton(
                  emoji: emoji,
                  onTap: () => onEmojiSelected(emoji),
                ))
            .toList(),
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const _EmojiButton({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}

/// Show the reaction picker as an overlay near the given button
Future<String?> showReactionPicker(BuildContext context) async {
  return await showDialog<String>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => Dialog(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r12)),
      child: ReactionPicker(
        onEmojiSelected: (emoji) => Navigator.of(context).pop(emoji),
      ),
    ),
  );
}
