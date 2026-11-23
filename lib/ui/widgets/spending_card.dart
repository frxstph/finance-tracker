import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/spending.dart';
import '../../state/app_state.dart';
import '../theme.dart';

/// The Dashboard's Spending card: 30 days, Weeks (quarter months), Months
/// (last 12) and Quarters. Design: "Spending chart" canvas.
class SpendingCard extends StatefulWidget {
  const SpendingCard({super.key});

  @override
  State<SpendingCard> createState() => _SpendingCardState();
}

enum _Range { days, weeks, months, quarters }

const List<String> _weekdays = <String>[
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];
const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const List<String> _monthNames = <String>[
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

class _SpendingCardState extends State<SpendingCard> {
  _Range _range = _Range.days;
  int? _picked;

  static const double _chartHeight = 150;

  Color _everyday(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF6CC497)
          : const Color(0xFF2E7D57);

  Color _light(BuildContext c) => _everyday(c).withAlpha(95);

  Color _ghost(BuildContext c) =>
      Theme.of(c).colorScheme.onSurface.withAlpha(45);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final entries = state.allEntries;
    final today = DateTime.now();
    final Widget body;
    switch (_range) {
      case _Range.days:
        body = _days(context, entries, today,
            state.safeToSpendNow.perDay ~/ 100 * 100);
      case _Range.weeks:
        body = _weeks(context, entries, today);
      case _Range.months:
        body = _monthsView(context, entries, today);
      case _Range.quarters:
        body = _quarters(context, entries, today);
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Spending',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SegmentedButton<_Range>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              segments: const <ButtonSegment<_Range>>[
                ButtonSegment<_Range>(value: _Range.days, label: Text('30 days')),
                ButtonSegment<_Range>(value: _Range.weeks, label: Text('Weeks')),
                ButtonSegment<_Range>(value: _Range.months, label: Text('Months')),
                ButtonSegment<_Range>(
                    value: _Range.quarters, label: Text('Quarters')),
              ],
              selected: <_Range>{_range},
              onSelectionChanged: (s) => setState(() {
                _range = s.first;
                _picked = null;
              }),
            ),
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
    );
  }

  Widget _headline(BuildContext context, int total, String sub,
      {InlineSpan? extra}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatPeso(-total),
            maxLines: 1,
            style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700, color: debtColor(context)),
          ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(text: sub, children: <InlineSpan>[if (extra != null) extra]),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context, InlineSpan text) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Text.rich(text,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  Widget _legend(BuildContext context, List<(Widget, String)> items) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: <Widget>[
          for (final (swatch, text) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                swatch,
                const SizedBox(width: 5),
                Text(text, style: theme.textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }

  Widget _swatch(Color c, {bool striped = false}) => SizedBox(
        width: 10,
        height: 10,
        child: CustomPaint(painter: _BarPainter(c, striped: striped, radius: 2)),
      );

  // ---- 30 days ----

  Widget _days(BuildContext context, List<Entry> entries, DateTime today, int safe) {
    final theme = Theme.of(context);
    final bars = last30Days(entries, today);
    final total = bars.fold<int>(0, (s, b) => s + b.amount);
    final over = safe > 0 ? bars.where((b) => b.amount > safe).length : 0;
    final max = bars.fold<int>(safe, (m, b) => b.amount > m ? b.amount : m);
    final orange = billsColor(context);
    final green = _everyday(context);
    final bills = totalsBetween(entries, bars.first.day, today).billsLoans;
    final picked = _picked == null ? null : bars[_picked!];
    String dayLabel(DateTime d) =>
        '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _headline(context, total,
            'Everyday spending, last 30 days · about ${formatPeso(total ~/ 30 ~/ 100 * 100)} a day'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: AnimatedOpacity(
            opacity: picked == null ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.inverseSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                picked == null
                    ? ' '
                    : '${dayLabel(picked.day)} · ${formatPeso(picked.amount)}',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _chartHeight,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Semantics(
                  label: 'Daily spending for the last 30 days'
                      '${over > 0 ? ', $over days over Safe to spend' : ''}',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      for (var i = 0; i < bars.length; i++)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(
                                () => _picked = _picked == i ? null : i),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 6,
                                height: max == 0
                                    ? 2
                                    : (bars[i].amount / max * _chartHeight)
                                        .clamp(2.0, _chartHeight)
                                        .toDouble(),
                                decoration: BoxDecoration(
                                  color: bars[i].amount == 0
                                      ? _ghost(context)
                                      : safe > 0 && bars[i].amount > safe
                                          ? orange
                                          : green,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3)),
                                  border: _picked == i
                                      ? Border.all(
                                          color: theme.colorScheme.onSurface,
                                          width: 2)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (safe > 0 && max > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: safe / max * _chartHeight,
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: const Size.fromHeight(2),
                      painter: _DashedLine(theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (final i in <int>[0, 7, 14, 21])
              Text('${_months[bars[i].day.month - 1]} ${bars[i].day.day}',
                  style: theme.textTheme.labelSmall),
            Text('Today', style: theme.textTheme.labelSmall),
          ],
        ),
        _legend(context, <(Widget, String)>[
          (_swatch(green), safe > 0 ? 'Within budget' : 'Spent'),
          if (safe > 0) (_swatch(orange), 'Over ($over ${over == 1 ? 'day' : 'days'})'),
          if (safe > 0)
            (
              SizedBox(
                  width: 14,
                  height: 2,
                  child: CustomPaint(
                      painter: _DashedLine(theme.colorScheme.onSurfaceVariant))),
              'Safe to spend ${formatPeso(safe)}'
            ),
        ]),
        _footer(
          context,
          TextSpan(children: <InlineSpan>[
            const TextSpan(text: 'Plus '),
            TextSpan(
                text: formatPeso(bills),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' in bills and loan payments'),
          ]),
        ),
      ],
    );
  }

  // ---- Weeks ----

  Widget _weeks(BuildContext context, List<Entry> entries, DateTime today) {
    final theme = Theme.of(context);
    final w = weekBars(entries, today);
    final mtd = monthToDate(entries, today);
    final diff = mtd.thisMonth - mtd.lastMonth;
    final lastName = _monthNames[(today.month + 10) % 12];
    final thisName = _monthNames[today.month - 1];
    final max = w.fold<int>(
        1,
        (m, b) => [m, b.thisMonth, b.lastMonth]
            .reduce((a, c) => a > c ? a : c));
    final green = _everyday(context);
    final first = DateTime(today.year, today.month, 1);
    final bills = totalsBetween(entries, first, today).billsLoans;
    InlineSpan compare;
    if (diff == 0) {
      compare = TextSpan(text: ' · same as $lastName by this date');
    } else {
      compare = TextSpan(children: <InlineSpan>[
        const TextSpan(text: ' · '),
        TextSpan(
          text: '${formatPeso(diff.abs())} ${diff > 0 ? 'more' : 'less'}',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: diff > 0 ? billsColor(context) : incomeColor(context)),
        ),
        TextSpan(text: ' than $lastName by this date'),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _headline(context, mtd.thisMonth, '$thisName so far', extra: compare),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (final b in w)
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(
                      b.future
                          ? ''
                          : b.inProgress
                              ? '${formatPeso(b.thisMonth)}\nso far'
                              : formatPeso(b.thisMonth),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: _chartHeight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          _bar(_ghost(context), b.lastMonth / max, 14),
                          const SizedBox(width: 4),
                          _bar(green, b.thisMonth / max, 22,
                              striped: b.inProgress),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            for (final b in w)
              Expanded(
                child: Text(b.label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall),
              ),
          ],
        ),
        _legend(context, <(Widget, String)>[
          (_swatch(green), thisName),
          (_swatch(_ghost(context)), lastName),
          (_swatch(green, striped: true), 'This week, still going'),
        ]),
        _footer(
          context,
          TextSpan(children: <InlineSpan>[
            const TextSpan(text: 'Plus '),
            TextSpan(
                text: formatPeso(bills),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' in bills and loan payments this month'),
          ]),
        ),
      ],
    );
  }

  Widget _bar(Color c, double fraction, double width, {bool striped = false}) {
    final h = (fraction.isFinite ? fraction : 0) * _chartHeight;
    return SizedBox(
      width: width,
      height: h < 2 ? 2 : h,
      child: CustomPaint(painter: _BarPainter(c, striped: striped)),
    );
  }

  // ---- Months and quarters ----

  Widget _stacked(BuildContext context, List<PeriodBar> bars,
      {required double barWidth, bool tops = false}) {
    final theme = Theme.of(context);
    final max = bars.fold<int>(1, (m, b) => b.total > m ? b.total : m);
    final green = _everyday(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (final b in bars)
              Expanded(
                child: Column(
                  children: <Widget>[
                    if (tops)
                      Text(
                        b.future || b.total == 0
                            ? ''
                            : '${compactPeso(b.total)}${b.inProgress ? ' so far' : ''}',
                        maxLines: 1,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    if (tops) const SizedBox(height: 4),
                    SizedBox(
                      height: _chartHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          if (b.billsLoans > 0)
                            SizedBox(
                              width: barWidth,
                              height: b.billsLoans / max * _chartHeight,
                              child: CustomPaint(
                                  painter: _BarPainter(_light(context),
                                      roundBottom: false)),
                            ),
                          SizedBox(
                            width: barWidth,
                            height: b.total == 0
                                ? 2
                                : b.everyday / max * _chartHeight,
                            child: CustomPaint(
                              painter: _BarPainter(
                                b.total == 0 ? _ghost(context) : green,
                                striped: b.inProgress,
                                roundTop: b.billsLoans == 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            for (final b in bars)
              Expanded(
                child: Text(b.label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall),
              ),
          ],
        ),
        _legend(context, <(Widget, String)>[
          (_swatch(green), 'Everyday'),
          (_swatch(_light(context)), 'Bills and loans'),
          (_swatch(green, striped: true), 'Still going'),
        ]),
      ],
    );
  }

  Widget _monthsView(BuildContext context, List<Entry> entries, DateTime today) {
    final bars = monthBars(entries, today);
    final total = bars.fold<int>(0, (s, b) => s + b.total);
    final full = bars.where((b) => !b.inProgress && b.total > 0).toList();
    final avg = full.isEmpty
        ? 0
        : full.fold<int>(0, (s, b) => s + b.everyday) ~/ full.length;
    final first = bars.first.start;
    final last = bars.last.start;
    String name(DateTime d) => '${_months[d.month - 1]} ${d.year}';
    PeriodBar? hi;
    PeriodBar? lo;
    for (final b in full) {
      if (hi == null || b.total > hi.total) hi = b;
      if (lo == null || b.total < lo.total) lo = b;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _headline(
          context,
          total,
          '${name(first)} – ${name(last)}'
          '${avg > 0 ? ' · everyday about ${formatPeso(avg ~/ 100 * 100)} a month' : ''}',
        ),
        const SizedBox(height: 12),
        _stacked(context, bars, barWidth: 14),
        _footer(
          context,
          hi == null
              ? const TextSpan(
                  text: 'Months fill in as you use the app. The first full '
                      'month shows here once it’s over.')
              : TextSpan(children: <InlineSpan>[
                  const TextSpan(text: 'Highest: '),
                  TextSpan(
                      text: _monthNames[hi.start.month - 1],
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' (${formatPeso(hi.total)})'),
                  if (lo != null && lo != hi) ...<InlineSpan>[
                    const TextSpan(text: ' · Lowest: '),
                    TextSpan(
                        text: _monthNames[lo.start.month - 1],
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' (${formatPeso(lo.total)})'),
                  ],
                ]),
        ),
      ],
    );
  }

  Widget _quarters(BuildContext context, List<Entry> entries, DateTime today) {
    final bars = quarterBars(entries, today);
    final total = bars.fold<int>(0, (s, b) => s + b.total);
    final bills = bars.fold<int>(0, (s, b) => s + b.billsLoans);
    final full =
        bars.where((b) => !b.inProgress && !b.future && b.total > 0).toList();
    final current = bars.firstWhere((b) => b.inProgress, orElse: () => bars.last);
    final end = DateTime(current.start.year, current.start.month + 3, 0);
    InlineSpan note;
    if (full.length >= 2) {
      final a = full[full.length - 2];
      final b = full.last;
      final d = b.total - a.total;
      note = TextSpan(children: <InlineSpan>[
        TextSpan(text: '${b.label} was '),
        TextSpan(
            text: d == 0
                ? 'the same as'
                : '${formatPeso(d.abs())} ${d > 0 ? 'more' : 'less'}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: d == 0 ? ' ${a.label}' : ' than ${a.label}'),
        if (total > 0)
          TextSpan(
              text: ' · bills and loans are '
                  '${(bills * 100 / total).round()}% of the total'),
      ]);
    } else {
      note = TextSpan(
          text: total == 0
              ? 'Quarters fill in as you use the app.'
              : 'Bills and loans are ${(bills * 100 / total).round()}% of the '
                  'total so far.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _headline(context, total,
            '${today.year} so far, by quarter · ${current.label} runs to '
            '${_months[end.month - 1]} ${end.day}'),
        const SizedBox(height: 12),
        _stacked(context, bars, barWidth: 30, tops: true),
        _footer(context, note),
      ],
    );
  }
}

/// A bar, solid or striped (for a period that's still going).
class _BarPainter extends CustomPainter {
  _BarPainter(
    this.color, {
    this.striped = false,
    this.radius = 3,
    this.roundTop = true,
    this.roundBottom = false,
  });

  final Color color;
  final bool striped;
  final double radius;
  final bool roundTop;
  final bool roundBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(radius);
    final rrect = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: roundTop ? r : Radius.zero,
      topRight: roundTop ? r : Radius.zero,
      bottomLeft: roundBottom ? r : Radius.zero,
      bottomRight: roundBottom ? r : Radius.zero,
    );
    if (!striped) {
      canvas.drawRRect(rrect, Paint()..color = color);
      return;
    }
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(Offset.zero & size, Paint()..color = color.withAlpha(150));
    final stripe = Paint()
      ..color = color
      ..strokeWidth = 3;
    for (double x = -size.height; x < size.width + size.height; x += 7) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), stripe);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.color != color || old.striped != striped;
}

class _DashedLine extends CustomPainter {
  _DashedLine(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 1), Offset((x + 4).clamp(0.0, size.width).toDouble(), 1), p);
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}
