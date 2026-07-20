import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/document_status.dart';
import '../../../models/document_type.dart';
import '../../../models/generated_document.dart';
import '../../../providers/workspace_provider.dart';
import '../../../theme/theme.dart';
import '../../../utils/currency_utils.dart';
import '../../../utils/document_ui_helpers.dart';
import '../../../widgets/table/hover_action_row.dart';
import '../../../widgets/table/table_view_styles.dart';

// Column widths
const double kDocTableColType = 180;
const double kDocTableColRecipient = 200;
const double kDocTableColStatus = 120;
const double kDocTableColAmount = 110;
const double kDocTableColDate = 130;
const double kDocTableColDueDate = 110;
const double kDocTableColGap = 12;

class DocumentTableRow extends StatelessWidget {
  final GeneratedDocument document;
  final bool isSelected;
  final bool selectionMode;
  final Map<String, double> columnWidths;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final bool isHighlighted;

  const DocumentTableRow({
    super.key,
    required this.document,
    this.isSelected = false,
    this.selectionMode = false,
    this.columnWidths = const {},
    this.onSelectionChanged,
    this.onLongPress,
    this.onTap,
    this.isHighlighted = false,
  });

  double _colW(String id, double defaultWidth) =>
      columnWidths[id] ?? defaultWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: HoverActionRow(
        actionWidth: 40,
        actions: [_buildActionsMenu(context)],
        builder: (isHovered) => InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08)
                  : isHighlighted
                  ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.05)
                  : isHovered
                  ? Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5)
                  : Colors.transparent,
              border: Border(
                bottom: TableViewStyles.rowDivider(context),
                left: isHighlighted
                    ? BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      )
                    : BorderSide.none,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
              child: Row(
                children: [
                  if (selectionMode) ...[
                    SizedBox(
                      width: 40,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (val) =>
                            onSelectionChanged?.call(val ?? false),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  SizedBox(
                    width: _colW('type', kDocTableColType),
                    child: _buildTypeCell(context),
                  ),
                  const SizedBox(width: kDocTableColGap),
                  SizedBox(
                    width: _colW('recipient', kDocTableColRecipient),
                    child: _buildRecipientCell(),
                  ),
                  const SizedBox(width: kDocTableColGap),
                  SizedBox(
                    width: _colW('status', kDocTableColStatus),
                    child: _buildStatusCell(),
                  ),
                  const SizedBox(width: kDocTableColGap),
                  SizedBox(
                    width: _colW('amount', kDocTableColAmount),
                    child: _buildAmountCell(context),
                  ),
                  const SizedBox(width: kDocTableColGap),
                  SizedBox(
                    width: _colW('date', kDocTableColDate),
                    child: _buildDateCell(),
                  ),
                  const SizedBox(width: kDocTableColGap),
                  SizedBox(
                    width: _colW('dueDate', kDocTableColDueDate),
                    child: _buildDueDateCell(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionsMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'view', child: Text('View')),
      ],
      onSelected: (value) {
        if (value == 'view') onTap?.call();
      },
    );
  }

  Widget _buildTypeCell(BuildContext context) {
    final typeColor = getDocumentTypeColor(document.documentType);
    final label = document.documentNumber != null
        ? '${document.documentType.displayName} #${document.documentNumber}'
        : document.documentType.displayName;

    return Row(
      children: [
        Icon(
          getDocumentTypeIcon(document.documentType),
          size: 16,
          color: typeColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildRecipientCell() {
    final name = document.preparedFor?.name ?? document.customerName ?? '—';
    return Text(
      name,
      style: const TextStyle(fontSize: 13),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildStatusCell() {
    final color = getDocumentStatusColor(document.status);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            document.status.displayName,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildAmountCell(BuildContext context) {
    if (document.totalAmount <= 0) {
      return const Text('—', style: TextStyle(fontSize: 13, color: AppColors.textTertiary));
    }
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    return Text(
      CurrencyUtils.formatCurrency(document.totalAmount, currencyCode),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildDateCell() {
    return Text(
      document.formattedCreatedAt,
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }

  Widget _buildDueDateCell() {
    if (document.dueDate == null) {
      return const Text('—', style: TextStyle(fontSize: 13, color: AppColors.textTertiary));
    }
    return Text(
      DateFormat('MM/dd/yyyy').format(document.dueDate!),
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }
}
