import 'package:flutter/material.dart';

import 'bills_page.dart';
import 'dashboard_page.dart';
import 'entries_page.dart';
import 'loan_form_page.dart';
import 'loans_page.dart';
import 'quick_add_page.dart';
import 'theme.dart';
import 'settings_page.dart';
import 'widgets/name_amount_dialog.dart';

/// Bottom navigation with four tabs. The add button follows the tab: entries
/// on Dashboard and Entries, monthly income or a bill on Monthly, loans on
/// Loans.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<String> _titles = <String>[
    'Dashboard',
    'Entries',
    'Monthly',
    'Loans',
  ];

  void _openQuickAdd() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const QuickAddPage(),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  List<Widget> _actions() {
    if (_index != 0) return const <Widget>[];
    return <Widget>[
      IconButton(
        tooltip: 'Settings',
        icon: const Icon(Icons.settings_outlined),
        onPressed: _openSettings,
      ),
    ];
  }

  /// On the Monthly tab, ask whether to add income or a bill.
  Future<void> _chooseMonthlyAdd() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(Icons.arrow_downward, color: incomeColor(context)),
              title: const Text('Monthly income'),
              subtitle: const Text('Comes in on a set day each month'),
              onTap: () => Navigator.of(sheetContext).pop(0),
            ),
            ListTile(
              leading: Icon(Icons.receipt_long, color: billsColor(context)),
              title: const Text('Monthly bill'),
              subtitle: const Text('Goes out every month'),
              onTap: () => Navigator.of(sheetContext).pop(1),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 0) {
      await showNewIncomeDialog(context);
    } else {
      await showNewBillDialog(context);
    }
  }

  Widget _addButton() {
    switch (_index) {
      case 2:
        return FloatingActionButton.extended(
          key: const ValueKey<String>('add-monthly'),
          heroTag: 'add-monthly',
          onPressed: _chooseMonthlyAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        );
      case 3:
        return FloatingActionButton.extended(
          key: const ValueKey<String>('add-loan'),
          heroTag: 'add-loan',
          onPressed: () => showNewLoanForm(context),
          icon: const Icon(Icons.add),
          label: const Text('Add loan'),
        );
      default:
        return FloatingActionButton.extended(
          key: const ValueKey<String>('add-entry'),
          heroTag: 'add-entry',
          onPressed: _openQuickAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add entry'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: _actions(),
      ),
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          DashboardPage(),
          EntriesPage(),
          BillsPage(),
          LoansPage(),
        ],
      ),
      floatingActionButton: _addButton(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Entries',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_repeat_outlined),
            selectedIcon: Icon(Icons.event_repeat),
            label: 'Monthly',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance),
            label: 'Loans',
          ),
        ],
      ),
    );
  }
}
