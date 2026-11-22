import 'dart:io';

import 'package:flutter/material.dart';

import '../data/receipt_reader.dart';
import '../domain/bulk_import.dart';
import '../domain/dates.dart';
import '../domain/money.dart';
import '../domain/models.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/amount_field.dart';
import 'widgets/dialogs.dart';

/// "Choose photos" with several picked: reads each photo on the phone,
/// then "Check before adding" lists them with what was found and what needs
/// a look. Nothing is saved until "Add N entries"; then a summary with Undo
/// all. Design: the "Add several receipts" canvas.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.photoPaths});

  final List<String> photoPaths;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

enum _Filter { all, attention, ready }

class _ImportPageState extends State<ImportPage> {
  final List<ImportDraft> _drafts = <ImportDraft>[];
  List<ImportReview> _reviews = const <ImportReview>[];
  bool _reading = true;
  bool _stop = false;
  bool _adding = false;
  _Filter _filter = _Filter.all;
  EntryType _typeForAll = EntryType.daily;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readAll());
  }

  Future<void> _readAll() async {
    for (final path in widget.photoPaths) {
      if (_stop || !mounted) break;
      final guess = await ReceiptReader.read(path);
      if (!mounted) return;
      setState(() => _drafts.add(ImportDraft(photoPath: path, guess: guess)));
    }
    if (!mounted) return;
    _review(setDefaults: true);
    setState(() => _reading = false);
  }

  /// Works out each draft's status. On the first pass (and after a fix) it
  /// also ticks the ones that can go in.
  void _review({bool setDefaults = false, int? fixedIndex}) {
    final state = AppScope.read(context);
    _reviews = reviewDrafts(_drafts, state.allEntries, DateTime.now());
    for (var i = 0; i < _drafts.length; i++) {
      if (setDefaults || i == fixedIndex) {
        _drafts[i].include = _reviews[i].addByDefault;
      } else if (!_reviews[i].addByDefault &&
          _reviews[i].status == ImportStatus.needsFix) {
        _drafts[i].include = false;
      }
    }
  }

  bool _needsAttention(int i) => _reviews[i].status != ImportStatus.ready;

  List<int> get _visible => <int>[
        for (var i = 0; i < _drafts.length; i++)
          if (_filter == _Filter.all ||
              (_filter == _Filter.attention && _needsAttention(i)) ||
              (_filter == _Filter.ready && !_needsAttention(i)))
            i,
      ];

  List<int> get _included => <int>[
        for (var i = 0; i < _drafts.length; i++)
          if (_drafts[i].include && _reviews[i].status != ImportStatus.needsFix)
            i,
      ];

  int _count(ImportStatus s) => _reviews.where((r) => r.status == s).length;

  Future<void> _fix(int index) async {
    var i = index;
    while (mounted) {
      final result = await showModalBottomSheet<_FixResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => _FixSheet(
          draft: _drafts[i],
          review: _reviews[i],
          position: i + 1,
          total: _drafts.length,
        ),
      );
      if (!mounted || result == null) return;
      setState(() {
        if (result == _FixResult.leaveOut) {
          _drafts[i].include = false;
          _review();
        } else {
          _drafts[i].fixed = true;
          _review(fixedIndex: i);
          _drafts[i].include = _reviews[i].status != ImportStatus.needsFix;
        }
      });
      if (result != _FixResult.saveAndNext) return;
      // Next photo that still needs attention, after this one.
      int? next;
      for (var j = 1; j <= _drafts.length; j++) {
        final k = (i + j) % _drafts.length;
        if (k != i &&
            (_reviews[k].status == ImportStatus.needsFix ||
                _reviews[k].status == ImportStatus.check) &&
            !_drafts[k].fixed) {
          next = k;
          break;
        }
      }
      if (next == null) return;
      i = next;
    }
  }

  Future<void> _add() async {
    final state = AppScope.read(context);
    final picked = _included;
    if (picked.isEmpty) return;
    setState(() => _adding = true);
    final cashBefore = state.cashNow;
    final safeBefore = state.safeToSpendNow.perDay ~/ 100 * 100;
    final now = DateTime.now().toIso8601String();
    final entries = <Entry>[
      for (final i in picked)
        Entry(
          type: _drafts[i].type,
          amount: _drafts[i].amount!,
          note: _drafts[i].note,
          date: dateKey(_drafts[i].date!),
          createdAt: now,
        ),
    ];
    List<int> ids;
    try {
      ids = await state.addEntries(
        entries,
        <String?>[for (final i in picked) _drafts[i].photoPath],
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      showMessage(context, 'Could not add: $e');
      return;
    }
    if (!mounted) return;
    final dates = <DateTime>[for (final i in picked) _drafts[i].date!]..sort();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => _SummaryPage(
          ids: ids,
          entries: entries,
          leftOut: _drafts.length - picked.length,
          duplicates: <int>[
            for (var i = 0; i < _drafts.length; i++)
              if (!picked.contains(i) &&
                  _reviews[i].status == ImportStatus.duplicate)
                i,
          ].length,
          first: dates.first,
          last: dates.last,
          cashBefore: cashBefore,
          safeBefore: safeBefore,
        ),
      ),
    );
  }

  Future<bool> _confirmClose() async {
    if (_drafts.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close without adding?'),
        content: const Text('Nothing from these photos has been saved yet.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep checking'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_reading) {
          setState(() => _stop = true);
          return;
        }
        if (await _confirmClose() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _reading ? _buildReading(context) : _buildReview(context),
    );
  }

  Widget _buildReading(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.photoPaths.length;
    final done = _drafts.length;
    final problems = _drafts
        .where((d) => d.amount == null || d.date == null)
        .length;
    return Scaffold(
      appBar: AppBar(title: Text('Reading ${done + 1 > total ? total : done + 1} of $total')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: <Widget>[
          LinearProgressIndicator(
            value: total == 0 ? null : done / total,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 10),
          Text(
            'Reading happens on your phone. Nothing is saved until you check '
            'and accept.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.78,
            children: <Widget>[
              for (var i = 0; i < total; i++)
                _Thumb(
                  path: widget.photoPaths[i],
                  state: i < done
                      ? _ThumbState.done
                      : i == done
                          ? _ThumbState.reading
                          : _ThumbState.waiting,
                ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'So far: ${done - problems} read fine · $problems need a fix',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: _stop ? null : () => setState(() => _stop = true),
            child: Text(_stop ? 'Stopping…' : 'Stop and review what’s read'),
          ),
        ),
      ),
    );
  }

  Widget _buildReview(BuildContext context) {
    final theme = Theme.of(context);
    if (_drafts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Check before adding')),
        body: const Center(child: Text('No photos were read.')),
      );
    }
    final included = _included;
    final readyTotal = included.fold<int>(
        0, (sum, i) => sum + (_drafts[i].amount ?? 0));
    final dates = <DateTime>[
      for (final d in _drafts)
        if (d.date != null) d.date!,
    ]..sort();
    final range = dates.isEmpty
        ? ''
        : ' · ${_shortRange(dates.first, dates.last)}';
    final attention = _reviews.where((r) => r.status != ImportStatus.ready).length;
    final skipped = widget.photoPaths.length - _drafts.length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () async {
            if (await _confirmClose() && context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text('Check before adding'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${_drafts.length} photos read$range'
                    '${skipped > 0 ? ' · $skipped not read' : ''}',
                    style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: <InlineSpan>[
                      TextSpan(
                        text: formatPeso(-readyTotal),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: debtColor(context),
                        ),
                      ),
                      TextSpan(
                        text: '  ticked to add',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _StatusPill(
                          status: ImportStatus.ready,
                          text: '${_count(ImportStatus.ready)} ready'),
                      if (_count(ImportStatus.check) > 0)
                        _StatusPill(
                            status: ImportStatus.check,
                            text: '${_count(ImportStatus.check)} to check'),
                      if (_count(ImportStatus.needsFix) > 0)
                        _StatusPill(
                            status: ImportStatus.needsFix,
                            text: '${_count(ImportStatus.needsFix)} need a fix'),
                      if (_count(ImportStatus.duplicate) > 0)
                        _StatusPill(
                            status: ImportStatus.duplicate,
                            text:
                                '${_count(ImportStatus.duplicate)} possible duplicate'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: Text('All ${_drafts.length}'),
                selected: _filter == _Filter.all,
                onSelected: (_) => setState(() => _filter = _Filter.all),
              ),
              ChoiceChip(
                label: Text('Needs attention $attention'),
                selected: _filter == _Filter.attention,
                onSelected: (_) => setState(() => _filter = _Filter.attention),
              ),
              ChoiceChip(
                label: Text('Ready ${_drafts.length - attention}'),
                selected: _filter == _Filter.ready,
                onSelected: (_) => setState(() => _filter = _Filter.ready),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final i in _visible)
            _DraftRow(
              draft: _drafts[i],
              review: _reviews[i],
              onToggle: _reviews[i].status == ImportStatus.needsFix
                  ? () => _fix(i)
                  : () => setState(
                      () => _drafts[i].include = !_drafts[i].include),
              onOpen: () => _fix(i),
            ),
          if (_visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Nothing here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Ticked ones go in as',
                        style: theme.textTheme.bodyMedium),
                  ),
                  DropdownButton<EntryType>(
                    value: _typeForAll,
                    onChanged: (t) {
                      if (t == null) return;
                      setState(() {
                        _typeForAll = t;
                        for (final d in _drafts) {
                          d.type = t;
                        }
                      });
                    },
                    items: const <DropdownMenuItem<EntryType>>[
                      DropdownMenuItem<EntryType>(
                          value: EntryType.daily, child: Text('Daily')),
                      DropdownMenuItem<EntryType>(
                          value: EntryType.oneTime, child: Text('One-time')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: included.isEmpty || _adding ? null : _add,
                child: Text(_adding
                    ? 'Adding…'
                    : included.isEmpty
                        ? 'Tick photos to add'
                        : 'Add ${included.length} '
                            '${included.length == 1 ? 'entry' : 'entries'}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _shortRange(DateTime a, DateTime b) {
  final left = shortDayLabel(a).substring(4);
  final right = shortDayLabel(b).substring(4);
  if (left == right) return left;
  if (a.month == b.month && a.year == b.year) {
    return '${a.day}–$right';
  }
  return '$left – $right';
}

enum _ThumbState { done, reading, waiting }

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, required this.state});

  final String path;
  final _ThumbState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: Opacity(
            opacity: state == _ThumbState.waiting ? 0.45 : 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: state == _ThumbState.reading
                    ? Border.all(color: scheme.primary, width: 3)
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(File(path), fit: BoxFit.cover, cacheWidth: 200),
            ),
          ),
        ),
        if (state == _ThumbState.done)
          Positioned(
            right: -6,
            top: -6,
            child: CircleAvatar(
              radius: 11,
              backgroundColor: scheme.primary,
              child: Icon(Icons.check, size: 15, color: scheme.onPrimary),
            ),
          ),
      ],
    );
  }
}

/// Colours per status: green ready, amber check, orange needs a fix,
/// purple possible duplicate.
(Color, Color) _statusColors(ImportStatus s, Brightness b) {
  final dark = b == Brightness.dark;
  switch (s) {
    case ImportStatus.ready:
      return dark
          ? (const Color(0xFF1E3A2A), const Color(0xFFBFEBD0))
          : (const Color(0xFFDDF1E5), const Color(0xFF14532D));
    case ImportStatus.check:
      return dark
          ? (const Color(0xFF3D3214), const Color(0xFFF5DE9A))
          : (const Color(0xFFFFF1C7), const Color(0xFF6B4A00));
    case ImportStatus.needsFix:
      return dark
          ? (const Color(0xFF452714), const Color(0xFFF8C9A6))
          : (const Color(0xFFFBE1CC), const Color(0xFF7A3300));
    case ImportStatus.duplicate:
      return dark
          ? (const Color(0xFF2E2745), const Color(0xFFD5CBF2))
          : (const Color(0xFFE7E2F3), const Color(0xFF4A3A7A));
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.text});

  final ImportStatus status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _statusColors(status, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.draft,
    required this.review,
    required this.onToggle,
    required this.onOpen,
  });

  final ImportDraft draft;
  final ImportReview review;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = draft.amount;
    final date = draft.date;
    final title = draft.note.trim().isEmpty ? 'Receipt' : draft.note.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            children: <Widget>[
              Checkbox(
                value: draft.include &&
                    review.status != ImportStatus.needsFix,
                onChanged: (_) => onToggle(),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(draft.photoPath),
                  width: 44,
                  height: 56,
                  fit: BoxFit.cover,
                  cacheWidth: 132,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          amount == null ? 'Add amount' : formatPeso(-amount),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: amount == null ? null : debtColor(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date == null
                          ? 'No date found · tap to add'
                          : '${shortDayLabel(date)} · '
                              '${draft.type == EntryType.oneTime ? 'One-time' : 'Daily'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    _StatusPill(status: review.status, text: review.reason),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FixResult { save, saveAndNext, leaveOut }

/// One photo big on top (pinch to zoom) with its amount, date, type and
/// note to fix.
class _FixSheet extends StatefulWidget {
  const _FixSheet({
    required this.draft,
    required this.review,
    required this.position,
    required this.total,
  });

  final ImportDraft draft;
  final ImportReview review;
  final int position;
  final int total;

  @override
  State<_FixSheet> createState() => _FixSheetState();
}

class _FixSheetState extends State<_FixSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.draft.amount == null
        ? ''
        : centavosToInput(widget.draft.amount!),
  );
  late final TextEditingController _note =
      TextEditingController(text: widget.draft.note);
  late DateTime? _date = widget.draft.date;
  late EntryType _type = widget.draft.type;
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Date on the receipt',
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _done(_FixResult result) {
    if (result == _FixResult.leaveOut) {
      Navigator.of(context).pop(result);
      return;
    }
    final amount = parseCentavos(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter the amount on the receipt');
      return;
    }
    if (_date == null) {
      _pickDate();
      return;
    }
    final d = widget.draft;
    if (d.amount != amount || d.date != _date) d.fixed = true;
    d
      ..amount = amount
      ..date = _date
      ..type = _type
      ..note = _note.text.trim();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noDate = _date == null;
    final (warnBg, warnFg) =
        _statusColors(ImportStatus.needsFix, theme.brightness);
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Photo ${widget.position} of ${widget.total}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Center(
                child: _StatusPill(
                    status: widget.review.status, text: widget.review.reason)),
            const SizedBox(height: 12),
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.file(File(widget.draft.photoPath),
                    fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 4),
            Text('Pinch the photo to zoom.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            AmountField(
              controller: _amount,
              label: 'Amount',
              errorText: _amountError,
              onChanged: (_) => setState(() => _amountError = null),
            ),
            const SizedBox(height: 12),
            Text(
              noDate ? 'Date · couldn’t read it' : 'Date',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: noDate ? warnFg : null),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                alignment: Alignment.centerLeft,
                backgroundColor: noDate ? warnBg : null,
                foregroundColor: noDate ? warnFg : null,
                side: noDate ? BorderSide(color: warnFg, width: 2) : null,
              ),
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(noDate
                  ? 'Pick the date on the receipt'
                  : shortDayLabel(_date!)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Daily'),
                  selected: _type == EntryType.daily,
                  onSelected: (_) => setState(() => _type = EntryType.daily),
                ),
                ChoiceChip(
                  label: const Text('One-time'),
                  selected: _type == EntryType.oneTime,
                  onSelected: (_) => setState(() => _type = EntryType.oneTime),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    onPressed: () => _done(_FixResult.leaveOut),
                    child: const Text('Leave it out'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    onPressed: () => _done(_FixResult.saveAndNext),
                    child: const Text('Save and next'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => _done(_FixResult.save),
              child: const Text('Save and go back to the list'),
            ),
          ],
        ),
      ),
    );
  }
}

/// After adding: how many went in, the total by type, what was left out,
/// what it did to cash and Safe to spend, with Undo all.
class _SummaryPage extends StatefulWidget {
  const _SummaryPage({
    required this.ids,
    required this.entries,
    required this.leftOut,
    required this.duplicates,
    required this.first,
    required this.last,
    required this.cashBefore,
    required this.safeBefore,
  });

  final List<int> ids;
  final List<Entry> entries;
  final int leftOut;
  final int duplicates;
  final DateTime first;
  final DateTime last;
  final int cashBefore;
  final int safeBefore;

  @override
  State<_SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<_SummaryPage> {
  bool _busy = false;

  Future<void> _undo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove all ${widget.ids.length} entries?'),
        content: const Text('They and their photos are removed, as if you '
            'never added them.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep them'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await AppScope.read(context).deleteEntriesById(widget.ids);
    if (!mounted) return;
    showMessage(context, 'Removed ${widget.ids.length} entries.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final total = widget.entries.fold<int>(0, (s, e) => s + e.amount);
    final daily = widget.entries.where((e) => e.type == EntryType.daily);
    final oneTime = widget.entries.where((e) => e.type == EntryType.oneTime);
    int sum(Iterable<Entry> es) => es.fold<int>(0, (s, e) => s + e.amount);
    final safeNow = state.safeToSpendNow.perDay ~/ 100 * 100;
    Widget line(String left, Widget right) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(left, style: theme.textTheme.bodyLarge)),
              right,
            ],
          ),
        );
    Widget money(int c) => Text(
          formatPeso(-c),
          style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600, color: debtColor(context)),
        );
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
            children: <Widget>[
              Center(
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: theme.colorScheme.primary,
                  child: Icon(Icons.check,
                      size: 34, color: theme.colorScheme.onPrimary),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Added ${widget.entries.length} '
                '${widget.entries.length == 1 ? 'entry' : 'entries'}',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatPeso(-total)} spent, '
                '${_shortRange(widget.first, widget.last)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: <Widget>[
                      if (daily.isNotEmpty)
                        line('Daily · ${daily.length}', money(sum(daily))),
                      if (oneTime.isNotEmpty)
                        line('One-time · ${oneTime.length}', money(sum(oneTime))),
                      if (widget.leftOut > 0)
                        line(
                          'Left out · ${widget.leftOut}'
                          '${widget.duplicates > 0 ? ' (${widget.duplicates} duplicate${widget.duplicates == 1 ? '' : 's'})' : ''}',
                          Text('not added',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('What changed',
                          style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Text(
                        'Cash on hand ${formatPeso(widget.cashBefore)} → '
                        '${formatPeso(state.cashNow)}',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Safe to spend ${formatPeso(safeNow)} a day '
                        '(was ${formatPeso(widget.safeBefore)})',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54)),
                    onPressed: _busy ? null : _undo,
                    child: const Text('Undo all'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54)),
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Done'),
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
