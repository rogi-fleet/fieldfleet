import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';

enum AvatarSize { small, medium, large }

class UserAvatar extends StatelessWidget {
  final AppUser? user;
  final String? userId;
  final AvatarSize size;
  final VoidCallback? onTap;
  final bool navigable;

  const UserAvatar({
    super.key,
    this.user,
    this.userId,
    this.size = AvatarSize.medium,
    this.onTap,
    this.navigable = true,
  });

  double get _radius {
    switch (size) {
      case AvatarSize.small:
        return 16;
      case AvatarSize.medium:
        return 20;
      case AvatarSize.large:
        return 40;
    }
  }

  double get _fontSize {
    switch (size) {
      case AvatarSize.small:
        return 12;
      case AvatarSize.medium:
        return 16;
      case AvatarSize.large:
        return 24;
    }
  }

  Color _getColorFromId(String id) {
    // Generate a consistent color from user ID hash
    final hash = id.hashCode;
    final colors = [
      AppColors.info,
      AppColors.success,
      AppColors.warning,
      AppColors.messageAccent,
      AppColors.financialAccent,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
      AppColors.warning,
      AppColors.error,
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUserId = userId ?? user?.id;

    if (resolvedUserId == null) {
      // Show default avatar
      return CircleAvatar(
        radius: _radius,
        backgroundColor: AppColors.textTertiary,
        child: Icon(Icons.person, size: _fontSize, color: Colors.white),
      );
    }

    return StreamBuilder<AppUser?>(
      stream: ServiceLocator.userService.getUserStream(resolvedUserId),
      builder: (context, snapshot) {
        final resolvedUser = snapshot.data ?? user;
        if (resolvedUser == null) {
          return CircleAvatar(
            radius: _radius,
            backgroundColor: AppColors.textTertiary,
            child: Icon(Icons.person, size: _fontSize, color: Colors.white),
          );
        }

        final backgroundColor = _getColorFromId(resolvedUser.id);
        final initials = resolvedUser.getInitials();

        final avatar = resolvedUser.profilePictureUrl != null
            ? CircleAvatar(
                radius: _radius,
                backgroundImage: CachedNetworkImageProvider(resolvedUser.profilePictureUrl!),
                onBackgroundImageError: (_, __) {},
              )
            : CircleAvatar(
                radius: _radius,
                backgroundColor: backgroundColor,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: _fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              );

        if (onTap != null) {
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(_radius),
            child: avatar,
          );
        }

        if (!navigable) return avatar;

        return InkWell(
          onTap: () {
            context.go('/profile/$resolvedUserId');
          },
          borderRadius: BorderRadius.circular(_radius),
          child: avatar,
        );
      },
    );
  }
}
