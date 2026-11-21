import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/export.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'bulk_upload_screen.dart';
import 'sync_screen.dart';

const _green = Color(0xFF2E7D32);
const _red = Color(0xFFC62828);

class _FinanceData {
  final List<Rec> all; // every transaction of the year, voided ones included
  final MonthBook book;
  _FinanceData(this.all, this.book);
}

/// The cash book of one month, laid out like the church's own "Receipts & Expenses" sheet:
/// Opening Balance + receipts = total; payments + Balance C/F = same total. Cash and bank are kept apart.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  late int _fy = fyStartOf(DateTime.now());
  late (int, int) _ym = (DateTime.now().year, DateTime.now().month);
  bool _busy = false;

  void _setFy(int fy) {
    final months = fyMonths(fy);
    setState(() {
      _fy = fy;
      _ym = months.contains(_ym) ? _ym : months.first;
    });
  }

  Future<_FinanceData> _load() async {
    final all = await Store.txns(fy: _fy);
    return _FinanceData(all, await Store.monthBook(_fy, _ym.$1, _ym.$2, all: all));
  }

  Future<void> _openingDialog() async {
    final op = await Store.opening(_fy);
    final cash = TextEditingController(text: op.cash == 0 ? '' : '${op.cash}'), bank = TextEditingController(text: op.bank == 0 ? '' : '${op.bank}');
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Opening balance ${fyLabel(_fy)}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Balance on 1 April. Later months carry their balance forward automatically.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: cash, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cash')),
          const SizedBox(height: 10),
          TextField(controller: bank, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Bank')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    await Store.saveOpening(_fy, double.tryParse(cash.text.trim()) ?? 0, double.tryParse(bank.text.trim()) ?? 0);
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      await Exporter.cashBook(_fy);
    } catch (e) {
      if (mounted) toast(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fys = [for (var y = fyStartOf(DateTime.now()) - 5; y <= fyStartOf(DateTime.now()) + 1; y++) y].reversed.toList();
    return SkyScaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'open') _openingDialog();
              if (v == 'xlsx') _export();
              if (v == 'bulk') Navigator.push(context, MaterialPageRoute(builder: (_) => BulkUploadScreen(fy: _fy)));
            },
            itemBuilder: (_) => [
              if (Perms.canWrite(tTxn)) const PopupMenuItem(value: 'bulk', child: Text('Bulk upload (Excel)')),
              const PopupMenuItem(value: 'open', child: Text('Opening balance')),
              const PopupMenuItem(value: 'xlsx', child: Text('Export year to Excel')),
            ],
          ),
        ],
      ),
      floatingActionButton: Perms.canWrite(tTxn)
          ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              FloatingActionButton.extended(
                heroTag: 'pay', backgroundColor: _red, foregroundColor: Colors.white,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TxnEditScreen(kind: 'payment'))),
                icon: const Icon(Icons.north_east), label: const Text('Payment'),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'rec', backgroundColor: _green, foregroundColor: Colors.white,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TxnEditScreen(kind: 'receipt'))),
                icon: const Icon(Icons.south_west), label: const Text('Receipt'),
              ),
            ])
          : null,
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(children: [
            const Text('Financial year', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            DropdownButton<int>(value: _fy, items: [for (final y in fys) DropdownMenuItem(value: y, child: Text(fyLabel(y)))], onChanged: (v) => v == null ? null : _setFy(v)),
          ]),
        ),
        SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            for (final ym in fyMonths(_fy))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(label: Text('${monthName(ym.$2).substring(0, 3)} ${ym.$1 % 100}'), selected: _ym == ym, onSelected: (_) => setState(() => _ym = ym)),
              ),
          ]),
        ),
        Expanded(
          child: Live<_FinanceData>(
            key: ValueKey('$_fy-$_ym'),
            load: _load,
            builder: (c, d) => _Book(d: d, ym: _ym),
          ),
        ),
      ]),
    );
  }
}

class _Book extends StatelessWidget {
  final _FinanceData d;
  final (int, int) ym;
  const _Book({required this.d, required this.ym});

  bool _inMonth(Rec t) {
    final x = parseDate(t.s('date'));
    return x != null && x.year == ym.$1 && x.month == ym.$2;
  }

  @override
  Widget build(BuildContext context) {
    final b = d.book;
    final month = d.all.where(_inMonth).toList();
    final rec = month.where((t) => t.s('kind') == 'receipt').toList(), pay = month.where((t) => t.s('kind') == 'payment').toList();
    return ListView(padding: const EdgeInsets.only(bottom: 170), children: [
      _Table(title: 'Receipts', color: _green, cols: true, children: [
        _Line(label: 'Opening Balance', cash: b.openCash, bank: b.openBank, bold: true),
        for (final t in rec) _TxnLine(t),
        _Line(label: 'Total', cash: b.totalReceiptsCash, bank: b.totalReceiptsBank, bold: true, top: true),
      ]),
      _Table(title: 'Payments', color: _red, cols: true, children: [
        for (final t in pay) _TxnLine(t),
        _Line(label: 'Total payments', cash: b.pCash, bank: b.pBank, bold: true, top: true),
        _Line(label: 'Balance C/F', cash: b.closeCash, bank: b.closeBank, bold: true),
        _Line(label: 'Total', cash: b.totalReceiptsCash, bank: b.totalReceiptsBank, bold: true, top: true),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
        child: Text('Closing balance carried to next month: cash ${money(b.closeCash)} · bank ${money(b.closeBank)} · total ${money(b.closeCash + b.closeBank)}', style: const TextStyle(fontSize: 12.5)),
      ),
    ]);
  }
}

class _Table extends StatelessWidget {
  final String title;
  final Color color;
  final bool cols;
  final List<Widget> children;
  const _Table({required this.title, required this.color, required this.cols, required this.children});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        decoration: BoxDecoration(color: isDark(context) ? Theme.of(context).colorScheme.surfaceContainerHigh : Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context)),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
            child: Row(children: [
              Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16))),
              const SizedBox(width: 92, child: Text('Cash', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
              const SizedBox(width: 92, child: Text('Bank', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
            ]),
          ),
          ...children,
          const SizedBox(height: 6),
        ]),
      );
}

class _Line extends StatelessWidget {
  final String label;
  final String? sub;
  final double? cash, bank;
  final bool bold, top, strike;
  final VoidCallback? onTap;
  const _Line({required this.label, this.sub, this.cash, this.bank, this.bold = false, this.top = false, this.strike = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final st = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: 13.5, decoration: strike ? TextDecoration.lineThrough : null, color: strike ? Colors.grey : null);
    Widget num(double? v) => SizedBox(width: 92, child: Text(v == null ? '' : money(v), textAlign: TextAlign.right, style: st));
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: top ? BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: st),
            if (sub != null && sub!.isNotEmpty) Text(sub!, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.outline, decoration: strike ? TextDecoration.lineThrough : null)),
          ])),
          num(cash), num(bank),
        ]),
      ),
    );
  }
}

class _TxnLine extends StatelessWidget {
  final Rec t;
  const _TxnLine(this.t);
  @override
  Widget build(BuildContext context) {
    final v = Store.isVoid(t);
    final amt = amountOf(t);
    return _Line(
      label: t.s('head'),
      sub: '${fmtDate(t.s('date'))}${t.s('narration').isEmpty ? '' : ' · ${t.s('narration')}'}${v ? ' · VOID: ${t.s('voidReason')}' : ''}',
      cash: t.s('mode') == 'cash' ? amt : null,
      bank: t.s('mode') == 'bank' ? amt : null,
      strike: v,
      onTap: () => showTxnSheet(context, t),
    );
  }
}

/// Details of one transaction: share a receipt, edit, or void (never delete).
void showTxnSheet(BuildContext context, Rec t) {
  final v = Store.isVoid(t);
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${t.s('kind') == 'receipt' ? 'Receipt' : 'Payment'} · ${money(amountOf(t))}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('${t.s('head')} · ${t.s('mode') == 'cash' ? 'Cash' : 'Bank'} · ${fmtDate(t.s('date'))}'),
          if (t.s('narration').isNotEmpty) Text(t.s('narration')),
          if (t.s('ref').isNotEmpty) Text('Ref: ${t.s('ref')}'),
          Text('Recorded by ${t.by} · ${fmtDateTime(t.updatedAt)}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          if (v) Padding(padding: const EdgeInsets.only(top: 8), child: Text('VOID: ${t.s('voidReason')}', style: const TextStyle(color: _red, fontWeight: FontWeight.w700))),
          if (t.conflict != null) ConflictBanner(rec: t),
          const SizedBox(height: 12),
          Wrap(spacing: 10, children: [
            if (t.s('kind') == 'receipt' && !v)
              OutlinedButton.icon(onPressed: () { Navigator.pop(c); shareReceipt(t); }, icon: const Icon(Icons.receipt_long_outlined), label: const Text('Share receipt')),
            if (!v)
              OutlinedButton.icon(onPressed: () { Navigator.pop(c); Navigator.push(context, MaterialPageRoute(builder: (_) => TxnEditScreen(kind: t.s('kind'), existing: t))); }, icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
            if (!v)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: _red),
                onPressed: () async {
                  Navigator.pop(c);
                  final why = await askText(context, 'Reason for voiding', hint: 'e.g. wrong amount entered');
                  if (why == null || why.trim().isEmpty) return;
                  await Store.voidTxn(t, why.trim());
                },
                icon: const Icon(Icons.block),
                label: const Text('Void'),
              ),
          ]),
        ]),
      ),
    ),
  );
}

void shareReceipt(Rec t) {
  final app = AppState.instance;
  final no = t.s('ref').isNotEmpty ? t.s('ref') : t.id.substring(0, 8).toUpperCase();
  Share.share('${app.orgName}\nOFFICIAL RECEIPT\n\nReceipt no: $no\nDate: ${fmtDate(t.s('date'))}\n'
      'Received: Rs. ${money(amountOf(t))} (${t.s('mode') == 'cash' ? 'Cash' : 'Bank'})\nTowards: ${t.s('head')}'
      '${t.s('narration').isEmpty ? '' : '\nDetails: ${t.s('narration')}'}\n\nThank you. God bless you.');
}

// ====================================================================== add / edit a receipt or payment
class TxnEditScreen extends StatefulWidget {
  final String kind; // receipt | payment
  final Rec? existing;
  const TxnEditScreen({super.key, required this.kind, this.existing});
  @override
  State<TxnEditScreen> createState() => _TxnEditScreenState();
}

class _TxnEditScreenState extends State<TxnEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _date = TextEditingController(text: widget.existing?.s('date') ?? dateStr(today()));
  late final _head = TextEditingController(text: widget.existing?.s('head'));
  late final _amount = TextEditingController(text: widget.existing == null ? '' : '${amountOf(widget.existing!)}');
  late final _narr = TextEditingController(text: widget.existing?.s('narration'));
  late final _ref = TextEditingController(text: widget.existing?.s('ref'));
  late String _mode = widget.existing?.s('mode').isNotEmpty == true ? widget.existing!.s('mode') : 'cash';
  List<String> _heads = [];

  bool get _isReceipt => widget.kind == 'receipt';

  @override
  void initState() {
    super.initState();
    _heads = Store.heads(widget.kind, const []);
    Store.txns().then((all) {
      if (mounted) setState(() => _heads = Store.heads(widget.kind, all));
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final amt = r2(double.parse(_amount.text.trim()));
    final ex = widget.existing;
    await Store.save(tTxn, id: ex?.id, summary: '${_isReceipt ? 'Receipt' : 'Payment'} ${money(amt)} ${_head.text.trim()} (${_mode == 'cash' ? 'cash' : 'bank'})', data: {
      ...?ex?.data,
      'date': _date.text, 'kind': widget.kind, 'head': _head.text.trim(), 'mode': _mode, 'amount': amt,
      'narration': _narr.text.trim(), 'ref': _ref.text.trim(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return SkyScaffold(
      appBar: AppBar(title: Text('${widget.existing == null ? 'Add' : 'Edit'} ${_isReceipt ? 'receipt' : 'payment'}')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          DateField(label: 'Date', controller: _date, required: true),
          gap,
          LayoutBuilder(
            builder: (c, box) => DropdownMenu<String>(
              controller: _head,
              width: box.maxWidth,
              enableFilter: true,
              requestFocusOnTap: true,
              label: Text(_isReceipt ? 'Received towards (head) *' : 'Paid for (head) *'),
              dropdownMenuEntries: [for (final h in _heads) DropdownMenuEntry(value: h, label: h)],
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 0), child: Text('Pick a head or type a new one.', style: TextStyle(fontSize: 12))),
          gap,
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount *', prefixText: 'Rs. '),
            validator: (v) {
              final x = double.tryParse((v ?? '').trim());
              return (x == null || x <= 0) ? 'Enter an amount greater than zero' : null;
            },
          ),
          gap,
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 'cash', icon: Icon(Icons.payments_outlined), label: Text('Cash')), ButtonSegment(value: 'bank', icon: Icon(Icons.account_balance_outlined), label: Text('Bank'))],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
          gap,
          TextFormField(controller: _narr, decoration: const InputDecoration(labelText: 'Narration / details')),
          gap,
          TextFormField(controller: _ref, decoration: InputDecoration(labelText: _isReceipt ? 'Receipt number (optional)' : 'Voucher / bill number (optional)')),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_head.text.trim().isEmpty) {
                toast(context, 'Choose or type the head of account');
                return;
              }
              _save();
            },
            child: const Text('Save'),
          ),
        ]),
      ),
    );
  }
}
