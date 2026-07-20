import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

enum WorkspaceAvatarSize { small, medium, large }

/// A widget that displays a workspace avatar.
/// Shows the workspace image if available, otherwise shows the workspace initial.
class WorkspaceAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String workspaceName;
  final WorkspaceAvatarSize size;
  final VoidCallback? onTap;

  const WorkspaceAvatar({
    super.key,
    this.avatarUrl,
    required this.workspaceName,
    this.size = WorkspaceAvatarSize.medium,
    this.onTap,
  });

  double get _size {
    switch (size) {
      case WorkspaceAvatarSize.small:
        return 32;
      case WorkspaceAvatarSize.medium:
        return 48;
      case WorkspaceAvatarSize.large:
        return 80;
    }
  }

  double get _fontSize {
    switch (size) {
      case WorkspaceAvatarSize.small:
        return 14;
      case WorkspaceAvatarSize.medium:
        return 20;
      case WorkspaceAvatarSize.large:
        return 32;
    }
  }

  double get _borderRadius {
    switch (size) {
      case WorkspaceAvatarSize.small:
        return 4;
      case WorkspaceAvatarSize.medium:
        return 8;
      case WorkspaceAvatarSize.large:
        return 12;
    }
  }

  Color _getColorFromName(String name) {
    // Generate a consistent color from workspace name hash
    final hash = name.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
      Colors.amber,
      Colors.red,
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _getColorFromName(workspaceName);
    final initial = workspaceName.isNotEmpty 
        ? workspaceName.substring(0, 1).toUpperCase() 
        : 'W';

    Widget avatar;
    
    if (avatarUrl != null) {
      avatar = ClipRRect(
        borderRadius: BorderRadius.circular(_borderRadius),
        child: CachedNetworkImage(
          imageUrl: avatarUrl!,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => _buildInitialAvatar(backgroundColor, initial),
        ),
      );
    } else {
      avatar = _buildInitialAvatar(backgroundColor, initial);
    }

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_borderRadius),
        child: avatar,
      );
    }

    return avatar;
  }

  Widget _buildInitialAvatar(Color backgroundColor, String initial) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: _fontSize,
          fontWeight: FontWeight.bold,
          color: backgroundColor,
        ),
      ),
    );
  }
}
