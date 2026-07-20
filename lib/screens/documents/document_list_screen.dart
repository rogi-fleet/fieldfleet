import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/generated_document.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/documents/document_list_panel.dart';

class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({super.key});

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  Stream<List<GeneratedDocument>>? _documentStream;
  String? _workspaceId;

  void _ensureStream(String workspaceId) {
    if (workspaceId != _workspaceId) {
      _workspaceId = workspaceId;
      _documentStream = ServiceLocator.documentService.getDocuments(workspaceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return const Center(child: Text('Error: No workspace found'));
    }

    _ensureStream(workspaceId);

    return Scaffold(
      body: Column(
        children: [
          const ModuleHeader(
            icon: Icons.description_outlined,
            title: 'Documents',
            description:
                'Estimates, contracts, change orders and signed paperwork.',
          ),
          Expanded(
            child: DocumentListPanel(
              documentStream: _documentStream!,
              onCreateTap: () => context.go('/documents/create'),
              onNavigateToDocument: (id) => context.push('/documents/$id'),
              extraQuickToggles: [
                ViewIconButton(
                  icon: Icons.article_outlined,
                  isSelected: false,
                  onTap: () => context.go('/documents/templates'),
                  tooltip: 'Templates',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
