import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Avatar slug → image asset
const Map<String, String> kPersonaAvatars = {
  'hard_hat': 'assets/images/avatars/hard_hat.png',
  'wrench': 'assets/images/avatars/wrench.png',
  'blueprint': 'assets/images/avatars/blueprint.png',
  'crane': 'assets/images/avatars/crane.png',
  'robot': 'assets/images/avatars/robot.png',
  'clipboard': 'assets/images/avatars/clipboard.png',
  'lightning': 'assets/images/avatars/lightning.png',
  'compass': 'assets/images/avatars/compass.png',
};

/// Backward-compatible avatar slug -> emoji map for screens that still render text avatars.
const Map<String, String> kPersonaAvatarEmojis = {
  'hard_hat': '👷',
  'wrench': '🔧',
  'blueprint': '📐',
  'crane': '🏗️',
  'robot': '🤖',
  'clipboard': '📋',
  'lightning': '⚡',
  'compass': '🧭',
};

/// Personality preset definitions
class PersonaStyle {
  final String slug;
  final String title;
  final String description;
  final String sampleLine;

  const PersonaStyle({
    required this.slug,
    required this.title,
    required this.description,
    required this.sampleLine,
  });
}

const List<PersonaStyle> kPersonaStyles = [
  PersonaStyle(
    slug: 'mentor',
    title: 'The Experienced Mentor',
    description: 'Calm authority, practical field examples, actionable advice.',
    sampleLine:
        'Based on my experience with similar jobs, I\'d start by addressing the structural concerns first.',
  ),
  PersonaStyle(
    slug: 'analyst',
    title: 'The Detail Analyst',
    description: 'Structured, numbered risks, quantified estimates.',
    sampleLine:
        '1. Risk: 15% cost overrun likely. 2. Timeline: +3 days. Recommendation: add contingency buffer.',
  ),
  PersonaStyle(
    slug: 'coach',
    title: 'The Motivating Coach',
    description: 'Upbeat, solutions-focused, always ends with a next step.',
    sampleLine:
        'Great progress! You\'re 70% there. Next step: schedule the final inspection for this Friday.',
  ),
  PersonaStyle(
    slug: 'concise',
    title: 'The No-Nonsense Foreman',
    description: 'Fewest words possible. Skips pleasantries.',
    sampleLine: 'Fix the moisture issue. Order drywall Thursday.',
  ),
  PersonaStyle(
    slug: 'expert',
    title: 'The Technical Expert',
    description: 'Cites codes/standards, explains the "why".',
    sampleLine:
        'Per IRC R302.1, fire-rated assemblies are required here. Here\'s why that matters...',
  ),
  PersonaStyle(
    slug: 'custom',
    title: 'Custom Personality',
    description: 'Write your own personality description.',
    sampleLine: '',
  ),
];

/// Returns thinking messages appropriate for the given persona style slug.
List<String> getPersonaThinkingMessages(String? style) {
  switch (style) {
    case 'mentor':
      return [
        'Drawing on years of field experience...',
        'Considering the best approach for your situation...',
        'Thinking through the practical implications...',
        'Reviewing best practices...',
      ];
    case 'analyst':
      return [
        'Running the numbers...',
        'Calculating risk factors...',
        'Quantifying estimates...',
        'Structuring the analysis...',
      ];
    case 'coach':
      return [
        'Putting together a great plan for you!',
        'Finding the best path forward...',
        'Building on your momentum...',
        'Identifying your next win...',
      ];
    case 'concise':
      return [
        'Working...',
        'Processing...',
        'Almost done...',
      ];
    case 'expert':
      return [
        'Consulting applicable codes and standards...',
        'Checking technical specifications...',
        'Verifying compliance requirements...',
        'Cross-referencing industry standards...',
      ];
    default:
      return [
        'Analyzing your request...',
        'Generating recommendations...',
        'Almost there...',
      ];
  }
}

/// Returns a time-aware greeting for the AI persona.
String getPersonaGreeting(String? name) {
  final hour = DateTime.now().hour;
  String timeOfDay;
  if (hour < 12) {
    timeOfDay = 'Good morning';
  } else if (hour < 17) {
    timeOfDay = 'Good afternoon';
  } else {
    timeOfDay = 'Good evening';
  }

  if (name != null && name.isNotEmpty) {
    return '$timeOfDay! I\'m $name. Ready to tackle today\'s work.';
  }
  return '$timeOfDay! I\'m your AI assistant. How can I help today?';
}

/// Reusable avatar chip row for persona selection.
class PersonaAvatarPicker extends StatelessWidget {
  final String selectedAvatar;
  final ValueChanged<String> onAvatarSelected;
  final bool isLightBackground;

  const PersonaAvatarPicker({
    super.key,
    required this.selectedAvatar,
    required this.onAvatarSelected,
    this.isLightBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kPersonaAvatars.entries.map((entry) {
        final isSelected = selectedAvatar == entry.key;
        return GestureDetector(
          onTap: () => onAvatarSelected(entry.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : (isLightBackground
                        ? Colors.white.withOpacity(0.15)
                        : AppColors.surfaceAlt),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : (isLightBackground
                          ? Colors.white.withOpacity(0.3)
                          : AppColors.cardBorder),
                width: 2,
              ),
            ),
            child: Center(
              child: ClipOval(
                child: Image.asset(
                  entry.value,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Personality style card grid for persona selection.
class PersonaStylePicker extends StatelessWidget {
  final String selectedStyle;
  final ValueChanged<String> onStyleSelected;
  final bool isLightBackground;

  const PersonaStylePicker({
    super.key,
    required this.selectedStyle,
    required this.onStyleSelected,
    this.isLightBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: kPersonaStyles.map((style) {
        final isSelected = selectedStyle == style.slug;
        final textColor = isLightBackground
            ? (isSelected ? const Color(0xFF0d4f8b) : Colors.white)
            : (isSelected
                  ? Theme.of(context).colorScheme.primary
                  : AppColors.textPrimary);
        final secondaryColor = isLightBackground
            ? (isSelected ? AppColors.textSecondary : Colors.white70)
            : AppColors.textSecondary;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onStyleSelected(style.slug),
            borderRadius: BorderRadius.circular(AppRadius.r12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isLightBackground
                          ? Colors.white
                          : Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.08))
                    : (isLightBackground
                          ? Colors.white.withOpacity(0.1)
                          : AppColors.surfaceAlt),
                borderRadius: BorderRadius.circular(AppRadius.r12),
                border: Border.all(
                  color: isSelected
                      ? (isLightBackground
                            ? Colors.white
                            : Theme.of(context).colorScheme.primary)
                      : (isLightBackground
                            ? Colors.white.withOpacity(0.2)
                            : AppColors.cardBorder),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          style.title,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          style.description,
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: isLightBackground
                          ? const Color(0xFF0d4f8b)
                          : Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Preview bubble showing persona name, avatar, and sample message.
class PersonaPreviewBubble extends StatelessWidget {
  final String avatarSlug;
  final String? name;
  final String selectedStyle;
  final bool isLightBackground;

  const PersonaPreviewBubble({
    super.key,
    required this.avatarSlug,
    this.name,
    required this.selectedStyle,
    this.isLightBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final assetPath = kPersonaAvatars[avatarSlug] ?? 'assets/images/avatars/robot.png';
    final displayName =
        name?.isNotEmpty == true ? name! : 'AI Assistant';
    final style = kPersonaStyles.firstWhere(
      (s) => s.slug == selectedStyle,
      orElse: () => kPersonaStyles.first,
    );
    final sampleLine =
        style.sampleLine.isNotEmpty ? style.sampleLine : 'How can I help?';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: isLightBackground
            ? Colors.white.withOpacity(0.15)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.r16),
        border: Border.all(
          color: isLightBackground
              ? Colors.white.withOpacity(0.3)
              : AppColors.cardBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLightBackground
                  ? Colors.white.withOpacity(0.2)
                  : Theme.of(context).colorScheme.primary.withValues(
                    alpha: 0.1,
                  ),
            ),
            child: Center(
              child: ClipOval(
                child: Image.asset(
                  assetPath,
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isLightBackground ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sampleLine,
                  style: TextStyle(
                    fontSize: 13,
                    color: isLightBackground ? Colors.white.withOpacity(0.85) : AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
