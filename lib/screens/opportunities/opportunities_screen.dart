import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/opportunity.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/opportunity_service.dart';
import '../../theme/theme.dart';
import '../../widgets/common/list_skeleton.dart';
import 'opportunity_card.dart';

class OpportunitiesScreen extends StatefulWidget {
  const OpportunitiesScreen({super.key});

  @override
  State<OpportunitiesScreen> createState() => _OpportunitiesScreenState();
}

class _OpportunitiesScreenState extends State<OpportunitiesScreen> {
  late SupabaseOpportunityService _svc;
  List<Opportunity> _opps = [];
  List<Map<String, dynamic>> _forecast = [];
  bool _loading = true;
  String? _error;
  String? _workspaceId;
  String? _ownerFilter; // null = all owners

  @override
  void initState() {
    super.initState();
    _svc = ServiceLocator.opportunityService;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Provider.of (listen: true) rather than read() so this re-runs once the
    // workspace hydrates. On a cold load/refresh activeWorkspace is briefly
    // null; with read() the load was skipped and never retried, leaving the
    // screen stuck on the loading spinner.
    final ws =
        Provider.of<WorkspaceProvider>(context).activeWorkspace?.workspaceId;
    if (ws != null && ws != _workspaceId) {
      _workspaceId = ws;
      _load();
    }
  }

  Future<void> _load() async {
    if (_workspaceId == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _svc.listOpportunities(_workspaceId!),
        _svc.getForecast(_workspaceId!),
      ]);
      if (!mounted) return;
      setState(() {
        _opps = results[0] as List<Opportunity>;
        _forecast = results[1] as List<Map<String, dynamic>>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onDropped(Opportunity opp, OpportunityStage to) async {
    if (opp.stage == to) return;
    try {
      await _svc.changeStage(opp.id, to);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to move: $e')),
      );
    }
  }

  List<Opportunity> get _filtered {
    if (_ownerFilter == null) return _opps;
    return _opps.where((o) => o.ownerId == _ownerFilter).toList();
  }

  Iterable<Map<String, dynamic>> get _forecastFiltered {
    if (_ownerFilter == null) return _forecast;
    return _forecast.where((r) => r['owner_id'] == _ownerFilter);
  }

  @override
  Widget build(BuildContext context) {
    final ownerIds = _opps
        .map((o) => o.ownerId)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Opportunities'),
        actions: [
          if (ownerIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: DropdownButton<String?>(
                value: _ownerFilter,
                hint: const Text('All owners'),
                underline: const SizedBox.shrink(),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem(value: null, child: Text('All owners')),
                  ...ownerIds.map((id) => DropdownMenuItem(
                        value: id,
                        child: Text(_shortId(id)),
                      )),
                ],
                onChanged: (v) => setState(() => _ownerFilter = v),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('New'),
              onPressed: () => context.go('/opportunities/new'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const ListSkeleton()
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Column(
                  children: [
                    _ForecastHeader(rows: _forecastFiltered.toList()),
                    const Divider(height: 1),
                    Expanded(
                      child: _Board(
                        opps: _filtered,
                        onDropped: _onDropped,
                        onTap: (o) => context.go('/opportunities/${o.id}'),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _shortId(String id) =>
      id.length <= 8 ? id : '${id.substring(0, 8)}…';
}

class _ForecastHeader extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _ForecastHeader({required this.rows});

  @override
  Widget build(BuildContext context) {
    double total = 0;
    double weighted = 0;
    int count = 0;
    for (final r in rows) {
      total += (r['total_value'] as num?)?.toDouble() ?? 0;
      weighted += (r['weighted_value'] as num?)?.toDouble() ?? 0;
      count += (r['opportunity_count'] as num?)?.toInt() ?? 0;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      color: AppColors.surfaceAlt,
      child: Wrap(
        spacing: 32,
        runSpacing: 8,
        children: [
          _Metric(label: 'Open opportunities', value: '$count'),
          _Metric(label: 'Pipeline value', value: _money(total)),
          _Metric(label: 'Weighted forecast', value: _money(weighted)),
        ],
      ),
    );
  }

  static String _money(double v) {
    if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(1)}k';
    return '\$${v.toStringAsFixed(0)}';
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
            )),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}

class _Board extends StatelessWidget {
  final List<Opportunity> opps;
  final void Function(Opportunity, OpportunityStage) onDropped;
  final void Function(Opportunity) onTap;

  const _Board({
    required this.opps,
    required this.onDropped,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stages = OpportunityStage.values;
        final columnWidth =
            (constraints.maxWidth / stages.length).clamp(220.0, 360.0);
        final content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in stages)
              SizedBox(
                width: columnWidth,
                child: _Column(
                  stage: s,
                  opps: opps.where((o) => o.stage == s).toList(),
                  onDropped: onDropped,
                  onTap: onTap,
                ),
              ),
          ],
        );
        if (constraints.maxWidth >= columnWidth * stages.length) {
          return content;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: content,
        );
      },
    );
  }
}

class _Column extends StatefulWidget {
  final OpportunityStage stage;
  final List<Opportunity> opps;
  final void Function(Opportunity, OpportunityStage) onDropped;
  final void Function(Opportunity) onTap;

  const _Column({
    required this.stage,
    required this.opps,
    required this.onDropped,
    required this.onTap,
  });

  @override
  State<_Column> createState() => _ColumnState();
}

class _ColumnState extends State<_Column> {
  bool _over = false;

  Color get _color {
    switch (widget.stage) {
      case OpportunityStage.newLead:
        return Colors.blueGrey;
      case OpportunityStage.qualified:
        return Colors.indigo;
      case OpportunityStage.proposal:
        return Colors.deepPurple;
      case OpportunityStage.negotiation:
        return Colors.orange;
      case OpportunityStage.won:
        return Colors.green;
      case OpportunityStage.lost:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.opps.fold<double>(0, (s, o) => s + o.estimatedValue);
    return DragTarget<Opportunity>(
      onWillAcceptWithDetails: (d) => d.data.stage != widget.stage,
      onAcceptWithDetails: (d) {
        setState(() => _over = false);
        widget.onDropped(d.data, widget.stage);
      },
      onMove: (_) {
        if (!_over) setState(() => _over = true);
      },
      onLeave: (_) {
        if (_over) setState(() => _over = false);
      },
      builder: (context, _, __) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: _over
                ? _color.withValues(alpha: 0.08)
                : Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
            border: Border.all(
              color: _over
                  ? _color.withValues(alpha: 0.5)
                  : AppColors.cardBorder.withValues(alpha: 0.5),
              width: _over ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.r12),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration:
                          BoxDecoration(color: _color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(widget.stage.displayName,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text('${widget.opps.length}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _color)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _money(total),
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
              ),
              const Divider(height: 12),
              Expanded(
                child: widget.opps.isEmpty
                    ? Center(
                        child: Text(
                          'No opportunities',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textTertiary),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                        itemCount: widget.opps.length,
                        itemBuilder: (_, i) {
                          final o = widget.opps[i];
                          return Draggable<Opportunity>(
                            data: o,
                            feedback: Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              child: SizedBox(
                                width: 260,
                                child: OpportunityCard(opp: o, onTap: () {}),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.4,
                              child: OpportunityCard(
                                  opp: o, onTap: () => widget.onTap(o)),
                            ),
                            child: OpportunityCard(
                                opp: o, onTap: () => widget.onTap(o)),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _money(double v) {
    if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(1)}k';
    return '\$${v.toStringAsFixed(0)}';
  }
}
