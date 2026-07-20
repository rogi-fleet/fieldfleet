import 'package:flutter/material.dart';
import '../models/project_health_score.dart';

/// Small circular indicator showing the health score number + color.
class ProjectHealthBadge extends StatelessWidget {
  final ProjectHealthScore score;
  final double size;

  const ProjectHealthBadge({
    super.key,
    required this.score,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${score.label} — ${score.overallScore}/100',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: score.color.withValues(alpha: 0.12),
          border: Border.all(color: score.color, width: 2),
        ),
        child: Center(
          child: Text(
            '${score.overallScore}',
            style: TextStyle(
              fontSize: size * 0.34,
              fontWeight: FontWeight.w800,
              color: score.color,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
