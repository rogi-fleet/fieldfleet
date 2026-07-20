import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Step metadata for AI wizard steps
class AiStepConfig {
  final int number;
  final String title;
  final String subtitle;
  final IconData icon;

  const AiStepConfig({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

/// Wizard header with step indicator bar + title/subtitle
class AiWizardHeader extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final List<AiStepConfig> steps;
  final Color? primaryColor;

  const AiWizardHeader({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.steps,
    this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = primaryColor ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        children: [
          // Step indicator
          Row(
            children: List.generate(totalSteps * 2 - 1, (index) {
              if (index.isOdd) {
                final stepIndex = index ~/ 2;
                final isCompleted = stepIndex < currentStep;
                return Expanded(
                  child: Container(
                    height: 2,
                    color: isCompleted ? color : AppColors.cardBorder,
                  ),
                );
              } else {
                final stepIndex = index ~/ 2;
                final isCompleted = stepIndex < currentStep;
                final isCurrent = stepIndex == currentStep;
                return AiWizardStepCircle(
                  number: stepIndex + 1,
                  isCompleted: isCompleted,
                  isCurrent: isCurrent,
                  primaryColor: color,
                );
              }
            }),
          ),
          const SizedBox(height: 20),
          // Step title and subtitle
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(steps[currentStep].icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${currentStep + 1}. ${steps[currentStep].title}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      steps[currentStep].subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Individual step circle in the step indicator
class AiWizardStepCircle extends StatelessWidget {
  final int number;
  final bool isCompleted;
  final bool isCurrent;
  final Color primaryColor;

  const AiWizardStepCircle({
    super.key,
    required this.number,
    required this.isCompleted,
    required this.isCurrent,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = isCompleted || isCurrent;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? primaryColor : Colors.transparent,
        border: Border.all(
          color: isActive ? primaryColor : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          width: 2,
        ),
      ),
      child: Center(
        child: isCompleted
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : Text(
                '$number',
                style: TextStyle(
                  color: isActive ? Colors.white : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }
}

/// Animated status text with pulsing dots
class AiAnimatedStatusText extends StatefulWidget {
  final String status;

  const AiAnimatedStatusText({super.key, required this.status});

  @override
  State<AiAnimatedStatusText> createState() => _AiAnimatedStatusTextState();
}

class _AiAnimatedStatusTextState extends State<AiAnimatedStatusText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final dots = '.' * ((_controller.value * 4).floor() % 4);
        return Text(
          '${widget.status}$dots',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65), fontSize: 16),
        );
      },
    );
  }
}

/// Animated AI thinking visualization with pulsing and orbiting elements
class AiThinkingAnimation extends StatefulWidget {
  final Color primaryColor;
  final String? personaAvatarAssetPath;
  final double size;

  const AiThinkingAnimation({
    super.key,
    required this.primaryColor,
    this.personaAvatarAssetPath,
    this.size = 140,
  });

  @override
  State<AiThinkingAnimation> createState() => _AiThinkingAnimationState();
}

class _AiThinkingAnimationState extends State<AiThinkingAnimation>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _orbitController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _orbitController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringSize = widget.size * 0.86;
    final glowSize = widget.size * 0.86;
    final orbitRadius = widget.size * 0.36;
    final iconSize = widget.size * 0.34;
    final avatarSize = widget.size * 0.46;
    final particleBaseSize = widget.size * 0.07;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: glowSize * _pulseAnimation.value,
                height: glowSize * _pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.primaryColor.withValues(alpha: 0.1),
                      widget.primaryColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              );
            },
          ),

          // Orbiting particles
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _orbitController,
              builder: (context, child) {
                final angle =
                    (_orbitController.value * 2 * math.pi) +
                    (index * 2 * math.pi / 3);
                final x = orbitRadius * math.cos(angle);
                final y = orbitRadius * math.sin(angle);

                return Transform.translate(
                  offset: Offset(x, y),
                  child: Container(
                    width: particleBaseSize + (index * 2),
                    height: particleBaseSize + (index * 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.primaryColor.withValues(
                        alpha: 0.6 - (index * 0.15),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.primaryColor.withValues(alpha: 0.4),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }),

          // Center pulsing icon
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: ringSize,
                  height: ringSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.primaryColor.withValues(alpha: 0.15),
                    boxShadow: [
                      BoxShadow(
                        color: widget.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.psychology,
                    size: iconSize,
                    color: widget.primaryColor,
                  ),
                ),
              );
            },
          ),
          if (widget.personaAvatarAssetPath != null)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: ClipOval(
                    child: Image.asset(
                      widget.personaAvatarAssetPath!,
                      width: avatarSize,
                      height: avatarSize,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Cycling thinking messages with elapsed timer
class AiThinkingMessages extends StatefulWidget {
  final DateTime? startTime;
  final List<String> messages;

  const AiThinkingMessages({super.key, this.startTime, required this.messages});

  @override
  State<AiThinkingMessages> createState() => _AiThinkingMessagesState();
}

class _AiThinkingMessagesState extends State<AiThinkingMessages> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startCycling();
  }

  void _startCycling() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.messages.length;
        });
        _startCycling();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.startTime != null
        ? DateTime.now().difference(widget.startTime!)
        : Duration.zero;

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: Text(
            widget.messages[_currentIndex],
            key: ValueKey(_currentIndex),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65), fontSize: 14),
          ),
        ),
        const SizedBox(height: 16),
        if (elapsed.inSeconds > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 6),
                AiElapsedTimer(startTime: widget.startTime!),
              ],
            ),
          ),
      ],
    );
  }
}

/// Live elapsed time counter
class AiElapsedTimer extends StatefulWidget {
  final DateTime startTime;

  const AiElapsedTimer({super.key, required this.startTime});

  @override
  State<AiElapsedTimer> createState() => _AiElapsedTimerState();
}

class _AiElapsedTimerState extends State<AiElapsedTimer> {
  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {});
        _tick();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startTime);
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;

    return Text(
      minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Full loading overlay composing thinking animation, status text, messages, and cancel button
class AiLoadingState extends StatefulWidget {
  final String currentProvider;
  final String currentStatus;
  final DateTime? loadingStartTime;
  final List<String> thinkingMessages;
  final String? streamedText;
  final bool showStreamPreview;
  final String? personaName;
  final String? personaAvatarAssetPath;
  final VoidCallback? onRunInBackground;
  final String backgroundActionLabel;
  final bool isBackgroundActionBusy;
  final VoidCallback onCancel;

  const AiLoadingState({
    super.key,
    required this.currentProvider,
    required this.currentStatus,
    this.loadingStartTime,
    required this.thinkingMessages,
    this.streamedText,
    this.showStreamPreview = false,
    this.personaName,
    this.personaAvatarAssetPath,
    this.onRunInBackground,
    this.backgroundActionLabel = 'Run in Background',
    this.isBackgroundActionBusy = false,
    required this.onCancel,
  });

  @override
  State<AiLoadingState> createState() => _AiLoadingStateState();
}

class _AiLoadingStateState extends State<AiLoadingState> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant AiLoadingState oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streamedText != oldWidget.streamedText) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Pretty-format partial/incomplete JSON for readable streaming display.
  String _prettyFormatPartialJson(String raw) {
    final buf = StringBuffer();
    var depth = 0;
    var inString = false;
    var escaped = false;

    void writeIndent() {
      buf.write('  ' * depth);
    }

    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];

      if (escaped) {
        buf.write(ch);
        escaped = false;
        continue;
      }

      if (ch == '\\' && inString) {
        buf.write(ch);
        escaped = true;
        continue;
      }

      if (ch == '"') {
        inString = !inString;
        buf.write(ch);
        continue;
      }

      if (inString) {
        buf.write(ch);
        continue;
      }

      // Skip existing whitespace outside strings — we add our own.
      if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') continue;

      switch (ch) {
        case '{':
        case '[':
          buf.write(ch);
          depth++;
          buf.write('\n');
          writeIndent();
          break;
        case '}':
        case ']':
          depth = (depth - 1).clamp(0, 999);
          buf.write('\n');
          writeIndent();
          buf.write(ch);
          break;
        case ',':
          buf.write(ch);
          buf.write('\n');
          writeIndent();
          break;
        case ':':
          buf.write(': ');
          break;
        default:
          buf.write(ch);
      }
    }

    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final hasText =
        widget.streamedText != null && widget.streamedText!.trim().isNotEmpty;
    final showStreamPreview = widget.showStreamPreview;
    final displayText = hasText
        ? _prettyFormatPartialJson(widget.streamedText!)
        : 'Waiting for streamed output...';

    return Padding(
      padding: EdgeInsets.fromLTRB(24, showStreamPreview ? 20 : 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showStreamPreview)
            Flexible(
              flex: 2,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    AiThinkingAnimation(
                      size: 112,
                      primaryColor: Theme.of(context).colorScheme.primary,
                      personaAvatarAssetPath: widget.personaAvatarAssetPath,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.personaAvatarAssetPath != null) ...[
                          ClipOval(
                            child: Image.asset(
                              widget.personaAvatarAssetPath!,
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          widget.personaName ?? widget.currentProvider,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AiAnimatedStatusText(status: widget.currentStatus),
                    const SizedBox(height: 12),
                    AiThinkingMessages(
                      startTime: widget.loadingStartTime,
                      messages: widget.thinkingMessages,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            AiThinkingAnimation(
              primaryColor: Theme.of(context).colorScheme.primary,
              personaAvatarAssetPath: widget.personaAvatarAssetPath,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.personaAvatarAssetPath != null) ...[
                  ClipOval(
                    child: Image.asset(
                      widget.personaAvatarAssetPath!,
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  widget.personaName ?? widget.currentProvider,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AiAnimatedStatusText(status: widget.currentStatus),
            const SizedBox(height: 16),
            AiThinkingMessages(
              startTime: widget.loadingStartTime,
              messages: widget.thinkingMessages,
            ),
          ],
          if (showStreamPreview) ...[
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Live output',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: SelectableText(
                            displayText,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.55,
                              color: hasText
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                              fontFamily: 'monospace',
                              fontStyle: hasText
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              if (widget.onRunInBackground != null)
                OutlinedButton.icon(
                  onPressed: widget.isBackgroundActionBusy
                      ? null
                      : widget.onRunInBackground,
                  icon: widget.isBackgroundActionBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.notifications_active_outlined),
                  label: Text(widget.backgroundActionLabel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Green badge showing success provider name
class AiProviderBadge extends StatelessWidget {
  final String providerName;
  final String? personaName;
  final String? personaAvatarAssetPath;

  const AiProviderBadge({
    super.key,
    required this.providerName,
    this.personaName,
    this.personaAvatarAssetPath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (personaAvatarAssetPath != null)
            ClipOval(
              child: Image.asset(
                personaAvatarAssetPath!,
                width: 14,
                height: 14,
                fit: BoxFit.cover,
              ),
            )
          else
            Icon(Icons.smart_toy, size: 14, color: AppColors.secondaryDark),
          const SizedBox(width: 4),
          Text(
            personaName ?? providerName,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.successDark,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
