import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../../widgets/common/app_search_bar.dart';

class ProjectSearchBar extends StatelessWidget {
  final String? initialValue;
  final ValueChanged<String> onSearchChanged;
  final double? width;
  final double? height;

  const ProjectSearchBar({
    super.key,
    this.initialValue,
    required this.onSearchChanged,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final terminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology
        .toLowerCase();

    return AppSearchBar(
      hintText: 'Search $terminology...',
      initialValue: initialValue,
      onChanged: onSearchChanged,
      width: width,
      height: height,
    );
  }
}
