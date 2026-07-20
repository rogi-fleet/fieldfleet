import 'package:flutter/material.dart';

import '../../../models/asset.dart';
import '../../../models/inventory/equipment_rental.dart';
import '../../../models/project.dart';
import '../../../services/service_locator.dart';
import '../../../services/supabase/asset_service.dart';
import '../../../services/supabase/project_service.dart';
import '../../../theme/theme.dart';

class EquipmentRentalForm extends StatefulWidget {
  final String workspaceId;
  final EquipmentRental? existing;
  final String? projectId;

  const EquipmentRentalForm({
    super.key,
    required this.workspaceId,
    this.existing,
    this.projectId,
  });

  @override
  State<EquipmentRentalForm> createState() => _EquipmentRentalFormState();
}

class _EquipmentRentalFormState extends State<EquipmentRentalForm> {
  final _formKey = GlobalKey<FormState>();
  final _daily = TextEditingController(text: '0');
  final _weekly = TextEditingController();
  final _monthly = TextEditingController();
  final _notes = TextEditingController();
  String? _assetId;
  String? _projectId;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _isBillable = true;
  // All assets in the workspace, sorted leasable-first. The form used to
  // restrict this list to is_leasable=true only, but contractors regularly
  // want to spin up an ad-hoc rental for gear they never bothered flagging
  // as "leasable" — that combination would show an empty dropdown and feel
  // broken. We now show every asset and quietly promote it to leasable on
  // save when needed.
  List<Asset> _allAssets = const [];
  List<Project> _projects = const [];
  bool _saving = false;
  SupabaseAssetService? _assetSvc;

  bool _isAssetLeasable(String? id) {
    if (id == null) return true;
    final a = _allAssets.firstWhere(
      (x) => x.id == id,
      orElse: () => Asset(
        id: id,
        workspaceId: widget.workspaceId,
        name: '',
        status: 'active',
        photoUrls: const [],
        category: 'other',
        tags: const [],
      ),
    );
    return a.isLeasable;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _assetId = e.assetId;
      _projectId = e.projectId;
      _startDate = e.startDate;
      _endDate = e.endDate;
      _daily.text = e.dailyRate.toString();
      _weekly.text = e.weeklyRate?.toString() ?? '';
      _monthly.text = e.monthlyRate?.toString() ?? '';
      _isBillable = e.isBillable;
      _notes.text = e.notes ?? '';
    } else {
      _projectId = widget.projectId;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        _assetSvc = SupabaseAssetService(workspaceId: widget.workspaceId);
        final projSvc = SupabaseProjectService();
        // Pull every asset in the workspace, then sort leasable-first so the
        // pre-flagged equipment surfaces at the top of the dropdown but
        // anything else is still selectable.
        final assets = await _assetSvc!.getAssets().first;
        final sorted = [...assets]..sort((a, b) {
          if (a.isLeasable != b.isLeasable) return a.isLeasable ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        final projects = await projSvc.getProjectsOnce(widget.workspaceId);
        if (mounted) {
          setState(() {
            _allAssets = sorted;
            _projects = projects;
            if (_assetId == null && sorted.isNotEmpty) {
              final a = sorted.first;
              _assetId = a.id;
              _daily.text = (a.dailyRentalRate ?? 0).toString();
              _weekly.text = a.weeklyRentalRate?.toString() ?? '';
              _monthly.text = a.monthlyRentalRate?.toString() ?? '';
            }
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load equipment: $e')),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _daily.dispose();
    _weekly.dispose();
    _monthly.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : (_endDate ?? DateTime.now())),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_assetId == null || _projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick equipment and a job first')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      // If the contractor picked an asset that wasn't flagged leasable
      // yet, promote it now using the rates entered on this form. This
      // prevents the "asset doesn't appear in rentals" surprise the next
      // time around and keeps the source of truth in one place.
      final assetSvc =
          _assetSvc ?? SupabaseAssetService(workspaceId: widget.workspaceId);
      if (!_isAssetLeasable(_assetId)) {
        await assetSvc.promoteToLeasable(
          _assetId!,
          dailyRentalRate: double.tryParse(_daily.text.trim()),
          weeklyRentalRate: double.tryParse(_weekly.text.trim()),
          monthlyRentalRate: double.tryParse(_monthly.text.trim()),
        );
      }

      final svc = ServiceLocator.equipmentRentalServiceFor(widget.workspaceId);
      final rental = EquipmentRental(
        id: widget.existing?.id ?? '',
        workspaceId: widget.workspaceId,
        assetId: _assetId!,
        projectId: _projectId!,
        startDate: _startDate,
        endDate: _endDate,
        dailyRate: double.tryParse(_daily.text.trim()) ?? 0,
        weeklyRate: double.tryParse(_weekly.text.trim()),
        monthlyRate: double.tryParse(_monthly.text.trim()),
        isBillable: _isBillable,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        costItemId: widget.existing?.costItemId,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      if (widget.existing == null) {
        await svc.startRental(rental);
      } else {
        await svc.update(rental);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  String _fmt(DateTime? d) => d == null
      ? 'Open'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Edit rental' : 'Start equipment rental',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (_allAssets.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Text(
                    'No equipment in this workspace yet. Add one from the '
                    'Assets tab and you can rent it from here.',
                  ),
                )
              else if (!_isAssetLeasable(_assetId))
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Text(
                    'This equipment is not flagged "Available for rental" yet. '
                    'Saving will turn that on and store the rates below.',
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _assetId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Equipment *',
                  border: OutlineInputBorder(),
                ),
                items: _allAssets
                    .map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  a.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!a.isLeasable)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(left: 8),
                                  child: Text(
                                    'not flagged',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final a = _allAssets.firstWhere((x) => x.id == v);
                  setState(() {
                    _assetId = v;
                    _daily.text = (a.dailyRentalRate ?? 0).toString();
                    _weekly.text = a.weeklyRentalRate?.toString() ?? '';
                    _monthly.text = a.monthlyRentalRate?.toString() ?? '';
                  });
                },
                validator: (_) => _assetId == null ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _projectId,
                decoration: const InputDecoration(
                  labelText: 'Job / project *',
                  border: OutlineInputBorder(),
                ),
                items: _projects
                    .map((p) =>
                        DropdownMenuItem(value: p.id, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setState(() => _projectId = v),
                validator: (_) => _projectId == null ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: const Text('Start date'),
                      subtitle: Text(_fmt(_startDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () => _pickDate(true),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        side: BorderSide(
                            color: Theme.of(context).dividerColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ListTile(
                      title: const Text('End date'),
                      subtitle: Text(_fmt(_endDate)),
                      trailing: Wrap(
                        children: [
                          if (_endDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() => _endDate = null),
                            ),
                          const Icon(Icons.calendar_today),
                        ],
                      ),
                      onTap: () => _pickDate(false),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        side: BorderSide(
                            color: Theme.of(context).dividerColor),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _daily,
                      decoration: const InputDecoration(
                        labelText: 'Daily rate',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _weekly,
                      decoration: const InputDecoration(
                        labelText: 'Weekly',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _monthly,
                      decoration: const InputDecoration(
                        labelText: 'Monthly',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bill back to job'),
                subtitle: const Text(
                  'Closing the rental writes a cost line to the job '
                  'Financials at the rate above.',
                ),
                value: _isBillable,
                onChanged: (v) => setState(() => _isBillable = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(isEdit ? 'Save' : 'Start rental'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
