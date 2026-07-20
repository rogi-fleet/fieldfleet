import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/document_type.dart';
import '../models/generated_document.dart';
import '../models/document_line_item.dart';
import '../models/file_attachment.dart';
import '../providers/workspace_provider.dart';
import '../utils/currency_utils.dart';
import '../theme/theme.dart';

/// A live preview widget for documents showing logo, headers, content,
/// line items table, attached files, and footer.
class DocumentPreviewWidget extends StatelessWidget {
  final String? logoUrl;
  final String templateName;
  final String? documentNumber;
  final DateTime? documentDate;
  final DateTime? expiryDate;
  final String expiryDateLabel;
  final DocumentContactInfo? preparedBy;
  final DocumentContactInfo? preparedFor;
  final String renderedContent;
  final List<DocumentLineItem> lineItems;
  final LineItemVisibility lineItemVisibility;
  final DocumentType? documentType;
  final List<FileAttachment> attachedPhotos;
  final String? footerContent;
  final bool showSignaturePlaceholder;
  final bool collectTax;
  final String taxName;
  final double taxRate;

  // Deposit application
  final double depositAmount;
  final String? depositLabel;

  // Holdback (retainage) withheld from this invoice
  final double retainagePercent;
  final double retainageAmount;

  // Invoice-level discount (flat, pre-tax). [M004]
  final double discountAmount;

  // Interactive edit callbacks — when non-null, edit affordances are shown
  final VoidCallback? onTemplateNameTap;
  final VoidCallback? onDocumentDateTap;
  final VoidCallback? onExpiryDateTap;
  final VoidCallback? onPreparedByTap;
  final VoidCallback? onPreparedForTap;
  final VoidCallback? onFooterTap;
  final VoidCallback? onContentTap;
  final VoidCallback? onLineItemsTap;
  final VoidCallback? onPhotosTap;

  const DocumentPreviewWidget({
    super.key,
    this.logoUrl,
    required this.templateName,
    this.documentNumber,
    this.documentDate,
    this.expiryDate,
    this.expiryDateLabel = 'Expires',
    this.preparedBy,
    this.preparedFor,
    required this.renderedContent,
    this.lineItems = const [],
    this.lineItemVisibility = LineItemVisibility.all,
    this.documentType,
    this.attachedPhotos = const [],
    this.footerContent,
    this.showSignaturePlaceholder = false,
    this.collectTax = false,
    this.taxName = 'Tax',
    this.taxRate = 0,
    this.depositAmount = 0,
    this.depositLabel,
    this.retainagePercent = 0,
    this.retainageAmount = 0,
    this.discountAmount = 0,
    this.onTemplateNameTap,
    this.onDocumentDateTap,
    this.onExpiryDateTap,
    this.onPreparedByTap,
    this.onPreparedForTap,
    this.onFooterTap,
    this.onContentTap,
    this.onLineItemsTap,
    this.onPhotosTap,
  });

  List<DocumentLineItem> get _visibleLineItems {
    switch (lineItemVisibility) {
      case LineItemVisibility.none:
        return [];
      case LineItemVisibility.topLevel:
        return lineItems
            .where((item) => item.isTopLevel && item.isVisible)
            .toList();
      case LineItemVisibility.all:
        return lineItems.where((item) => item.isVisible).toList();
    }
  }

  double get _totalAmount {
    return lineItems
        .where((item) => item.isItem && item.isVisible)
        .fold(0.0, (sum, item) => sum + item.total);
  }

  // Tax base excludes non-taxable lines (per-line is_taxable). [M002]
  double get _taxableAmount {
    return lineItems
        .where((item) => item.isItem && item.isVisible && item.isTaxable)
        .fold(0.0, (sum, item) => sum + item.total);
  }

  double get _previewTaxAmount {
    if (!(collectTax && taxRate > 0)) return 0.0;
    var base = _taxableAmount;
    // A pre-tax discount shrinks the taxable base (apportioned by taxable
    // share), matching GeneratedDocument.computedTaxAmount. [M004]
    if (discountAmount > 0 && _totalAmount > 0) {
      base -= discountAmount * (_taxableAmount / _totalAmount);
      if (base < 0) base = 0;
    }
    return base * (taxRate / 100);
  }

  // Drop a leading "# ..." H1 heading from the rendered content. Templates
  // commonly start with `# Invoice {{number}}` etc., which now duplicates the
  // template name + document number shown in the preview header. Also drop
  // a leading "## ..." H2 if it's the first heading-level content — every
  // template opens with its section heading (`## Scope`,
  // `## Restoration Scope`, `## Scope of Work`, …) which lands right under
  // the widget's hardcoded "Scope" label and reads as a visible duplicate.
  // We only peel past front-matter (blank lines, `---` rules, `**key:** val`
  // metadata) before looking for the H2 — anything else means body prose has
  // started and the H2 belongs to a later section that should stay.
  String _contentWithoutLeadingTitle(String content) {
    final lines = content.split('\n');

    void removeAt(int idx) {
      lines.removeAt(idx);
      while (idx < lines.length && lines[idx].trim().isEmpty) {
        lines.removeAt(idx);
      }
    }

    var stripped = false;

    // Skip leading blanks.
    var i = 0;
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    if (i < lines.length && lines[i].trimLeft().startsWith('# ')) {
      removeAt(i);
      stripped = true;
    }

    // Walk past front-matter looking for the first H2. A line is
    // "front-matter" if it's blank, a `---` rule, or a `**...:**` metadata
    // line. Anything else stops the walk.
    bool isFrontMatter(String line) {
      final t = line.trim();
      if (t.isEmpty) return true;
      if (t.startsWith('---')) return true;
      if (t.startsWith('**') && t.contains(':')) return true;
      return false;
    }

    var j = i;
    while (j < lines.length && isFrontMatter(lines[j])) {
      j++;
    }
    if (j < lines.length && lines[j].trimLeft().startsWith('## ')) {
      removeAt(j);
      stripped = true;
    }

    return stripped ? lines.join('\n') : content;
  }

  // Currency formatting helper
  String _formatCurrency(BuildContext context, double amount) {
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    return CurrencyUtils.formatCurrency(amount, currencyCode);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with logo
            _buildHeader(context),
            const SizedBox(height: 24),

            // Prepared By / Prepared For
            if (preparedBy != null || preparedFor != null)
              _buildContactHeaders(context),

            // Divider line
            Container(
              height: 3,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.base),
              decoration: BoxDecoration(
                color: const Color(0xFFD4A843),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Main content
            if (renderedContent.isNotEmpty)
              if (onContentTap != null)
                InkWell(
                  onTap: onContentTap,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: _buildContentSection(context),
                )
              else
                _buildContentSection(context),

            // Line items table
            if (_visibleLineItems.isNotEmpty) ...[
              const SizedBox(height: 24),
              if (onLineItemsTap != null)
                InkWell(
                  onTap: onLineItemsTap,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: _buildLineItemsTable(context),
                )
              else
                _buildLineItemsTable(context),
            ],

            // Attached files
            if (attachedPhotos.isNotEmpty) ...[
              const SizedBox(height: 24),
              if (onPhotosTap != null)
                InkWell(
                  onTap: onPhotosTap,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: _buildPhotosSection(context),
                )
              else
                _buildPhotosSection(context),
            ],

            // Signature placeholder
            if (showSignaturePlaceholder) ...[
              const SizedBox(height: 32),
              _buildSignaturePlaceholder(context),
            ],

            // Footer
            if (footerContent != null && footerContent!.isNotEmpty) ...[
              const SizedBox(height: 24),
              Container(height: 1, color: AppColors.cardBorder),
              const SizedBox(height: 12),
              if (onFooterTap != null)
                _buildEditableField(
                  context: context,
                  onTap: onFooterTap,
                  child: Text(
                    footerContent!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                Text(
                  footerContent!,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditableField({
    required BuildContext context,
    required Widget child,
    VoidCallback? onTap,
    IconData icon = Icons.arrow_back,
  }) {
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.cardBorder,
            style: BorderStyle.solid,
          ),
          color: AppColors.surfaceAlt.withValues(alpha: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: child),
            const SizedBox(width: 6),
            Icon(icon, size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo
        if (logoUrl != null && logoUrl!.isNotEmpty)
          Container(
            width: 80,
            height: 80,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: CachedNetworkImage(
                imageUrl: logoUrl!,
                fit: BoxFit.contain,
                errorWidget: (context, url, error) => Container(
                  color: AppColors.cardBorder,
                  child: Icon(Icons.business, color: AppColors.textTertiary),
                ),
              ),
            ),
          ),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _buildEditableField(
                      context: context,
                      onTap: onTemplateNameTap,
                      child: Text(
                        templateName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  if (documentNumber != null && documentNumber!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        documentNumber!,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _buildEditableField(
                context: context,
                onTap: onDocumentDateTap,
                icon: Icons.edit,
                child: Text(
                  'Date Issued: ${DateFormat('MMMM dd, yyyy').format(documentDate ?? DateTime.now())}',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              if (expiryDate != null) ...[
                const SizedBox(height: 4),
                _buildEditableField(
                  context: context,
                  onTap: onExpiryDateTap,
                  icon: Icons.edit,
                  child: Text(
                    '$expiryDateLabel: ${DateFormat('MMMM dd, yyyy').format(expiryDate!)}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContactHeaders(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preparedBy != null && !preparedBy!.isEmpty)
          Expanded(
            child: _buildContactColumn(
              context,
              'FROM',
              preparedBy!,
              onTap: onPreparedByTap,
            ),
          ),
        if (preparedFor != null && !preparedFor!.isEmpty)
          Expanded(
            child: _buildContactColumn(
              context,
              'TO',
              preparedFor!,
              onTap: onPreparedForTap,
            ),
          ),
      ],
    );
  }

  Widget _buildContactColumn(
    BuildContext context,
    String title,
    DocumentContactInfo contact, {
    VoidCallback? onTap,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.arrow_back, size: 13, color: AppColors.textTertiary),
            ],
          ],
        ),
        const SizedBox(height: 4),
        if (contact.name != null && contact.name!.isNotEmpty)
          Text(
            contact.name!,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        if (contact.organization != null && contact.organization!.isNotEmpty)
          Text(
            contact.organization!,
            style: TextStyle(color: AppColors.textPrimary),
          ),
        if (contact.phone != null && contact.phone!.isNotEmpty)
          Text(
            contact.phone!,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        if (contact.email != null && contact.email!.isNotEmpty)
          Text(
            contact.email!,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        if (contact.address != null && contact.address!.isNotEmpty)
          Text(
            contact.address!,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
      ],
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.cardBorder),
          color: AppColors.surfaceAlt.withValues(alpha: 0.5),
        ),
        child: content,
      ),
    );
  }

  Widget _buildContentSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Scope',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (onContentTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.arrow_back, size: 14, color: AppColors.textTertiary),
            ],
          ],
        ),
        const SizedBox(height: 8),
        MarkdownBody(
          softLineBreak: true,
          data: _contentWithoutLeadingTitle(renderedContent),
          styleSheet: MarkdownStyleSheet(
            h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            p: const TextStyle(fontSize: 14),
            tableHead: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            tableBody: const TextStyle(fontSize: 12),
            tableCellsPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 6,
            ),
          ),
        ),
      ],
    );
  }

  List<LineItemColumn> get _columns {
    final fromType = documentType?.lineItemColumns;
    if (fromType == null || fromType.isEmpty) {
      return const [
        LineItemColumn.description,
        LineItemColumn.quantity,
        LineItemColumn.unitPrice,
        LineItemColumn.total,
      ];
    }
    return fromType;
  }

  String _columnLabel(LineItemColumn col) {
    switch (col) {
      case LineItemColumn.description:
        return 'Description';
      case LineItemColumn.quantity:
        return 'Qty';
      case LineItemColumn.unit:
        return 'Unit';
      case LineItemColumn.unitPrice:
        return 'Price';
      case LineItemColumn.total:
        return 'Total';
      case LineItemColumn.bidPrice:
        return 'Bid Price';
      case LineItemColumn.bidTotal:
        return 'Bid Total';
    }
  }

  double? _columnWidth(LineItemColumn col) {
    switch (col) {
      case LineItemColumn.description:
        return null; // Expanded flex
      case LineItemColumn.quantity:
        return 60;
      case LineItemColumn.unit:
        return 60;
      case LineItemColumn.unitPrice:
      case LineItemColumn.bidPrice:
        return 80;
      case LineItemColumn.total:
      case LineItemColumn.bidTotal:
        return 90;
    }
  }

  Widget _headerCell(LineItemColumn col) {
    final label = _columnLabel(col);
    const style = TextStyle(fontWeight: FontWeight.w600, fontSize: 12);
    if (col == LineItemColumn.description) {
      return Expanded(flex: 4, child: Text(label, style: style));
    }
    return SizedBox(
      width: _columnWidth(col),
      child: Text(label, textAlign: TextAlign.right, style: style),
    );
  }

  Widget _buildLineItemsTable(BuildContext context) {
    final visibleItems = _visibleLineItems;
    final topLevelItems = visibleItems
        .where((i) => i.parentId == null)
        .toList();
    final columns = _columns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Line Items',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (onLineItemsTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.arrow_back, size: 14, color: AppColors.textTertiary),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            children: [
              // Header row
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(7),
                  ),
                ),
                child: Row(
                  children: [
                    for (final col in columns) _headerCell(col),
                  ],
                ),
              ),

              // Data rows
              ...topLevelItems.asMap().entries.map((entry) {
                final item = entry.value;
                return _buildLineItemRow(
                  context,
                  item,
                  visibleItems,
                  columns: columns,
                  isLast: entry.key == topLevelItems.length - 1,
                );
              }),

              // Totals section — skipped for document types whose line items
              // have no priced columns (e.g. request-for-bid before the
              // vendor fills in their prices).
              if (columns.contains(LineItemColumn.total))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    border: Border(
                      top: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(7),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (collectTax && taxRate > 0) ...[
                        _totalRow(
                          context,
                          'Subtotal',
                          _totalAmount,
                          color: AppColors.primaryDark,
                        ),
                        if (discountAmount > 0) ...[
                          const SizedBox(height: 4),
                          _totalRow(
                            context,
                            'Discount',
                            -discountAmount,
                            color: AppColors.primaryDark,
                          ),
                        ],
                        const SizedBox(height: 4),
                        _totalRow(
                          context,
                          '$taxName (${taxRate.toStringAsFixed(1)}%)',
                          _previewTaxAmount,
                          color: AppColors.primaryDark,
                        ),
                        Divider(
                          height: 12,
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ],
                      // Grand Total row
                      ..._buildGrandTotalRows(context),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dataCell(
    BuildContext context,
    LineItemColumn col,
    DocumentLineItem item,
    List<DocumentLineItem> allItems, {
    required bool isGroup,
  }) {
    String text;
    FontWeight weight = FontWeight.normal;
    switch (col) {
      case LineItemColumn.description:
        // Description column is composed by _descriptionCell, not this helper.
        text = '';
        break;
      case LineItemColumn.quantity:
        text = isGroup ? '' : item.formattedQuantity;
        break;
      case LineItemColumn.unit:
        text = isGroup ? '' : (item.unit ?? '');
        break;
      case LineItemColumn.unitPrice:
        text = isGroup ? '' : _formatCurrency(context, item.unitPrice);
        break;
      case LineItemColumn.total:
        if (isGroup) {
          text = _formatCurrency(
            context,
            _calculateGroupTotal(item.id, allItems),
          );
          weight = FontWeight.w600;
        } else {
          text = _formatCurrency(context, item.total);
        }
        break;
      case LineItemColumn.bidPrice:
        text = isGroup || item.vendorBidPrice == null
            ? ''
            : _formatCurrency(context, item.vendorBidPrice!);
        break;
      case LineItemColumn.bidTotal:
        if (isGroup) {
          text = '';
        } else {
          final bidTotal = item.vendorBidTotal;
          text = bidTotal == null ? '' : _formatCurrency(context, bidTotal);
        }
        break;
    }
    return SizedBox(
      width: _columnWidth(col),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 13, fontWeight: weight),
      ),
    );
  }

  Widget _descriptionCell(DocumentLineItem item, {required bool isGroup}) {
    return Expanded(
      flex: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.name,
            style: TextStyle(
              fontWeight: isGroup ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (item.description != null &&
              item.description!.isNotEmpty &&
              item.description!.trim() != item.name.trim())
            Text(
              item.description!,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildLineItemRow(
    BuildContext context,
    DocumentLineItem item,
    List<DocumentLineItem> allItems, {
    required List<LineItemColumn> columns,
    int depth = 0,
    bool isLast = false,
  }) {
    final children = allItems.where((i) => i.parentId == item.id).toList();
    final isGroup = item.isGroup;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(
            left: 12 + (depth * 16.0),
            right: 12,
            top: 10,
            bottom: 10,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: isLast && children.isEmpty
                  ? BorderSide.none
                  : BorderSide(color: AppColors.cardBorder),
            ),
          ),
          child: Row(
            children: [
              for (final col in columns)
                if (col == LineItemColumn.description)
                  _descriptionCell(item, isGroup: isGroup)
                else
                  _dataCell(context, col, item, allItems, isGroup: isGroup),
            ],
          ),
        ),
        // Render children
        ...children.asMap().entries.map((entry) {
          return _buildLineItemRow(
            context,
            entry.value,
            allItems,
            columns: columns,
            depth: depth + 1,
            isLast: isLast && entry.key == children.length - 1,
          );
        }),
      ],
    );
  }

  Widget _totalRow(
    BuildContext context,
    String label,
    double amount, {
    bool bold = false,
    double fontSize = 13,
    Color? color,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 60),
        const SizedBox(width: 80),
        SizedBox(
          width: 90,
          child: Text(
            _formatCurrency(context, amount),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: fontSize,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildGrandTotalRows(BuildContext context) {
    final hasTax = collectTax && taxRate > 0;
    final grandTotal = (hasTax ? _totalAmount + _previewTaxAmount : _totalAmount) -
        discountAmount;
    final hasDeposit = depositAmount > 0;
    final hasHoldback = retainageAmount > 0;
    final balanceDue = (grandTotal - depositAmount - retainageAmount)
        .clamp(0.0, double.infinity);
    final showBalanceBlock = hasDeposit || hasHoldback;

    return [
      _totalRow(
        context,
        hasTax ? 'Grand Total' : 'Total',
        grandTotal,
        bold: true,
        fontSize: showBalanceBlock ? 13 : 16,
        color: AppColors.primary,
      ),
      if (hasDeposit) ...[
        const SizedBox(height: 4),
        _totalRow(
          context,
          depositLabel ?? 'Less Deposit',
          -depositAmount,
          color: AppColors.textSecondary,
        ),
      ],
      if (hasHoldback) ...[
        const SizedBox(height: 4),
        _totalRow(
          context,
          'Less Holdback (${retainagePercent.toStringAsFixed(1)}%)',
          -retainageAmount,
          color: AppColors.warningDark,
        ),
      ],
      if (showBalanceBlock) ...[
        Divider(
          height: 12,
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
        _totalRow(
          context,
          'Balance Due',
          balanceDue,
          bold: true,
          fontSize: 16,
          color: AppColors.primary,
        ),
      ],
    ];
  }

  double _calculateGroupTotal(String groupId, List<DocumentLineItem> allItems) {
    double total = 0;
    for (final child in allItems.where((i) => i.parentId == groupId)) {
      if (!child.isVisible) continue;
      if (child.isGroup) {
        total += _calculateGroupTotal(child.id, allItems);
      } else {
        total += child.total;
      }
    }
    return total;
  }

  Widget _buildPhotosSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Attached Files',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (onPhotosTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.arrow_back, size: 14, color: AppColors.textTertiary),
            ],
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: attachedPhotos.length,
          itemBuilder: (context, index) {
            final file = attachedPhotos[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: file.isImage
                  ? CachedNetworkImage(
                      imageUrl: file.thumbnailUrl ?? file.fileUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.cardBorder,
                        child: Icon(
                          Icons.broken_image,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    )
                  : _buildFileTile(file),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFileTile(FileAttachment file) {
    return Container(
      color: AppColors.surfaceAlt,
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_iconForFile(file), color: AppColors.primary, size: 28),
          const SizedBox(height: 6),
          Text(
            file.fileExtension,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            file.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  IconData _iconForFile(FileAttachment file) {
    if (file.isPDF) return Icons.picture_as_pdf;
    if (file.mimeType.contains('spreadsheet') ||
        file.mimeType.contains('excel')) {
      return Icons.table_chart;
    }
    if (file.isDocument) return Icons.description;
    return Icons.insert_drive_file;
  }

  Widget _buildSignaturePlaceholder(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SIGNATURE',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 60,
            width: 200,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.textTertiary)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Date: _________________',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
