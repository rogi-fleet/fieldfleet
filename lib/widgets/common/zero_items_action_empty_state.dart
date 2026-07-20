import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../theme/theme.dart';
import '../animated_empty_state_cta.dart';

class ZeroItemsActionEmptyState extends StatefulWidget {
  const ZeroItemsActionEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onTap,
    this.hintText,
    this.secondaryAction,
    this.padding = const EdgeInsets.all(AppSpacing.xxxl),
    this.lottieAsset,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback? onTap;
  final String? hintText;
  final Widget? secondaryAction;
  final EdgeInsetsGeometry padding;
  /// Optional path to a Lottie JSON asset (e.g. 'assets/lottie/empty_box.json').
  /// When provided, replaces the pulse icon animation.
  final String? lottieAsset;

  @override
  State<ZeroItemsActionEmptyState> createState() =>
      _ZeroItemsActionEmptyStateState();
}

class _ZeroItemsActionEmptyStateState extends State<ZeroItemsActionEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final accentColor = chrome.scaffoldAccent;

    return Center(
      child: Padding(
        padding: widget.padding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.lottieAsset != null)
              Lottie.asset(
                widget.lottieAsset!,
                width: 120,
                height: 120,
                repeat: true,
              )
            else
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accentColor.withValues(alpha: 0.1),
                            accentColor.withValues(alpha: 0.2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        size: 40,
                        color: accentColor,
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: chrome.scaffoldText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              style: TextStyle(
                fontSize: 12,
                color: chrome.scaffoldTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.onTap != null) ...[
              const SizedBox(height: 18),
              AnimatedEmptyStateCta(
                animation: _pulseAnimation,
                label: widget.ctaLabel,
                onTap: widget.onTap,
              ),
            ],
            if (widget.secondaryAction != null) ...[
              const SizedBox(height: 12),
              widget.secondaryAction!,
            ],
            const SizedBox(height: 10),
            Text(
              widget.hintText ??
                  (widget.onTap != null
                      // Point at the actual CTA above rather than a phantom
                      // "+" button — the button is labelled with the action
                      // (e.g. "Upload File", "Add Structure").
                      ? (kIsWeb
                          ? 'Click "${widget.ctaLabel}" to begin'
                          : 'Tap "${widget.ctaLabel}" to begin')
                      : (kIsWeb
                          ? 'Click the + button to begin'
                          : 'Tap the + button to begin')),
              style: TextStyle(
                fontSize: 12,
                color: chrome.scaffoldTextSecondary,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
