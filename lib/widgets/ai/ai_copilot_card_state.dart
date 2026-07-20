import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class AiCopilotCardStateView extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final String? error;
  final String disabledMessage;
  final String emptyMessage;
  final bool hasContent;
  final Widget content;

  const AiCopilotCardStateView({
    super.key,
    required this.enabled,
    required this.loading,
    required this.error,
    required this.disabledMessage,
    required this.emptyMessage,
    required this.hasContent,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Text(
        disabledMessage,
        style: const TextStyle(color: AppColors.textSecondary),
      );
    }

    if (loading) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    if (error != null) {
      return Text(
        error!,
        style: const TextStyle(color: AppColors.textSecondary),
      );
    }

    if (!hasContent) {
      return Text(
        emptyMessage,
        style: const TextStyle(color: AppColors.textSecondary),
      );
    }

    return content;
  }
}
