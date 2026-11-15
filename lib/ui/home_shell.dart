import 'package:flutter/material.dart';

import 'bills_page.dart';
import 'dashboard_page.dart';
import 'entries_page.dart';
import 'loans_page.dart';
import 'quick_add_page.dart';
import 'settings_page.dart';
import 'widgets/name_amount_dialog.dart';

/// Bottom navigation with four tabs and an "Add" button on every tab.
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
    switch (_index) {
      case 0:
        return <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ];
      case 2:
        return <Widget>[
          IconButton(
            tooltip: 'New bill',
            icon: const Icon(Icons.playlist_add),
            onPressed: () => showNewBillDialog(context),
          ),
        ];
      case 3:
        return <Widget>[
          IconButton(
            tooltip: 'New loan',
            icon: const Icon(Icons.playlist_add),
            onPressed: () => showNewLoanDialog(context),
          ),
        ];
      default:
        return const <Widget>[];
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQuickAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
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
