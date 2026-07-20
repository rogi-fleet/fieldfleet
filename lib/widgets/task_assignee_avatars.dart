import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../models/task.dart';
import '../models/user.dart';
import '../services/service_locator.dart';
import '../services/task_scheduler_service.dart';
import 'user_avatar.dart';
import 'skill_chip.dart';

/// Widget that displays task assignees as overlapping avatars with quick-assign popup
class TaskAssigneeAvatars extends StatelessWidget {
  final Task? task;
  final Map<String, AppUser> usersMap;
  final List<AppUser> allWorkspaceUsers;
  final int maxVisible;
  final double avatarSize;
  final VoidCallback? onAssignmentChanged;
  /// Optional override for assignee IDs (e.g., for aggregated group assignees)
  final List<String>? assigneeIdsOverride;
  /// If true, disables the click-to-assign popup (for read-only display)
  final bool readOnly;
  /// Map of userId -> list of skillIds for skill-based sorting
  final Map<String, List<String>> memberSkillsMap;

  const TaskAssigneeAvatars({
    super.key,
    this.task,
    required this.usersMap,
    required this.allWorkspaceUsers,
    this.maxVisible = 3,
    this.avatarSize = 24,
    this.onAssignmentChanged,
    this.assigneeIdsOverride,
    this.readOnly = false,
    this.memberSkillsMap = const {},
  });

  List<String> get _effectiveAssigneeIds =>
      assigneeIdsOverride ?? task?.assignedToIds ?? [];

  @override
  Widget build(BuildContext context) {
    if (readOnly || task == null) {
      // Read-only mode - just show avatars without click handler
      return Tooltip(
        message: _effectiveAssigneeIds.isEmpty
            ? 'No assignees'
            : _getAssignedNames(),
        child: _buildAvatarContent(context),
      );
    }

    return InkWell(
      onTap: () => _showAssignmentPopup(context),
      borderRadius: BorderRadius.circular(avatarSize / 2),
      child: Tooltip(
        message: _effectiveAssigneeIds.isEmpty
            ? 'Assign team members'
            : _getAssignedNames(),
        child: _buildAvatarContent(context),
      ),
    );
  }

  String _getAssignedNames() {
    return _effectiveAssigneeIds
        .map((id) => usersMap[id]?.displayName ?? usersMap[id]?.email ?? 'Unknown')
        .join(', ');
  }

  Widget _buildAvatarContent(BuildContext context) {
    final assignedIds = _effectiveAssigneeIds;

    // No assignees - show person add icon
    if (assignedIds.isEmpty) {
      return Container(
        width: avatarSize,
        height: avatarSize,
        decoration: BoxDecoration(
          color: AppColors.cardBorder,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.textTertiary, width: 1),
        ),
        child: Icon(
          Icons.person_add_outlined,
          size: avatarSize * 0.6,
          color: AppColors.textSecondary,
        ),
      );
    }

    // Has assignees - show stacked avatars
    final visibleIds = assignedIds.take(maxVisible).toList();
    final remainingCount = assignedIds.length - maxVisible;
    final overlapOffset = avatarSize * 0.6;

    return SizedBox(
      width: overlapOffset * (visibleIds.length - 1) + avatarSize + 
             (remainingCount > 0 ? overlapOffset : 0),
      height: avatarSize,
      child: Stack(
        children: [
          for (int i = 0; i < visibleIds.length; i++)
            Positioned(
              left: i * overlapOffset,
              child: _buildSingleAvatar(visibleIds[i]),
            ),
          if (remainingCount > 0)
            Positioned(
              left: visibleIds.length * overlapOffset,
              child: _buildOverflowIndicator(remainingCount),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleAvatar(String userId) {
    final cachedUser = usersMap[userId];

    return StreamBuilder<AppUser?>(
      stream: ServiceLocator.userService.getUserStream(userId),
      builder: (context, snapshot) {
        final user = snapshot.data ?? cachedUser;

        return Container(
          width: avatarSize,
          height: avatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: user != null
                ? (user.profilePictureUrl != null
                    ? CachedNetworkImage(
                        imageUrl: user.profilePictureUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildAvatarFallback(user),
                      )
                    : _buildAvatarFallback(user))
                : Container(
                    color: AppColors.cardBorder,
                    child: Icon(
                      Icons.person,
                      size: avatarSize * 0.6,
                      color: AppColors.textTertiary,
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildAvatarFallback(AppUser user) {
    const colors = AppColors.categoryPalette;
    final colorIndex = user.id.hashCode.abs() % colors.length;

    return Container(
      color: colors[colorIndex],
      child: Center(
        child: Text(
          user.getInitials(),
          style: TextStyle(
            color: Colors.white,
            fontSize: avatarSize * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildOverflowIndicator(int count) {
    return Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        color: AppColors.cardBorder,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          '+$count',
          style: TextStyle(
            fontSize: avatarSize * 0.35,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  void _showAssignmentPopup(BuildContext context) {
    if (task == null) return; // Safety check

    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => _AssignmentPopup(
        task: task!,
        allWorkspaceUsers: allWorkspaceUsers,
        initialPosition: offset,
        buttonSize: button.size,
        onAssignmentChanged: onAssignmentChanged,
        memberSkillsMap: memberSkillsMap,
      ),
    );
  }
}

class _AssignmentPopup extends StatefulWidget {
  final Task task;
  final List<AppUser> allWorkspaceUsers;
  final Offset initialPosition;
  final Size buttonSize;
  final VoidCallback? onAssignmentChanged;
  final Map<String, List<String>> memberSkillsMap;

  const _AssignmentPopup({
    required this.task,
    required this.allWorkspaceUsers,
    required this.initialPosition,
    required this.buttonSize,
    this.onAssignmentChanged,
    this.memberSkillsMap = const {},
  });

  @override
  State<_AssignmentPopup> createState() => _AssignmentPopupState();
}

class _AssignmentPopupState extends State<_AssignmentPopup> {
  late Set<String> _selectedUserIds;
  bool _isLoading = false;
  bool _isAutoAssigning = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedUserIds = Set<String>.from(widget.task.assignedToIds);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const popupWidth = 280.0;
    const popupHeight = 320.0;

    // Calculate position to show popup below and right-aligned to button
    double left = widget.initialPosition.dx;
    double top = widget.initialPosition.dy + widget.buttonSize.height + 8;

    // Adjust if popup would go off screen
    if (left + popupWidth > screenSize.width - 16) {
      left = screenSize.width - popupWidth - 16;
    }
    if (top + popupHeight > screenSize.height - 16) {
      top = widget.initialPosition.dy - popupHeight - 8;
    }

    final filteredUsers = widget.allWorkspaceUsers.where((user) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return (user.displayName?.toLowerCase().contains(query) ?? false) ||
             user.email.toLowerCase().contains(query);
    }).toList();

    // Sort by skill match if task has required skills
    final requiredSkillIds = widget.task.requiredSkillIds;
    if (requiredSkillIds.isNotEmpty) {
      filteredUsers.sort((a, b) {
        final aSkills = widget.memberSkillsMap[a.id] ?? [];
        final bSkills = widget.memberSkillsMap[b.id] ?? [];
        final aMatches = aSkills.where((s) => requiredSkillIds.contains(s)).length;
        final bMatches = bSkills.where((s) => requiredSkillIds.contains(s)).length;
        // Higher match count first
        return bMatches.compareTo(aMatches);
      });
    }

    return Stack(
      children: [
        // Backdrop to close popup
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(color: Colors.transparent),
          ),
        ),
        // Popup
        Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(AppRadius.r12),
            child: Container(
              width: popupWidth,
              constraints: const BoxConstraints(maxHeight: popupHeight),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(AppRadius.r12),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        const Icon(Icons.people_outline, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Assign Team Members',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (_isLoading || _isAutoAssigning)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        _buildAutoAssignButton(),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Search field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search team members...',
                        hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: BorderSide(color: AppColors.cardBorder),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                  // Unassign all option
                  if (_selectedUserIds.isNotEmpty)
                    InkWell(
                      onTap: _unassignAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_off_outlined,
                              size: 18,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Unassign all',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_selectedUserIds.isNotEmpty)
                    const Divider(height: 1),
                  // User list
                  Flexible(
                    child: filteredUsers.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(AppSpacing.base),
                            child: Text(
                              'No team members found',
                              style: TextStyle(color: AppColors.textTertiary),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                            itemCount: filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              final isSelected = _selectedUserIds.contains(user.id);

                              return InkWell(
                                onTap: () => _toggleUser(user.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.sm,
                                  ),
                                  child: Row(
                                    children: [
                                      UserAvatar(
                                        user: user,
                                        size: AvatarSize.small,
                                        onTap: () => _toggleUser(user.id),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              user.displayName ?? user.email,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (user.displayName != null)
                                              Text(
                                                user.email,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textTertiary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                      // Skill match badge
                                      if (widget.task.requiredSkillIds.isNotEmpty) ...[
                                        Builder(builder: (context) {
                                          final userSkills = widget.memberSkillsMap[user.id] ?? [];
                                          final matchCount = userSkills
                                              .where((s) => widget.task.requiredSkillIds.contains(s))
                                              .length;
                                          return SkillMatchBadge(
                                            matchingSkills: matchCount,
                                            totalRequired: widget.task.requiredSkillIds.length,
                                            isCompact: true,
                                          );
                                        }),
                                        const SizedBox(width: 4),
                                      ],
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (_) => _toggleUser(user.id),
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAutoAssignButton() {
    return Tooltip(
      message: 'Auto-select based on skills & availability',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _isAutoAssigning ? null : _autoAssign,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_fix_high,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                'Auto',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _autoAssign() async {
    setState(() => _isAutoAssigning = true);
    try {
      final proposal = await TaskSchedulerService.autoAssign(
        task: widget.task,
        workspaceId: widget.task.workspaceId,
      );
      if (!mounted) return;
      if (proposal == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No matching team member found')),
        );
        setState(() => _isAutoAssigning = false);
        return;
      }
      // Add the proposed assignee
      if (!_selectedUserIds.contains(proposal.proposedAssigneeId)) {
        _selectedUserIds.add(proposal.proposedAssigneeId);
        setState(() => _isAutoAssigning = false);
        // Save immediately
        setState(() => _isLoading = true);
        try {
          await ServiceLocator.taskService.updateTask(
            taskId: widget.task.id,
            assignedToIds: _selectedUserIds.toList(),
          );
          widget.onAssignmentChanged?.call();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to assign: $e')),
            );
          }
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isAutoAssigning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${proposal.proposedAssigneeName} is already assigned'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAutoAssigning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-assign failed: $e')),
        );
      }
    }
  }

  Future<void> _unassignAll() async {
    setState(() {
      _selectedUserIds.clear();
    });

    setState(() => _isLoading = true);
    try {
      await ServiceLocator.taskService.updateTask(
        taskId: widget.task.id,
        assignedToIds: [],
      );
      widget.onAssignmentChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unassign: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleUser(String userId) async {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });

    // Update task immediately
    setState(() => _isLoading = true);
    try {
      await ServiceLocator.taskService.updateTask(
        taskId: widget.task.id,
        assignedToIds: _selectedUserIds.toList(),
      );
      widget.onAssignmentChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update assignment: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
