import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/export.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';

class _Data {
  final List<Rec> members, attendance, txns;
  _Data(this.members, this.attendance, this.txns);
}

/// Reports and analytics. Each section is shown only to the roles that may read that data.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late int _fy = fyStartOf(DateTime.now());
  late (int, int) _ym = (DateTime.now().year, DateTime.now().month);

  Future<_Data> _load() async => _Data(
        Perms.members ? await Store.members() : [],
        Perms.attendance ? await Store.attendance() : [],
        Perms.finance ? await Store.txns(fy: _fy) : [],
      );

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Live<_Data>(
        key: ValueKey('$_fy'),
        load: _load,
        builder: (c, d) => ListView(padding: const EdgeInsets.only(bottom: 30), children: [
          if (Perms.members) ..._membership(d),
          if (Perms.attendance) ..._attendance(c, d),
          if (Perms.finance) ..._finance(c, d),
        ]),
      ),
    );
  }

  Widget _card(List<Widget> kids) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: isDark(context) ? Theme.of(context).colorScheme.surfaceContainerHigh : Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
      );

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(k)), Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600))]),
      );

  // ---------------------------------------------------------------- membership
  List<Widget> _membership(_Data d) {
    final by = {for (final s in memberStatuses) s: d.members.where((m) => m.s('status') == s).length};
    final fams = d.members.map((m) => m.s('familyName').toLowerCase()).where((x) => x.isNotEmpty).toSet().length;
    return [
      const SectionTitle('Membership'),
      _card([
        _kv('Total members', '${d.members.length}', bold: true),
        for (final e in by.entries) _kv(e.key, '${e.value}'),
        _kv('Families', '$fams'),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => Exporter.members(), icon: const Icon(Icons.table_view_outlined), label: const Text('Export member list (Excel)'))),
      ]),
    ];
  }

  // ---------------------------------------------------------------- attendance
  List<Widget> _attendance(BuildContext context, _Data d) {
    final months = [for (var i = 0; i < 12; i++) DateTime(DateTime.now().year, DateTime.now().month - i, 1)];
    final inMonth = d.attendance.where((a) {
      final x = parseDate(a.s('date'));
      return x != null && x.year == _ym.$1 && x.month == _ym.$2;
    }).toList();
    final perService = <String, List<Rec>>{};
    for (final a in inMonth) {
      perService.putIfAbsent(a.s('service'), () => []).add(a);
    }
    final trend = d.attendance.where((a) => a.s('service') == 'Sunday Worship').take(8).toList().reversed.toList();
    final maxP = trend.fold<int>(1, (m, a) => a.i('presentCount') > m ? a.i('presentCount') : m);
    return [
      const SectionTitle('Monthly attendance'),
      _card([
        DropdownButton<(int, int)>(
          value: _ym,
          isExpanded: true,
          items: [for (final m in months) DropdownMenuItem(value: (m.year, m.month), child: Text('${monthName(m.month)} ${m.year}'))],
          onChanged: (v) => setState(() => _ym = v ?? _ym),
        ),
        if (perService.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No attendance recorded in this month.')),
        for (final e in perService.entries) ...[
          _kv(e.key, '${e.value.length} meeting${e.value.length == 1 ? '' : 's'} · avg ${(e.value.fold<int>(0, (s, a) => s + a.i('presentCount')) / e.value.length).toStringAsFixed(1)}'),
        ],
      ]),
      if (trend.isNotEmpty) ...[
        const SectionTitle('Sunday Worship attendance trend (last 8)'),
        _card([
          for (final a in trend)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 62, child: Text(fmtDate(a.s('date')).substring(0, 6), style: const TextStyle(fontSize: 12))),
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: a.i('presentCount') / maxP, minHeight: 12, color: accentGreen))),
                SizedBox(width: 36, child: Text('${a.i('presentCount')}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ),
        ]),
      ],
    ];
  }

  // ---------------------------------------------------------------- finance
  List<Widget> _finance(BuildContext context, _Data d) {
    final live = d.txns.where((t) => !Store.isVoid(t)).toList();
    double sum(String kind, [String? mode]) => r2(live.where((t) => t.s('kind') == kind && (mode == null || t.s('mode') == mode)).fold(0.0, (a, t) => a + amountOf(t)));
    Map<String, double> byHead(String kind) {
      final m = <String, double>{};
      for (final t in live.where((t) => t.s('kind') == kind)) {
        m[t.s('head')] = (m[t.s('head')] ?? 0) + amountOf(t);
      }
      return m;
    }

    Widget heads(String title, Map<String, double> m, Color color) {
      final rows = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return _card([
        Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
        const SizedBox(height: 4),
        if (rows.isEmpty) const Text('Nothing recorded.'),
        for (final e in rows) _kv(e.key, money(e.value)),
      ]);
    }

    final fys = [for (var y = fyStartOf(DateTime.now()) - 5; y <= fyStartOf(DateTime.now()) + 1; y++) y].reversed.toList();
    return [
      const SectionTitle('Financial year summary'),
      _card([
        Row(children: [
          const Text('Financial year', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          DropdownButton<int>(value: _fy, items: [for (final y in fys) DropdownMenuItem(value: y, child: Text(fyLabel(y)))], onChanged: (v) => setState(() => _fy = v ?? _fy)),
        ]),
        _kv('Total receipts', money(sum('receipt')), bold: true),
        _kv('   Cash', money(sum('receipt', 'cash'))),
        _kv('   Bank', money(sum('receipt', 'bank'))),
        _kv('Total payments', money(sum('payment')), bold: true),
        _kv('   Cash', money(sum('payment', 'cash'))),
        _kv('   Bank', money(sum('payment', 'bank'))),
        const Divider(),
        _kv(sum('receipt') >= sum('payment') ? 'Surplus for the year' : 'Deficit for the year', money(sum('receipt') - sum('payment')), bold: true),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => Exporter.cashBook(_fy), icon: const Icon(Icons.table_view_outlined), label: const Text('Export cash book (Excel)'))),
      ]),
      heads('Receipts by head', byHead('receipt'), const Color(0xFF2E7D32)),
      heads('Payments by head', byHead('payment'), const Color(0xFFC62828)),
    ];
  }
}
