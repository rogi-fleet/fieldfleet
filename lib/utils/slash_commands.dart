/// Slack-style slash commands for the message composer.
///
/// Some commands are pure text-substitution (e.g. `/shrug`, `/me`), executed
/// before the message is sent. Others are server-side ("action" commands like
/// `/topic`, `/rename`, `/leave`, `/invite`) that are dispatched separately.
library;

class SlashCommand {
  final String name;
  final String description;
  final String usage;
  final SlashCommandKind kind;

  const SlashCommand({
    required this.name,
    required this.description,
    required this.usage,
    required this.kind,
  });
}

enum SlashCommandKind {
  /// Replaces the input content before sending (no server side-effect).
  textSubstitution,

  /// Server-side action; do not send the message.
  channelAction,
}

const List<SlashCommand> kSlashCommands = [
  SlashCommand(
    name: 'shrug',
    description: 'Append ¯\\_(ツ)_/¯ to your message',
    usage: '/shrug [message]',
    kind: SlashCommandKind.textSubstitution,
  ),
  SlashCommand(
    name: 'tableflip',
    description: 'Append (╯°□°)╯︵ ┻━┻',
    usage: '/tableflip [message]',
    kind: SlashCommandKind.textSubstitution,
  ),
  SlashCommand(
    name: 'unflip',
    description: 'Append ┬─┬ ノ( ゜-゜ノ)',
    usage: '/unflip [message]',
    kind: SlashCommandKind.textSubstitution,
  ),
  SlashCommand(
    name: 'me',
    description: 'Display an action message in italics',
    usage: '/me <action>',
    kind: SlashCommandKind.textSubstitution,
  ),
  SlashCommand(
    name: 'topic',
    description: 'Set the channel topic',
    usage: '/topic <new topic>',
    kind: SlashCommandKind.channelAction,
  ),
  SlashCommand(
    name: 'rename',
    description: 'Rename the current channel',
    usage: '/rename <new-name>',
    kind: SlashCommandKind.channelAction,
  ),
  SlashCommand(
    name: 'leave',
    description: 'Leave this channel',
    usage: '/leave',
    kind: SlashCommandKind.channelAction,
  ),
];

/// Result of parsing user input. If [command] is null, the message should be
/// sent as-is. If [command] is set:
///   - [transformedText] is the text to send (when kind == textSubstitution),
///   - [argument] is the raw argument after the command (when kind == channelAction).
class SlashCommandResult {
  final SlashCommand? command;
  final String transformedText;
  final String argument;

  const SlashCommandResult({
    this.command,
    this.transformedText = '',
    this.argument = '',
  });

  bool get isCommand => command != null;
  bool get isAction =>
      command != null && command!.kind == SlashCommandKind.channelAction;
}

/// Parse user-typed input. Returns a result describing what to do.
SlashCommandResult parseSlashCommand(String input) {
  final trimmed = input.trimLeft();
  if (!trimmed.startsWith('/')) {
    return SlashCommandResult(transformedText: input);
  }
  final spaceIdx = trimmed.indexOf(' ');
  final name = (spaceIdx == -1 ? trimmed.substring(1) : trimmed.substring(1, spaceIdx))
      .toLowerCase();
  final arg = spaceIdx == -1 ? '' : trimmed.substring(spaceIdx + 1).trim();
  final command = kSlashCommands.where((c) => c.name == name).cast<SlashCommand?>().firstWhere(
        (_) => true,
        orElse: () => null,
      );
  if (command == null) {
    return SlashCommandResult(transformedText: input);
  }

  switch (command.name) {
    case 'shrug':
      final tail = arg.isEmpty ? '' : '$arg ';
      return SlashCommandResult(
        command: command,
        transformedText: '$tail¯\\_(ツ)_/¯',
      );
    case 'tableflip':
      final tail = arg.isEmpty ? '' : '$arg ';
      return SlashCommandResult(
        command: command,
        transformedText: '$tail(╯°□°)╯︵ ┻━┻',
      );
    case 'unflip':
      final tail = arg.isEmpty ? '' : '$arg ';
      return SlashCommandResult(
        command: command,
        transformedText: '$tail┬─┬ ノ( ゜-゜ノ)',
      );
    case 'me':
      // Render as italic action via markdown
      return SlashCommandResult(
        command: command,
        transformedText: arg.isEmpty ? '' : '_${arg}_',
      );
    default:
      return SlashCommandResult(command: command, argument: arg);
  }
}

/// Suggestions matching a partial command (e.g. user typed "/to").
List<SlashCommand> suggestSlashCommands(String input) {
  final trimmed = input.trimLeft();
  if (!trimmed.startsWith('/')) return const [];
  // Only suggest while the user is still typing the command name (no space yet).
  if (trimmed.contains(' ')) return const [];
  final partial = trimmed.substring(1).toLowerCase();
  return kSlashCommands
      .where((c) => partial.isEmpty || c.name.startsWith(partial))
      .toList();
}
