import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:taskfleet_ops/models/document_line_item.dart';
import 'package:signature/signature.dart';
import 'package:http/http.dart' as http;
import '../../config/supabase_config.dart';
import '../../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class PublicDocumentSignScreen extends StatefulWidget {
  final String token;

  const PublicDocumentSignScreen({super.key, required this.token});

  @override
  State<PublicDocumentSignScreen> createState() =>
      _PublicDocumentSignScreenState();
}

class _PublicDocumentSignScreenState extends State<PublicDocumentSignScreen> {
  bool _isLoading = true;
  bool _isSigning = false;
  String? _error;
  Map<String, dynamic>? _document;
  Map<String, dynamic>? _link;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _signatureController = SignatureController(
    penStrokeWidth: 2.5,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  String? get _linkedRecipientEmail {
    final email = _link?['recipientEmail'] as String?;
    if (email == null) return null;
    final trimmed = email.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void initState() {
    super.initState();
    _resolveToken();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  String _extractErrorMessage(dynamic decodedBody, String fallback) {
    if (decodedBody is Map<String, dynamic>) {
      for (final key in const ['error', 'msg', 'message']) {
        final value = decodedBody[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
    return fallback;
  }

  Future<void> _resolveToken() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${SupabaseConfig.url}/functions/v1/document-signing'),
        headers: {
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({'action': 'resolve', 'token': widget.token}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        setState(() {
          _error = _extractErrorMessage(data, 'Unable to open signing link');
          _isLoading = false;
        });
        return;
      }

      if (data is! Map<String, dynamic>) {
        setState(() {
          _error = 'Unexpected response while opening signing link';
          _isLoading = false;
        });
        return;
      }

      final link = data['link'] as Map<String, dynamic>?;
      final recipientEmail = link?['recipientEmail'] as String?;
      if (recipientEmail != null && recipientEmail.isNotEmpty) {
        _emailController.text = recipientEmail;
      }

      setState(() {
        _document = data['document'] as Map<String, dynamic>?;
        _link = link;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Unable to load document: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _signDocument() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter your full name')));
      return;
    }
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter your email')));
      return;
    }
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address')),
      );
      return;
    }
    if (_signatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add your signature')),
      );
      return;
    }

    final signatureBytes = await _signatureController.toPngBytes();
    if (!mounted) return;
    if (signatureBytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not read signature')));
      return;
    }

    setState(() => _isSigning = true);

    try {
      final response = await http.post(
        Uri.parse('${SupabaseConfig.url}/functions/v1/document-signing'),
        headers: {
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({
          'action': 'sign',
          'token': widget.token,
          'signedByName': _nameController.text.trim(),
          'signedByEmail': _emailController.text.trim(),
          'signaturePngBase64': base64Encode(signatureBytes),
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(_extractErrorMessage(data, 'Failed to sign document'));
      }

      await _resolveToken();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document signed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Signing failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSigning = false);
      }
    }
  }

  Widget _buildLineItemsSection(Map<String, dynamic> document) {
    final rawItems = document['lineItems'] as List?;
    final visibility = LineItemVisibility.fromString(
      document['lineItemVisibility'] as String?,
    );
    if (rawItems == null ||
        rawItems.isEmpty ||
        visibility == LineItemVisibility.none) {
      return const SizedBox.shrink();
    }

    final items = rawItems.cast<Map<String, dynamic>>();
    final visibleItems = items.where((i) {
      final isVisible = i['isVisible'] as bool? ?? true;
      final type = i['type'] as String? ?? 'item';
      if (!isVisible) return false;
      if (visibility == LineItemVisibility.topLevel && i['parentId'] != null) {
        return false;
      }
      return type == 'item';
    }).toList();

    if (visibleItems.isEmpty) return const SizedBox.shrink();

    double subtotal = 0;
    double taxableSubtotal = 0; // tax base excludes non-taxable lines [M002]
    for (final item in visibleItems) {
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final price = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
      final lineTotal = qty * price;
      subtotal += lineTotal;
      if (item['isTaxable'] as bool? ?? true) {
        taxableSubtotal += lineTotal;
      }
    }

    final collectTax = document['collectTax'] as bool? ?? false;
    final taxRate = (document['taxRate'] as num?)?.toDouble() ?? 0.0;
    final taxName = document['taxName'] as String? ?? 'Tax';
    final taxAmount = collectTax ? taxableSubtotal * (taxRate / 100) : 0.0;
    final total = subtotal + taxAmount;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Line Items',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1),
                },
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: AppColors.cardBorder,
                    width: 0.5,
                  ),
                ),
                children: [
                  TableRow(
                    children: [
                      _tableHeader('Description'),
                      _tableHeader('Qty'),
                      _tableHeader('Price'),
                      _tableHeader('Total'),
                    ],
                  ),
                  ...visibleItems.map((item) {
                    final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
                    final price =
                        (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
                    final lineTotal = qty * price;
                    return TableRow(
                      children: [
                        _tableCell(item['name'] as String? ?? ''),
                        _tableCell(
                          qty == qty.roundToDouble()
                              ? qty.toInt().toString()
                              : qty.toStringAsFixed(2),
                        ),
                        _tableCell('\$${price.toStringAsFixed(2)}'),
                        _tableCell('\$${lineTotal.toStringAsFixed(2)}'),
                      ],
                    );
                  }),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Subtotal: \$${subtotal.toStringAsFixed(2)}'),
                    if (collectTax && taxRate > 0)
                      Text(
                        '$taxName (${taxRate.toStringAsFixed(1)}%): \$${taxAmount.toStringAsFixed(2)}',
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Total: \$${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
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

  Widget _tableHeader(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
    ),
  );

  Widget _tableCell(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(text, style: const TextStyle(fontSize: 13)),
  );

  static String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.month}/${date.day}/${date.year}';
    } catch (_) {
      return isoDate;
    }
  }

  static bool _isValidEmail(String email) {
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final status = document?['status'] as String?;
    final isSigned = status == 'signed';

    return Scaffold(
      appBar: AppBar(title: const Text('Document Signing')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _resolveToken,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : document == null
          ? const Center(child: Text('Document not found'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.base),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (document['templateName'] as String?) ??
                                    'Document',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              if (_link?['expiresAt'] != null)
                                Text(
                                  'Link expires: ${_formatDate(_link!['expiresAt'])}',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Chip(
                                label: Text(
                                  isSigned ? 'Signed' : 'Pending Signature',
                                ),
                                backgroundColor: isSigned
                                    ? AppColors.success.withAlpha(40)
                                    : AppColors.warning.withAlpha(40),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.base),
                          child: MarkdownBody(
                            data:
                                (document['renderedContent'] as String?) ?? '',
                            selectable: true,
                          ),
                        ),
                      ),
                      _buildLineItemsSection(document),
                      const SizedBox(height: 16),
                      if (isSigned) ...[
                        Card(
                          color: AppColors.successLight,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.base),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'This document is already signed.',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Signed by: ${document['signedByName'] ?? 'Unknown'}',
                                ),
                                if (document['signedByEmail'] != null)
                                  Text('Email: ${document['signedByEmail']}'),
                                if (document['signedAt'] != null)
                                  Text('Signed at: ${document['signedAt']}'),
                                if (document['signatureUrl'] != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    height: 110,
                                    width: 280,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppColors.cardBorder,
                                      ),
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: document['signatureUrl'],
                                      fit: BoxFit.contain,
                                      errorWidget: (_, __, ___) =>
                                          const Center(child: Icon(Icons.draw)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.base),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                StackedField(
                                  label: 'Full Name',
                                  child: TextField(
                                    controller: _nameController,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                StackedField(
                                  label: 'Email',
                                  child: TextField(
                                    controller: _emailController,
                                    readOnly: _linkedRecipientEmail != null,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: InputDecoration(
                                      border: const OutlineInputBorder(),
                                      helperText: _linkedRecipientEmail != null
                                          ? 'This signing link is tied to $_linkedRecipientEmail'
                                          : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Signature',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 160,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppColors.cardBorder,
                                    ),
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    color: Colors.white,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    child: Signature(
                                      controller: _signatureController,
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _signatureController.clear,
                                    child: const Text('Clear signature'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isSigning
                                        ? null
                                        : _signDocument,
                                    icon: _isSigning
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.check_circle),
                                    label: Text(
                                      _isSigning
                                          ? 'Signing...'
                                          : 'Sign Document',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
