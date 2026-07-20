import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/common/module_header.dart';
import '../assets/asset_list_screen.dart';
import 'tabs/inventory_items_tab.dart';
import 'tabs/inventory_suppliers_tab.dart';
import 'tabs/equipment_rentals_tab.dart';

/// Main entry point for the Inventory module. Houses the four tabs that
/// map to the resources restoration / GC contractors care about:
///   1. Consumables — consumable items, on-hand qty, reorder points
///   2. Suppliers — vendors we buy from
///   3. Equipment Rentals — daily / weekly / monthly billing of leasable
///      equipment (air movers, dehumidifiers, scrubbers, etc.)
///   4. Equipment — the master register of owned equipment, with leasing
///      configuration (folded in from the standalone Assets module so the
///      whole "what we own + how we deploy it" workflow lives in one place)
///
/// Purchase orders are documents-first and live under Financials → Purchase
/// Orders, so they are not a tab here.
class InventoryScreen extends StatefulWidget {
  final int initialTabIndex;
  const InventoryScreen({super.key, this.initialTabIndex = 0});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 4;
  late final TabController _tabController = TabController(
    length: _tabCount,
    vsync: this,
    initialIndex: widget.initialTabIndex.clamp(0, _tabCount - 1),
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.appUser;
    final workspaceId =
        user?.activeWorkspaceId ?? user?.workspaceId ?? '';

    if (workspaceId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No active workspace.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: Column(
        children: [
          ModuleHeader(
            icon: Icons.warehouse,
            title: 'Inventory',
            description: 'Track consumables, suppliers, equipment rentals, and '
                'your owned-asset register all in one place.',
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(icon: Icon(Icons.inventory), text: 'Consumables'),
                Tab(icon: Icon(Icons.store), text: 'Suppliers'),
                Tab(
                  icon: Icon(Icons.air),
                  text: 'Equipment Rentals',
                ),
                Tab(
                  icon: Icon(Icons.inventory_2),
                  text: 'Equipment',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                InventoryItemsTab(workspaceId: workspaceId),
                InventorySuppliersTab(workspaceId: workspaceId),
                EquipmentRentalsTab(workspaceId: workspaceId),
                // The full Assets list screen, embedded as a tab so the
                // owned-equipment register, the rentals that deploy those
                // assets, and the consumable stock sit side-by-side.
                const AssetListScreen(showModuleHeader: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
