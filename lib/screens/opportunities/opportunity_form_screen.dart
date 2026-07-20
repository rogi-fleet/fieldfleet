import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/customer.dart';
import '../../models/opportunity.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/opportunity_service.dart';
import '../../theme/theme.dart';

class OpportunityFormScreen extends StatefulWidget {
  final String? opportunityId;
  const OpportunityFormScreen({super.key, this.opportunityId});

  @override
  State<OpportunityFormScreen> createState() => _OpportunityFormScreenState();
}

class _OpportunityFormScreenState extends State<OpportunityFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _value = TextEditingController(text: '0');
  final _probability = TextEditingController(text: '50');
  final _nextAction = TextEditingController();

  late SupabaseOpportunityService _svc;
  OpportunityStage _stage = OpportunityStage.newLead;
  String? _customerId;
  DateTime? _expectedClose;
  bool _loading = true;
  bool _saving = false;
  List<Customer> _customers = [];
  Opportunity? _existing;

  @override
  void initState() {
    super.initState();
    _svc = ServiceLocator.opportunityService;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ws = context.read<WorkspaceProvider>().activeWorkspace?.workspaceId;
    if (ws == null) return;
    final customers =
        await (ServiceLocator.customerService as dynamic).getCustomersOnce(ws)
            as List<Customer>;
    Opportunity? existing;
    if (widget.opportunityId != null) {
      existing = await _svc.getOpportunity(widget.opportunityId!);
      if (existing != null) {
        _name.text = existing.name;
        _desc.text = existing.description ?? '';
        _value.text = existing.estimatedValue.toString();
        _probability.text = existing.probability.toString();
        _nextAction.text = existing.nextAction ?? '';
        _stage = existing.stage;
        _customerId = existing.customerId;
        _expectedClose = existing.expectedCloseDate;
      }
    }
    if (!mounted) return;
    setState(() {
      _customers = customers;
      _existing = existing;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _value.dispose();
    _probability.dispose();
    _nextAction.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ws = context.read<WorkspaceProvider>().activeWorkspace?.workspaceId;
    if (ws == null) return;
    setState(() => _saving = true);
    try {
      if (_existing == null) {
        final draft = Opportunity(
          id: '',
          workspaceId: ws,
          name: _name.text.trim(),
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          stage: _stage,
          estimatedValue: double.tryParse(_value.text) ?? 0,
          probability: int.tryParse(_probability.text) ?? 50,
          expectedCloseDate: _expectedClose,
          customerId: _customerId,
          nextAction:
              _nextAction.text.trim().isEmpty ? null : _nextAction.text.trim(),
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final created = await _svc.createOpportunity(draft);
        if (mounted) context.go('/opportunities/${created.id}');
      } else {
        await _svc.updateOpportunity(_existing!.id, {
          'name': _name.text.trim(),
          'description':
              _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'stage': _stage.dbValue,
          'estimated_value': double.tryParse(_value.text) ?? 0,
          'probability': int.tryParse(_probability.text) ?? 50,
          'expected_close_date': _expectedClose
              ?.toIso8601String()
              .substring(0, 10),
          'customer_id': _customerId,
          'next_action':
              _nextAction.text.trim().isEmpty ? null : _nextAction.text.trim(),
        });
        if (mounted) context.go('/opportunities/${_existing!.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'New opportunity' : 'Edit opportunity'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _desc,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _customerId,
                    decoration: const InputDecoration(labelText: 'Customer'),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem(value: null, child: Text('—')),
                      ..._customers.map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.companyName ??
                                  (c.contacts.isNotEmpty
                                      ? c.contacts.first.name
                                      : 'Customer'),
                            ),
                          )),
                    ],
                    onChanged: (v) => setState(() => _customerId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<OpportunityStage>(
                    initialValue: _stage,
                    decoration: const InputDecoration(labelText: 'Stage'),
                    items: OpportunityStage.values
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s.displayName),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _stage = v ?? OpportunityStage.newLead),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _value,
                        decoration: const InputDecoration(
                            labelText: 'Estimated value'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _probability,
                        decoration:
                            const InputDecoration(labelText: 'Probability %'),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n < 0 || n > 100) return '0-100';
                          return null;
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_expectedClose == null
                        ? 'Expected close date — none'
                        : 'Expected close: ${_expectedClose!.toIso8601String().substring(0, 10)}'),
                    trailing: const Icon(Icons.event),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _expectedClose ?? DateTime.now(),
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 365)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365 * 3)),
                      );
                      if (picked != null) {
                        setState(() => _expectedClose = picked);
                      }
                    },
                  ),
                  TextFormField(
                    controller: _nextAction,
                    decoration:
                        const InputDecoration(labelText: 'Next action'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
