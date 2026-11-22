import 'package:flutter/material.dart';

import 'accounts_page.dart';
import 'bill_form_page.dart';
import 'calculator_page.dart';
import 'bills_page.dart';
import 'dashboard_page.dart';
import 'entries_page.dart';
import 'loan_form_page.dart';
import 'loans_page.dart';
import 'quick_add_page.dart';
import 'theme.dart';
import 'settings_page.dart';
import 'widgets/name_amount_dialog.dart';

/// Bottom navigation: Dashboard, Entries, a raised Scan button in the
/// middle, Monthly and Loans. Scan is how spending is added on Dashboard and
/// Entries; Monthly and Loans keep their own add button.
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
        tooltip: 'Calculator',
        icon: const Icon(Icons.calculate_outlined),
        onPressed: () => showCalculator(context),
      ),
      IconButton(
        tooltip: 'My accounts and QR codes',
        icon: const Icon(Icons.qr_code_2),
        onPressed: () => showAccountsPage(context),
      ),
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
              title: const Text('Bill'),
              subtitle: const Text('Monthly, weekly, daily or one time'),
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
      await showNewBillForm(context);
    }
  }

  Widget? _addButton() {
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
        // Dashboard and Entries add through the Scan button.
        return null;
    }
  }

  /// The middle Scan button: a sheet with the ways to add a spend. Receipt
  /// scanning is the next update; adding by hand works now.
  Future<void> _openScan() async {
    final theme = Theme.of(context);
    final manual = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Add a spend', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Scanning receipts is coming in the next update.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              const _ScanOption(
                icon: Icons.document_scanner_outlined,
                title: 'Scan a receipt',
                subtitle: 'Coming soon',
              ),
              const SizedBox(height: 8),
              const _ScanOption(
                icon: Icons.photo_library_outlined,
                title: 'Choose a photo',
                subtitle: 'Coming soon',
              ),
              const SizedBox(height: 8),
              _ScanOption(
                icon: Icons.edit_outlined,
                title: 'Add without a photo',
                subtitle: 'Type the amount yourself',
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || manual != true) return;
    _openQuickAdd();
  }

  /// Tab bar slots: Dashboard, Entries, (Scan), Monthly, Loans.
  int get _navIndex => _index < 2 ? _index : _index + 1;

  void _onNav(int i) {
    if (i == 2) {
      _openScan();
      return;
    }
    setState(() => _index = i < 2 ? i : i - 1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: <Widget>[
          NavigationBar(
            selectedIndex: _navIndex,
            onDestinationSelected: _onNav,
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
              // Room for the raised Scan circle drawn on top.
              NavigationDestination(
                icon: SizedBox(width: 24, height: 24),
                label: 'Scan',
                tooltip: 'Scan a receipt',
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
          Positioned(
            top: -18,
            child: Semantics(
              button: true,
              label: 'Scan a receipt',
              excludeSemantics: true,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 5),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: scheme.primary,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _openScan,
                    child: Icon(
                      Icons.document_scanner_outlined,
                      color: scheme.onPrimary,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One choice in the Scan sheet; without [onTap] it shows as not ready yet.
class _ScanOption extends StatelessWidget {
  const _ScanOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final fg = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: enabled
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(icon,
                    color: enabled ? theme.colorScheme.primary : fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
