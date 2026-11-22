import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/receipt_reader.dart';
import '../state/lock_controller.dart';

import 'accounts_page.dart';
import 'bill_form_page.dart';
import 'calculator_page.dart';
import 'bills_page.dart';
import 'dashboard_page.dart';
import 'entries_page.dart';
import 'loan_form_page.dart';
import 'import_page.dart';
import 'loans_page.dart';
import 'quick_add_page.dart';
import 'theme.dart';
import 'settings_page.dart';
import 'widgets/dialogs.dart';
import 'widgets/name_amount_dialog.dart';

/// Bottom navigation: Dashboard, Entries, a raised Scan button in the
/// middle, Monthly and Loans. Scan (camera, gallery or by hand) is how
/// spending is added on Dashboard and Entries; Monthly and Loans keep their
/// own add button.
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

  /// The middle Scan button: a sheet with the ways to add a spend.
  Future<void> _openScan() async {
    final theme = Theme.of(context);
    final choice = await showModalBottomSheet<_ScanChoice>(
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
                'Scan a receipt and the app fills in the amount for you.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _ScanOption(
                icon: Icons.document_scanner_outlined,
                title: 'Scan a receipt',
                subtitle: 'Opens the camera',
                primary: true,
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ScanChoice.camera),
              ),
              const SizedBox(height: 8),
              _ScanOption(
                icon: Icons.photo_library_outlined,
                title: 'Choose photos',
                subtitle: 'Receipts or e-wallet screenshots from your gallery',
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ScanChoice.gallery),
              ),
              const SizedBox(height: 8),
              _ScanOption(
                icon: Icons.edit_outlined,
                title: 'Add without a photo',
                subtitle: 'Type the amount yourself',
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ScanChoice.manual),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _ScanChoice.manual) {
      _openQuickAdd();
      return;
    }
    if (choice == _ScanChoice.camera) {
      await _scanReceipt(ImageSource.camera);
    } else {
      await _choosePhotos();
    }
  }

  /// Most photos read in one go.
  static const int _maxPhotos = 30;

  /// Gallery with multi-select. One photo → Check and save, as with the
  /// camera; several → read them all, then Check before adding.
  Future<void> _choosePhotos() async {
    List<XFile> photos;
    try {
      photos = await LockScope.read(context).whileAway(
        () => ImagePicker().pickMultiImage(
          maxWidth: 2000,
          imageQuality: 85,
          limit: _maxPhotos,
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Could not open your photos: $e');
      return;
    }
    if (photos.isEmpty || !mounted) return;
    if (photos.length == 1) {
      await _readOne(photos.single.path);
      return;
    }
    // Older phones' pickers may ignore the limit.
    if (photos.length > _maxPhotos) {
      showMessage(
        context,
        'Reading the first $_maxPhotos of ${photos.length} photos. Add the '
        'rest after.',
      );
      photos = photos.sublist(0, _maxPhotos);
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ImportPage(
          photoPaths: <String>[for (final p in photos) p.path],
        ),
      ),
    );
  }

  /// Takes or picks the photo, reads it on the phone, then opens Check and
  /// save with what was found.
  Future<void> _scanReceipt(ImageSource source) async {
    final XFile? photo;
    try {
      photo = await LockScope.read(context).whileAway(
        () => ImagePicker().pickImage(
          source: source,
          maxWidth: 2000,
          imageQuality: 85,
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Could not open the camera: $e');
      return;
    }
    if (photo == null || !mounted) return;
    await _readOne(photo.path);
  }

  /// Reads one photo, then opens Check and save with what was found.
  Future<void> _readOne(String path) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: <Widget>[
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Reading the receipt…')),
            ],
          ),
        ),
      ),
    );
    final guess = await ReceiptReader.read(path);
    if (!mounted) return;
    Navigator.of(context).pop(); // the "Reading" dialog
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => QuickAddPage(
          scan: ScannedReceipt(photoPath: path, guess: guess),
        ),
      ),
    );
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

/// What was picked in the Scan sheet.
enum _ScanChoice { camera, gallery, manual }

/// One choice in the Scan sheet. The [primary] one is filled green.
class _ScanOption extends StatelessWidget {
  const _ScanOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = primary ? scheme.onPrimary : scheme.onSurface;
    return Material(
      color: primary ? scheme.primary : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: primary
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(icon, color: primary ? fg : scheme.primary),
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
                          color: primary
                              ? fg.withAlpha(220)
                              : scheme.onSurfaceVariant,
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
