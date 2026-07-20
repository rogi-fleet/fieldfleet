import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../theme/theme.dart';

/// A skeleton placeholder widget for project cards during loading
class ProjectCardSkeleton extends StatelessWidget {
  final bool forceCompactLayout;

  const ProjectCardSkeleton({super.key, this.forceCompactLayout = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade800 : AppColors.cardBorder,
      highlightColor: isDark ? Colors.grey.shade700 : AppColors.surfaceAlt,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        child: forceCompactLayout ? _buildMobileLayout() : _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Photo at top (full width) with overlay effect
        SizedBox(
          height: 200,
          width: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(
                child: _box(height: 200, width: double.infinity),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.5),
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _box(height: 20, width: 180),
                      const SizedBox(height: 6),
                      _box(height: 14, width: 140),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _box(height: 24, width: 100),
                  const SizedBox(width: 8),
                  _box(height: 24, width: 80),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _box(height: 12, width: 60),
                  const Spacer(),
                  _box(height: 12, width: 40),
                ],
              ),
              const SizedBox(height: 8),
              _box(height: 8, width: double.infinity),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _box(height: 12, width: 80),
                        const SizedBox(height: 6),
                        _box(height: 14, width: 100),
                        const SizedBox(height: 12),
                        _box(height: 12, width: 60),
                        const SizedBox(height: 6),
                        _box(height: 14, width: 90),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _box(height: 12, width: 70),
                        const SizedBox(height: 6),
                        _box(height: 14, width: 85),
                        const SizedBox(height: 12),
                        _box(height: 12, width: 90),
                        const SizedBox(height: 6),
                        _box(height: 14, width: 70),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _box(height: 12, width: 85),
                        const SizedBox(height: 6),
                        _box(height: 14, width: 60),
                        const SizedBox(height: 12),
                        _box(height: 12, width: 75),
                        const SizedBox(height: 6),
                        _box(height: 14, width: 95),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _circle(size: 32),
                  const SizedBox(width: 4),
                  _circle(size: 32),
                  const SizedBox(width: 4),
                  _circle(size: 32),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _box(height: 36, width: double.infinity)),
                  const SizedBox(width: 8),
                  Expanded(child: _box(height: 36, width: double.infinity)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _box(width: 180, height: double.infinity),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _box(height: 20, width: 200),
                            const SizedBox(height: 8),
                            _box(height: 14, width: 150),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      _box(height: 28, width: 80),
                      const SizedBox(width: 8),
                      _box(height: 28, width: 80),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _box(height: 12, width: 100),
                            const SizedBox(height: 6),
                            _box(height: 14, width: 120),
                            const SizedBox(height: 12),
                            _box(height: 12, width: 80),
                            const SizedBox(height: 6),
                            _box(height: 14, width: 100),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _box(height: 12, width: 90),
                            const SizedBox(height: 6),
                            _box(height: 14, width: 110),
                            const SizedBox(height: 12),
                            _box(height: 12, width: 100),
                            const SizedBox(height: 6),
                            _box(height: 14, width: 90),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _box(height: 12, width: 110),
                            const SizedBox(height: 6),
                            _box(height: 14, width: 80),
                            const SizedBox(height: 12),
                            _box(height: 12, width: 90),
                            const SizedBox(height: 6),
                            _box(height: 14, width: 120),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _box(height: 12, width: 60),
                      const Spacer(),
                      _box(height: 12, width: 40),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _box(height: 8, width: double.infinity),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _box(height: 32, width: 90),
                      const SizedBox(width: 8),
                      _box(height: 32, width: 80),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _box({double? width, double? height}) {
    return Container(
      width: width,
      height: height ?? 16,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
  }

  static Widget _circle({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// A list of skeleton cards for the loading state
class ProjectCardSkeletonList extends StatelessWidget {
  final int count;

  const ProjectCardSkeletonList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount;
        if (width < AppBreakpoints.mobile) {
          crossAxisCount = 1;
        } else if (width < AppBreakpoints.tablet) {
          crossAxisCount = 2;
        } else if (width < 1400) {
          crossAxisCount = 3;
        } else {
          crossAxisCount = 4;
        }

        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.base),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.55,
          ),
          itemCount: count,
          itemBuilder: (context, index) => const ProjectCardSkeleton(forceCompactLayout: true),
        );
      },
    );
  }
}
