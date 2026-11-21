import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_state.dart';
import 'db.dart';
import 'store.dart';
import 'util.dart';

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
String monthName(int m) => _monthNames[m - 1];

/// The twelve months of a financial year (April - March) as (calendar year, month).
List<(int, int)> fyMonths(int fy) => [for (var i = 0; i < 12; i++) (fy + (4 + i - 1) ~/ 12, (4 + i - 1) % 12 + 1)];

TextCellValue _t(String s) => TextCellValue(s);
DoubleCellValue _d(num v) => DoubleCellValue(v.toDouble());

/// Builds Excel files and opens the phone's share sheet (save to Drive, send by WhatsApp or e-mail, ...).
class Exporter {
  static Future<void> _share(Excel ex, String name) async {
    final bytes = ex.encode();
    if (bytes == null) throw Exception('Could not create the Excel file');
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')], subject: name);
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

  /// Receipts & Expenses account of a financial year: one sheet per month in the same layout as the church's own sheet
  /// (Receipts | Cash | Bank on the left, Payments | Cash | Bank on the right, Opening Balance, totals and Balance C/F),
  /// plus a head-wise summary sheet.
  static Future<void> cashBook(int fy) async {
    final app = AppState.instance;
    final all = await Store.txns(fy: fy);
    final ex = Excel.createExcel();
    final title = '${app.orgName} Receipts and Expense Account for the year ${fyLabel(fy)}';

    for (final (y, m) in fyMonths(fy)) {
      final b = await Store.monthBook(fy, y, m, all: all);
      final sh = ex['${monthName(m).substring(0, 3)} $y'];
      sh.appendRow([_t(title)]);
      sh.appendRow([_t('Date'), _t('Receipts'), _t('Cash'), _t('Bank'), _t('Date'), _t('Payment'), _t('Cash'), _t('Bank')]);
      sh.appendRow([_t(dateStr(DateTime(y, m, 1))), _t('Opening Balance'), _d(b.openCash), _d(b.openBank)]);
      final n = b.receipts.length > b.payments.length ? b.receipts.length : b.payments.length;
      for (var i = 0; i < n; i++) {
        final r = i < b.receipts.length ? b.receipts[i] : null;
        final pm = i < b.payments.length ? b.payments[i] : null;
        sh.appendRow([
          _t(r?.s('date') ?? ''), _t(r == null ? '' : _label(r)), r != null && r.s('mode') == 'cash' ? _d(amountOf(r)) : _t(''), r != null && r.s('mode') == 'bank' ? _d(amountOf(r)) : _t(''),
          _t(pm?.s('date') ?? ''), _t(pm == null ? '' : _label(pm)), pm != null && pm.s('mode') == 'cash' ? _d(amountOf(pm)) : _t(''), pm != null && pm.s('mode') == 'bank' ? _d(amountOf(pm)) : _t(''),
        ]);
      }
      sh.appendRow([_t(''), _t('Total'), _d(b.totalReceiptsCash), _d(b.totalReceiptsBank), _t(''), _t('Total'), _d(b.pCash), _d(b.pBank)]);
      sh.appendRow([_t(''), _t(''), _t(''), _t(''), _t(dateStr(DateTime(y, m + 1, 0))), _t('Balance C/F'), _d(b.closeCash), _d(b.closeBank)]);
      sh.appendRow([_t(''), _t('Grand total'), _d(b.totalReceiptsCash), _d(b.totalReceiptsBank), _t(''), _t('Grand total'), _d(b.totalReceiptsCash), _d(b.totalReceiptsBank)]);
    }

    final live = all.where((t) => !Store.isVoid(t)).toList();
    final sum = ex['Summary ${fyLabel(fy)}'];
    sum.appendRow([_t(title)]);
    for (final kind in ['receipt', 'payment']) {
      sum.appendRow([_t('')]);
      sum.appendRow([_t(kind == 'receipt' ? 'Receipts by head' : 'Payments by head'), _t('Cash'), _t('Bank'), _t('Total')]);
      final heads = <String, List<double>>{};
      for (final t in live.where((t) => t.s('kind') == kind)) {
        final h = heads.putIfAbsent(t.s('head'), () => [0, 0]);
        h[t.s('mode') == 'cash' ? 0 : 1] += amountOf(t);
      }
      var c = 0.0, bk = 0.0;
      for (final e in (heads.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
        sum.appendRow([_t(e.key), _d(r2(e.value[0])), _d(r2(e.value[1])), _d(r2(e.value[0] + e.value[1]))]);
        c += e.value[0];
        bk += e.value[1];
      }
      sum.appendRow([_t('Total'), _d(r2(c)), _d(r2(bk)), _d(r2(c + bk))]);
    }
    ex.delete('Sheet1');
    await _share(ex, 'CashBook_${_safe(app.orgName)}_${fyLabel(fy)}.xlsx');
  }

  static String _label(Rec t) => t.s('narration').isEmpty ? t.s('head') : '${t.s('head')} - ${t.s('narration')}';

  /// The member list (only for people whose roles may read members).
  static Future<void> members() async {
    final app = AppState.instance;
    final list = await Store.members();
    final ex = Excel.createExcel();
    final sh = ex['Members'];
    sh.appendRow([_t('Name'), _t('Phone'), _t('Email'), _t('Gender'), _t('Date of birth'), _t('Address'), _t('Family'), _t('Relation'), _t('Status')]);
    for (final m in list) {
      sh.appendRow([for (final k in ['name', 'phone', 'email', 'gender', 'dob', 'address', 'familyName', 'relation', 'status']) _t(m.s(k))]);
    }
    ex.delete('Sheet1');
    await _share(ex, 'Members_${_safe(app.orgName)}.xlsx');
  }
}
