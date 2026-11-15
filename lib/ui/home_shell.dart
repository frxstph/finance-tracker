import 'package:flutter/material.dart';

import 'bills_page.dart';
import 'dashboard_page.dart';
import 'entries_page.dart';
import 'loan_form_page.dart';
import 'loans_page.dart';
import 'quick_add_page.dart';
import 'settings_page.dart';
import 'widgets/name_amount_dialog.dart';

/// Bottom navigation with four tabs. The add button follows the tab: entries
/// on Dashboard and Entries, bills on Bills, loans on Loans.
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
    'Bills',
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

  Widget _addButton() {
    switch (_index) {
      case 2:
        return FloatingActionButton.extended(
          key: const ValueKey<String>('add-bill'),
          heroTag: 'add-bill',
          onPressed: () => showNewBillDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Add bill'),
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
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Bills',
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
