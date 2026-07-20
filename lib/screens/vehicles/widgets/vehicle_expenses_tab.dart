import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../models/vehicle.dart';
import '../../../models/vehicle_expense.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/supabase/vehicle_service.dart';
import '../../../theme/theme.dart';
import '../../../widgets/common/list_skeleton.dart';
import '../../../widgets/forms/stacked_field.dart';
import '../../../utils/numeric_input.dart';

class VehicleExpensesTab extends StatefulWidget {
  final Vehicle vehicle;
  final SupabaseVehicleService vehicleService;

  const VehicleExpensesTab({
    super.key,
    required this.vehicle,
    required this.vehicleService,
  });

  @override
  State<VehicleExpensesTab> createState() => _VehicleExpensesTabState();
}

class _VehicleExpensesTabState extends State<VehicleExpensesTab> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VehicleExpense>>(
      stream: widget.vehicleService.getExpenses(widget.vehicle.id),
      builder: (context, snapshot) {
        final expenses = snapshot.data ?? [];
        final filtered = _filter == 'all'
            ? expenses
            : expenses.where((e) => e.category == _filter).toList();

        return Column(
          children: [
            _buildHeader(context, expenses),
            _buildSummaryRow(expenses),
            _buildFilterChips(),
            Expanded(
              child: snapshot.connectionState == ConnectionState.waiting &&
                      expenses.isEmpty
                  ? const ListSkeleton(itemCount: 3)
                  : filtered.isEmpty
                  ? _buildEmpty(context)
                  : _buildList(context, filtered),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, List<VehicleExpense> expenses) {
    final total = expenses.fold<double>(0.0, (s, e) => s + e.amount);
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.base, AppSpacing.sm, AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${expenses.length} expense${expenses.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                if (expenses.isNotEmpty)
                  Text(
                    'Total: \$${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () => _showExpenseForm(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(List<VehicleExpense> expenses) {
    if (expenses.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final thisMonth = expenses.where((e) =>
        e.date.year == now.year && e.date.month == now.month);
    final thisYear =
        expenses.where((e) => e.date.year == now.year);

    final monthTotal = thisMonth.fold<double>(0.0, (s, e) => s + e.amount);
    final yearTotal = thisYear.fold<double>(0.0, (s, e) => s + e.amount);
    final allTotal = expenses.fold<double>(0.0, (s, e) => s + e.amount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.sm, AppSpacing.base, 0),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              label: 'This Month',
              value: '\$${monthTotal.toStringAsFixed(0)}',
              color: AppColors.info,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _SummaryCard(
              label: 'This Year',
              value: '\$${yearTotal.toStringAsFixed(0)}',
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _SummaryCard(
              label: 'All Time',
              value: '\$${allTotal.toStringAsFixed(0)}',
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: FilterChip(
              label: const Text('All'),
              selected: _filter == 'all',
              onSelected: (_) => setState(() => _filter = 'all'),
              showCheckmark: false,
            ),
          ),
          ...VehicleExpense.categories.map((cat) {
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: FilterChip(
                label: Text(VehicleExpense.categoryLabel(cat)),
                selected: _filter == cat,
                onSelected: (_) => setState(() => _filter = cat),
                showCheckmark: false,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<VehicleExpense> expenses) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, 0, AppSpacing.base, 80),
      itemCount: expenses.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _ExpenseCard(
        expense: expenses[index],
        vehicleService: widget.vehicleService,
        onEdit: () => _showExpenseForm(context, expense: expenses[index]),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.base),
            const Text(
              'No expenses recorded',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Track fuel, tolls, repairs, insurance\nand other vehicle costs.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => _showExpenseForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Add First Expense'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExpenseForm(BuildContext context,
      {VehicleExpense? expense}) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.activeWorkspaceId ??
        authProvider.appUser?.workspaceId ?? '';

    await showDialog<void>(
      context: context,
      builder: (ctx) => _ExpenseFormDialog(
        vehicleId: widget.vehicle.id,
        workspaceId: workspaceId,
        vehicleService: widget.vehicleService,
        existingExpense: expense,
        currentMileage: widget.vehicle.currentMileage,
      ),
    );
  }
}

// ─── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Expense Card ─────────────────────────────────────────────────────────────

class _ExpenseCard extends StatelessWidget {
  final VehicleExpense expense;
  final SupabaseVehicleService vehicleService;
  final VoidCallback onEdit;

  const _ExpenseCard({
    required this.expense,
    required this.vehicleService,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(expense.category);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: AppRadius.badgeRadius,
            ),
            child: Icon(
              _categoryIcon(expense.category),
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  VehicleExpense.categoryLabel(expense.category),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  _formatDate(expense.date),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if ((expense.vendor ?? '').isNotEmpty)
                  Text(
                    expense.vendor!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                if ((expense.description ?? '').isNotEmpty)
                  Text(
                    expense.description!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (expense.odometer != null)
                  Row(
                    children: [
                      const Icon(Icons.speed_outlined,
                          size: 11, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        '${expense.odometer} mi',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${expense.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 18, color: AppColors.textTertiary),
                onSelected: (v) async {
                  if (v == 'edit') {
                    onEdit();
                  } else if (v == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Expense'),
                        content: const Text(
                            'Remove this expense record permanently?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: AppColors.error),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await vehicleService.deleteExpense(expense.id);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  static Color _categoryColor(String cat) {
    switch (cat) {
      case 'fuel':
        return AppColors.warning;
      case 'repair':
        return AppColors.error;
      case 'toll':
        return AppColors.info;
      case 'parking':
        return AppColors.primary;
      case 'insurance':
        return AppColors.success;
      case 'registration':
        return AppColors.invoiceAccent;
      case 'wash':
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }

  static IconData _categoryIcon(String cat) {
    switch (cat) {
      case 'fuel':
        return Icons.local_gas_station_outlined;
      case 'repair':
        return Icons.build_outlined;
      case 'toll':
        return Icons.toll_outlined;
      case 'parking':
        return Icons.local_parking_outlined;
      case 'insurance':
        return Icons.shield_outlined;
      case 'registration':
        return Icons.assignment_outlined;
      case 'wash':
        return Icons.local_car_wash_outlined;
      default:
        return Icons.receipt_outlined;
    }
  }
}

// ─── Expense Form Dialog ──────────────────────────────────────────────────────

class _ExpenseFormDialog extends StatefulWidget {
  final String vehicleId;
  final String workspaceId;
  final SupabaseVehicleService vehicleService;
  final VehicleExpense? existingExpense;
  final int currentMileage;

  const _ExpenseFormDialog({
    required this.vehicleId,
    required this.workspaceId,
    required this.vehicleService,
    this.existingExpense,
    required this.currentMileage,
  });

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _descController;
  late TextEditingController _vendorController;
  late TextEditingController _odometerController;
  late String _category;
  late DateTime _date;
  bool _saving = false;

  bool get _isEditing => widget.existingExpense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existingExpense;
    _category = e?.category ?? 'fuel';
    _date = e?.date ?? DateTime.now();
    _amountController = TextEditingController(
        text: e != null && e.amount > 0 ? e.amount.toStringAsFixed(2) : '');
    _descController =
        TextEditingController(text: e?.description ?? '');
    _vendorController =
        TextEditingController(text: e?.vendor ?? '');
    _odometerController = TextEditingController(
        text: e?.odometer?.toString() ?? '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    _vendorController.dispose();
    _odometerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDialogHeader(),
              const Divider(height: 1, color: AppColors.cardBorder),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StackedField(
                        label: 'Category *',
                        child: DropdownButtonFormField<String>(
                          value: _category,
                          decoration: const InputDecoration(),
                          items: VehicleExpense.categories
                              .map((cat) => DropdownMenuItem(
                                    value: cat,
                                    child: Text(
                                        VehicleExpense.categoryLabel(cat)),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _category = v ?? _category),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      Row(
                        children: [
                          Expanded(
                            child: StackedField(
                              label: 'Amount *',
                              child: TextFormField(
                                controller: _amountController,
                                keyboardType: NumericInput.keyboard,
                                inputFormatters: NumericInput.currency,
                                decoration: const InputDecoration(
                                    prefixText: '\$ '),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  if (double.tryParse(v.trim()) == null) {
                                    return 'Invalid amount';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: StackedField(
                              label: 'Date *',
                              child: InkWell(
                                onTap: _pickDate,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    suffixIcon: Icon(
                                        Icons.calendar_today_outlined,
                                        size: 18),
                                  ),
                                  child: Text(_formatDate(_date)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.base),
                      StackedField(
                        label: 'Vendor / Location',
                        child: TextFormField(
                          controller: _vendorController,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Shell, Joe\'s Auto',
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      StackedField(
                        label: 'Description',
                        child: TextFormField(
                          controller: _descController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'Notes or details',
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      StackedField(
                        label: 'Odometer Reading (mi)',
                        child: TextFormField(
                          controller: _odometerController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            hintText:
                                'Current: ${widget.currentMileage} mi',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.cardBorder),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(_isEditing
                              ? 'Save Changes'
                              : 'Add Expense'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.base, AppSpacing.sm, AppSpacing.base),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: AppRadius.badgeRadius,
            ),
            child: const Icon(Icons.receipt_outlined,
                size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _isEditing ? 'Edit Expense' : 'Add Expense',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final expense = VehicleExpense(
        id: widget.existingExpense?.id ?? '',
        workspaceId: widget.workspaceId,
        vehicleId: widget.vehicleId,
        date: _date,
        category: _category,
        amount: double.parse(_amountController.text.trim()),
        description: _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        vendor: _vendorController.text.trim().isEmpty
            ? null
            : _vendorController.text.trim(),
        odometer: int.tryParse(_odometerController.text.trim()),
      );

      if (_isEditing) {
        await widget.vehicleService.updateExpense(expense);
      } else {
        await widget.vehicleService.addExpense(expense);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';
}
