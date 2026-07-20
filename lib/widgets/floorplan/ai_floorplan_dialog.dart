import 'package:flutter/material.dart';

/// Modal dialog that asks the user to describe a floorplan in
/// free-text. Returns the prompt on submit, or null on cancel.
Future<String?> showAiFloorplanDialog(
  BuildContext context, {
  String? initialPrompt,
  String confirmLabel = 'Generate',
  String? warning,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _AiFloorplanDialog(
      initialPrompt: initialPrompt,
      confirmLabel: confirmLabel,
      warning: warning,
    ),
  );
}

class _AiFloorplanDialog extends StatefulWidget {
  final String? initialPrompt;
  final String confirmLabel;
  final String? warning;

  const _AiFloorplanDialog({
    this.initialPrompt,
    this.confirmLabel = 'Generate',
    this.warning,
  });

  @override
  State<_AiFloorplanDialog> createState() => _AiFloorplanDialogState();
}

class _AiFloorplanDialogState extends State<_AiFloorplanDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialPrompt ?? '');

  static const _examples = [
    'Studio apartment, 6m × 7m, with a small bathroom',
    'Two-bedroom apartment with kitchen island, 8m × 12m',
    'L-shaped living room and open kitchen',
    'Small office with two private rooms and a meeting room',
    '2-bedroom 1-bath cottage, ~80 m²',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _useExample(String s) {
    setState(() => _ctrl.text = s);
    _ctrl.selection = TextSelection.collapsed(offset: s.length);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Describe your floorplan'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.warning != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_outlined, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(widget.warning!)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 4,
              minLines: 3,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText:
                    'e.g. "Two-bedroom apartment with kitchen island, 8m × 12m"',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try one of these:',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final ex in _examples)
                  ActionChip(
                    label: Text(
                      ex,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: () => _useExample(ex),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'AI floorplans are a starting point — you can edit anything '
              'afterwards. Generation typically takes 10–30 seconds.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.auto_awesome, size: 16),
          onPressed: () {
            final text = _ctrl.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(context, text);
          },
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
