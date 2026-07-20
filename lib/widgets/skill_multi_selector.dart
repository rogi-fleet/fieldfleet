import 'package:flutter/material.dart';
import '../services/service_locator.dart';
import '../models/skill.dart';

import '../theme/theme.dart';
import 'skill_chip.dart';

/// Multi-select widget for choosing skills
class SkillMultiSelector extends StatefulWidget {
  final String workspaceId;
  final List<String> selectedSkillIds;
  final ValueChanged<List<String>> onChanged;
  final String? label;
  final bool enabled;

  const SkillMultiSelector({
    super.key,
    required this.workspaceId,
    required this.selectedSkillIds,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  @override
  State<SkillMultiSelector> createState() => _SkillMultiSelectorState();
}

class _SkillMultiSelectorState extends State<SkillMultiSelector> {
  final dynamic _skillService = ServiceLocator.skillService;
  List<Skill> _allSkills = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSkills();
  }

  Future<void> _loadSkills() async {
    try {
      _skillService.getSkills(widget.workspaceId).listen(
        (skills) {
          if (mounted) {
            setState(() {
              _allSkills = skills;
              _isLoading = false;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSkillPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SkillPickerSheet(
        allSkills: _allSkills,
        selectedSkillIds: widget.selectedSkillIds,
        onChanged: widget.onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final selectedSkills = _allSkills
        .where((s) => widget.selectedSkillIds.contains(s.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Row(
            children: [
              Icon(
                Icons.build_circle_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            children: [
              // Selected skills as chips
              if (selectedSkills.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selectedSkills.map((skill) {
                      return SkillChip(
                        skill: skill,
                        showDelete: widget.enabled,
                        onDelete: widget.enabled
                            ? () {
                                final newIds = List<String>.from(
                                  widget.selectedSkillIds,
                                )..remove(skill.id);
                                widget.onChanged(newIds);
                              }
                            : null,
                      );
                    }).toList(),
                  ),
                ),
              // Add button
              if (widget.enabled)
                InkWell(
                  onTap: _showSkillPicker,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          selectedSkills.isEmpty
                              ? 'Add required skills...'
                              : 'Add more skills...',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkillPickerSheet extends StatefulWidget {
  final List<Skill> allSkills;
  final List<String> selectedSkillIds;
  final ValueChanged<List<String>> onChanged;

  const _SkillPickerSheet({
    required this.allSkills,
    required this.selectedSkillIds,
    required this.onChanged,
  });

  @override
  State<_SkillPickerSheet> createState() => _SkillPickerSheetState();
}

class _SkillPickerSheetState extends State<_SkillPickerSheet> {
  late Set<String> _selected;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedSkillIds);
  }

  @override
  Widget build(BuildContext context) {
    final filteredSkills = widget.allSkills.where((skill) {
      if (_searchQuery.isEmpty) return true;
      return skill.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.build_circle, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Select Skills',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () {
                  widget.onChanged(_selected.toList());
                  Navigator.pop(context);
                },
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Search
          TextField(
            decoration: InputDecoration(
              hintText: 'Search skills...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 10,
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          // Skill list
          Expanded(
            child: filteredSkills.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty
                          ? 'No skills defined yet'
                          : 'No matching skills',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredSkills.length,
                    itemBuilder: (context, index) {
                      final skill = filteredSkills[index];
                      final isSelected = _selected.contains(skill.id);

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selected.add(skill.id);
                            } else {
                              _selected.remove(skill.id);
                            }
                          });
                        },
                        title: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: skill.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(skill.name)),
                          ],
                        ),
                        subtitle: skill.description != null
                            ? Text(
                                skill.description!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              )
                            : null,
                        controlAffinity: ListTileControlAffinity.trailing,
                        dense: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
