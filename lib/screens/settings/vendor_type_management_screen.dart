import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer_type_config.dart';
import '../../services/service_locator.dart';
import '../../utils/user_facing_error.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';
import '../../widgets/adaptive_navigation.dart';

class VendorTypeManagementScreen extends StatefulWidget {
  const VendorTypeManagementScreen({super.key});

  @override
  State<VendorTypeManagementScreen> createState() =>
      _VendorTypeManagementScreenState();
}

class _VendorTypeManagementScreenState
    extends State<VendorTypeManagementScreen>
    with SingleTickerProviderStateMixin {
  final _service = ServiceLocator.vendorTypeService;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabSwitch);
  }

  void _onTabSwitch() {
    if (!_tabController.indexIsChanging) {
      TabSwitchNotification().dispatch(context);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabSwitch);
    _tabController.dispose();
    super.dispose();
  }

  String? get _workspaceId =>
      Provider.of<AuthProvider>(context, listen: false)
          .appUser
          ?.currentWorkspaceId;

  // ── Shared dialog helpers ─────────────────────────────────────────────

  Future<Map<String, dynamic>?> _showCreateOrEditDialog({
    required String title,
    String? existingName,
    String? existingDescription,
    Color? existingColor,
  }) async {
    final nameCtrl = TextEditingController(text: existingName ?? '');
    final descCtrl = TextEditingController(text: existingDescription ?? '');
    Color selectedColor = existingColor ?? Colors.blue;

    return showFormPopup<Map<String, dynamic>>(
      context,
      icon: existingName == null ? Icons.category : Icons.edit,
      title: title,
      width: 480,
      builder: (popupContext, scrollController) => StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StackedField(
                      label: 'Name',
                      child: TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(hintText: 'e.g., Plumbing Contractor'),
                        autofocus: existingName == null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Description (Optional)',
                      child: TextField(
                        controller: descCtrl,
                        decoration: const InputDecoration(hintText: 'Describe this type'),
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildColorPicker(selectedColor, (c) => setDialogState(() => selectedColor = c)),
                  ],
                ),
              ),
            ),
            FormPopupFooter(
              onSubmit: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  Navigator.pop(context, {
                    'name': nameCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'color': _colorToHex(selectedColor),
                  });
                }
              },
              submitLabel: existingName == null ? 'Create' : 'Save',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker(Color selected, ValueChanged<Color> onChanged) {
    const colors = [
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
      Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
      Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.amber, Colors.orange, Colors.deepOrange, Colors.brown,
      Colors.blueGrey, Colors.grey,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Color:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) => InkWell(
            onTap: () => onChanged(color),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color, shape: BoxShape.circle,
                border: Border.all(
                  color: selected == color ? Colors.black : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  static String _colorToHex(Color c) =>
      '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

  static Color _parseHex(String hex) {
    try {
      var s = hex.replaceAll('#', '');
      if (s.length == 3) s = s.split('').map((c) => c + c).join();
      if (s.length == 6) return Color(int.parse('FF$s', radix: 16));
      if (s.length == 8) return Color(int.parse(s, radix: 16));
      return Colors.blue;
    } catch (_) {
      return Colors.blue;
    }
  }

  // ── Vendor Types tab ──────────────────────────────────────────────────

  Future<void> _createVendorType() async {
    final result = await _showCreateOrEditDialog(title: 'Create Vendor Type');
    if (result == null || _workspaceId == null) return;
    try {
      await _service.createVendorType(
        workspaceId: _workspaceId!,
        name: result['name'],
        color: result['color'],
        description: result['description'].isEmpty ? null : result['description'],
      );
      if (mounted) _showSnack('Vendor type created');
    } catch (e) {
      if (mounted) _showSnack(_duplicateOrError(e, 'creating vendor type'));
    }
  }

  Future<void> _editVendorType(CustomerTypeConfig type) async {
    final result = await _showCreateOrEditDialog(
      title: 'Edit Vendor Type',
      existingName: type.name,
      existingDescription: type.description,
      existingColor: _parseHex(type.color),
    );
    if (result == null || _workspaceId == null) return;
    try {
      await _service.fullUpdateVendorType(
        workspaceId: _workspaceId!, typeId: type.id,
        oldName: type.name, newName: result['name'] as String,
        color: result['color'] as String,
        description: (result['description'] as String).isNotEmpty ? result['description'] as String : null,
      );
      if (mounted) _showSnack('Vendor type updated');
    } catch (e) {
      if (mounted) _showSnack(_duplicateOrError(e, 'updating vendor type'));
    }
  }

  Future<void> _deleteVendorType(CustomerTypeConfig type) async {
    if (_workspaceId == null) return;
    final count = await _service.getVendorTypeUsageCount(_workspaceId!, type.name);
    if (!mounted) return;
    final ok = await _confirmDelete(type.name, count);
    if (ok != true) return;
    try {
      await _service.deleteVendorType(_workspaceId!, type.id);
      if (mounted) _showSnack('Vendor type deleted');
    } catch (e) {
      if (mounted) _showSnack(UserFacingError.uiMessage(e, action: 'deleting vendor type'));
    }
  }

  // ── Vendor Categories tab ─────────────────────────────────────────────

  Future<void> _createVendorCategory() async {
    final result = await _showCreateOrEditDialog(title: 'Create Vendor Category');
    if (result == null || _workspaceId == null) return;
    try {
      await _service.createVendorCategory(
        workspaceId: _workspaceId!,
        name: result['name'],
        color: result['color'],
        description: result['description'].isEmpty ? null : result['description'],
      );
      if (mounted) _showSnack('Vendor category created');
    } catch (e) {
      if (mounted) _showSnack(_duplicateOrError(e, 'creating vendor category'));
    }
  }

  Future<void> _editVendorCategory(CustomerTypeConfig cat) async {
    final result = await _showCreateOrEditDialog(
      title: 'Edit Vendor Category',
      existingName: cat.name,
      existingDescription: cat.description,
      existingColor: _parseHex(cat.color),
    );
    if (result == null || _workspaceId == null) return;
    try {
      await _service.fullUpdateVendorCategory(
        workspaceId: _workspaceId!, catId: cat.id,
        oldName: cat.name, newName: result['name'] as String,
        color: result['color'] as String,
        description: (result['description'] as String).isNotEmpty ? result['description'] as String : null,
      );
      if (mounted) _showSnack('Vendor category updated');
    } catch (e) {
      if (mounted) _showSnack(_duplicateOrError(e, 'updating vendor category'));
    }
  }

  Future<void> _deleteVendorCategory(CustomerTypeConfig cat) async {
    if (_workspaceId == null) return;
    final count = await _service.getVendorCategoryUsageCount(_workspaceId!, cat.name);
    if (!mounted) return;
    final ok = await _confirmDelete(cat.name, count);
    if (ok != true) return;
    try {
      await _service.deleteVendorCategory(_workspaceId!, cat.id);
      if (mounted) _showSnack('Vendor category deleted');
    } catch (e) {
      if (mounted) _showSnack(UserFacingError.uiMessage(e, action: 'deleting vendor category'));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _duplicateOrError(Object e, String action) {
    final s = e.toString();
    if (s.contains('duplicate key') || s.contains('unique constraint')) {
      return 'A type with that name already exists';
    }
    return UserFacingError.uiMessage(e, action: action);
  }

  Future<bool?> _confirmDelete(String name, int usageCount) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete'),
        content: Text(
          usageCount > 0
              ? '"$name" is used by $usageCount vendor(s). Deleting it removes it from the dropdown but existing vendors keep their current value.'
              : 'Delete "$name"?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeList({
    required Stream<List<CustomerTypeConfig>> stream,
    required String emptyLabel,
    required Future<int> Function(String name) getUsage,
    required void Function(CustomerTypeConfig) onEdit,
    required void Function(CustomerTypeConfig) onDelete,
  }) {
    final workspaceId = _workspaceId;
    if (workspaceId == null) {
      return const Center(child: Text('No workspace found'));
    }

    return StreamBuilder<List<CustomerTypeConfig>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(UserFacingError.uiMessage(snapshot.error, action: 'load data')),
          );
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category_outlined, size: 64, color: AppColors.textTertiary),
                const SizedBox(height: 16),
                Text(emptyLabel, style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.base),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final color = _parseHex(item.color);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: Border.all(color: color, width: 1),
                  ),
                  child: Center(
                    child: Text(
                      item.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                title: Row(children: [
                  Text(item.name),
                  if (item.isDefault) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(AppRadius.xs)),
                      child: Text('Default', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                    ),
                  ],
                ]),
                subtitle: item.description != null ? Text(item.description!) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => onEdit(item), tooltip: 'Edit'),
                    IconButton(icon: const Icon(Icons.delete), color: AppColors.error, onPressed: () => onDelete(item), tooltip: 'Delete'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = _workspaceId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Vendor Types'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Types'),
            Tab(text: 'Categories'),
          ],
        ),
      ),
      body: workspaceId == null
          ? const Center(child: Text('No workspace found'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          if (_tabController.index == 0) {
                            _createVendorType();
                          } else {
                            _createVendorCategory();
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 16),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTypeList(
                        stream: _service.getVendorTypes(workspaceId),
                        emptyLabel: 'No vendor types yet',
                        getUsage: (name) => _service.getVendorTypeUsageCount(workspaceId, name),
                        onEdit: _editVendorType,
                        onDelete: _deleteVendorType,
                      ),
                      _buildTypeList(
                        stream: _service.getVendorCategories(workspaceId),
                        emptyLabel: 'No vendor categories yet',
                        getUsage: (name) => _service.getVendorCategoryUsageCount(workspaceId, name),
                        onEdit: _editVendorCategory,
                        onDelete: _deleteVendorCategory,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
