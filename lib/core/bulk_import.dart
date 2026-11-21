import 'package:excel/excel.dart';

import 'store.dart';
import 'util.dart';

String _fyRange(int fy) => '${fmtDate(dateStr(DateTime(fy, 4, 1)))} to ${fmtDate(dateStr(DateTime(fy + 1, 3, 31)))}';

class BulkRow {
  final int line; // row number in the Excel sheet
  final Map<String, dynamic> data;
  final List<String> errors;
  String? skipReason;
  BulkRow(this.line, this.data, this.errors);
  bool get ok => errors.isEmpty && skipReason == null;
}

class BulkResult {
  final int fy;
  final List<BulkRow> rows;
  final ({double cash, double bank})? opening; // from the "Opening Balance" sheet, when filled in
  final String? fileError;
  BulkResult(this.fy, this.rows, {this.opening, this.fileError});
  List<BulkRow> get valid => rows.where((r) => r.ok).toList();
  List<BulkRow> get invalid => rows.where((r) => r.errors.isNotEmpty).toList();
  List<BulkRow> get skipped => rows.where((r) => r.errors.isEmpty && r.skipReason != null).toList();
  double get receipts => valid.where((r) => r.data['kind'] == 'receipt').fold(0.0, (a, r) => a + (r.data['amount'] as double));
  double get payments => valid.where((r) => r.data['kind'] == 'payment').fold(0.0, (a, r) => a + (r.data['amount'] as double));
}

/// Excel template and bulk upload of receipts / payments (and the opening balance) for one financial year (April - March).
class BulkImport {
  static const txnSheet = 'Transactions';
  static const openSheet = 'Opening Balance';
  static const maxRows = 5000;

  static const headers = ['Date*', 'Type*', 'Head of Account*', 'Mode*', 'Amount*', 'Narration', 'Reference No'];
  static const _keys = ['date', 'type', 'head', 'mode', 'amount', 'narration', 'ref'];

  static String _norm(String h) => h.toLowerCase().replaceAll('*', '').replaceAll(RegExp(r'[^a-z]'), '');

  // ------------------------------------------------------------------ template
  static List<int> buildTemplate(int fy) {
    final x = Excel.createExcel();
    final def = x.getDefaultSheet();
    if (def != null && def != txnSheet) x.rename(def, txnSheet);
    final sh = x[txnSheet];

    final req = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#0047CC'), fontColorHex: ExcelColor.white);
    final opt = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#FF6A00'), fontColorHex: ExcelColor.white);
    const widths = [14.0, 12.0, 30.0, 10.0, 14.0, 40.0, 18.0];
    for (var c = 0; c < headers.length; c++) {
      final cell = sh.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headers[c].endsWith('*') ? req : opt;
      sh.setColumnWidth(c, widths[c]);
    }

    final ob = x[openSheet];
    for (var c = 0; c < 2; c++) {
      final cell = ob.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.value = TextCellValue(c == 0 ? 'Cash' : 'Bank');
      cell.cellStyle = opt;
      ob.setColumnWidth(c, 18);
    }
    ob.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0)).value =
        TextCellValue('Optional. Balance on 1 April $fy (row 2). Leave empty to keep the opening balance already in the app.');

    final heads = x['Heads'];
    heads.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Receipt heads');
    heads.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Payment heads');
    for (var i = 0; i < defaultReceiptHeads.length; i++) {
      heads.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(defaultReceiptHeads[i]);
    }
    for (var i = 0; i < defaultPaymentHeads.length; i++) {
      heads.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = TextCellValue(defaultPaymentHeads[i]);
    }
    heads.setColumnWidth(0, 30);
    heads.setColumnWidth(1, 30);

    final info = x['Instructions'];
    final lines = <String>[
      'Freely CMS - Receipts & Payments bulk upload template',
      'Financial year: ${fyLabel(fy)}  (${_fyRange(fy)})',
      '',
      'HOW TO USE',
      '1. Enter one receipt or payment per row on the "$txnSheet" sheet, from row 2. Do not change the header row.',
      '2. Blue headers (marked *) are required. Orange headers are optional.',
      '3. Date must fall inside the financial year ${fyLabel(fy)} (${_fyRange(fy)}). Use DD-MM-YYYY or real Excel dates.',
      '4. Type: Receipt or Payment.',
      '5. Head of Account: see the "Heads" sheet. Any other name is created as a new head.',
      '6. Mode: Cash or Bank.',
      '7. Amount: a number greater than zero (no currency sign).',
      '8. Optional: fill the "$openSheet" sheet with the cash and bank balance on 1 April.',
      '9. Rows already in the app (same date, type, head, mode, amount, narration and reference) are skipped, so uploading the same file twice does not double the entries.',
      '10. Save as .xlsx and upload it from Finance > Bulk upload (Excel), choosing the same financial year.',
      '11. Maximum $maxRows rows per upload.',
      '',
      'EXAMPLE ROWS',
      '15-04-$fy | Receipt | Sunday Offering A/C | Cash | 12500 | Offering 14 Apr |',
      '20-04-$fy | Payment | Electricity and water | Bank | 3200.50 | April bill | EB-4411',
    ];
    for (var i = 0; i < lines.length; i++) {
      final cell = info.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i));
      cell.value = TextCellValue(lines[i]);
      if (i == 0 || i == 3 || i == 16) cell.cellStyle = CellStyle(bold: true);
    }
    info.setColumnWidth(0, 120);
    x.setDefaultSheet(txnSheet);
    return x.encode()!;
  }

  // ------------------------------------------------------------------ parsing
  static String _text(CellValue? v) {
    if (v == null) return '';
    return switch (v) {
      TextCellValue() => v.value.toString().trim(),
      IntCellValue() => v.value.toString(),
      DoubleCellValue() => v.value == v.value.roundToDouble() ? v.value.toInt().toString() : v.value.toString(),
      DateCellValue() => dateStr(v.asDateTimeLocal()),
      DateTimeCellValue() => dateStr(v.asDateTimeLocal()),
      BoolCellValue() => v.value.toString(),
      _ => v.toString().trim(),
    };
  }

  static DateTime? _date(CellValue? v) {
    if (v == null) return null;
    if (v is DateCellValue) return v.asDateTimeLocal();
    if (v is DateTimeCellValue) return v.asDateTimeLocal();
    if (v is IntCellValue || v is DoubleCellValue) {
      final n = v is IntCellValue ? v.value : (v as DoubleCellValue).value.floor();
      if (n < 20000 || n > 80000) return null;
      return DateTime(1899, 12, 30).add(Duration(days: n));
    }
    return parseDateText(_text(v));
  }

  static const _mon = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

  /// DD-MM-YYYY, DD/MM/YYYY, DD.MM.YYYY, YYYY-MM-DD, DD-Mon-YYYY. Day first. Null when not a real date.
  static DateTime? parseDateText(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    int? d, m, y;
    var r = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
    if (r != null) {
      y = int.parse(r[1]!); m = int.parse(r[2]!); d = int.parse(r[3]!);
    } else if ((r = RegExp(r'^(\d{1,2})[-/. ](\d{1,2})[-/. ](\d{2,4})$').firstMatch(s)) != null) {
      d = int.parse(r![1]!); m = int.parse(r[2]!); y = int.parse(r[3]!);
      if (y < 100) y += 2000;
    } else if ((r = RegExp(r'^(\d{1,2})[-/. ]([A-Za-z]{3})[A-Za-z]*[-/. ,]*(\d{2,4})$').firstMatch(s)) != null) {
      d = int.parse(r![1]!); m = _mon[r[2]!.toLowerCase()]; y = int.parse(r[3]!);
      if (y < 100) y += 2000;
    }
    if (d == null || m == null || y == null || m < 1 || m > 12 || d < 1) return null;
    final dt = DateTime(y, m, d);
    return (dt.month == m && dt.day == d) ? dt : null;
  }

  /// "12,500.50" / "Rs. 1250" / numeric cell -> number. Null when not a number.
  static double? parseAmount(CellValue? v) {
    if (v == null) return null;
    if (v is IntCellValue) return v.value.toDouble();
    if (v is DoubleCellValue) return v.value;
    final t = _text(v).replaceAll(RegExp(r'[,\s]|rs\.?|₹', caseSensitive: false), '');
    return double.tryParse(t);
  }

  static String? parseKind(String s) => switch (s.trim().toLowerCase()) {
        'receipt' || 'receipts' || 'r' => 'receipt',
        'payment' || 'payments' || 'p' => 'payment',
        _ => null,
      };

  static String? parseMode(String s) => switch (s.trim().toLowerCase()) {
        'cash' || 'c' => 'cash',
        'bank' || 'b' || 'cheque' || 'online' || 'upi' || 'neft' || 'rtgs' || 'imps' => 'bank',
        _ => null,
      };

  static String _sig(String date, String kind, String head, String mode, double amt, String narr, String ref) =>
      '$date|$kind|${head.toLowerCase()}|$mode|${r2(amt)}|${narr.toLowerCase()}|${ref.toLowerCase()}';

  /// Reads and validates [bytes] (an .xlsx file) against financial year [fy]. Nothing is saved.
  static Future<BulkResult> parse(List<int> bytes, int fy) async {
    final Excel x;
    try {
      x = Excel.decodeBytes(bytes);
    } catch (_) {
      return BulkResult(fy, [], fileError: 'This is not a valid .xlsx Excel file. Please use the template and save it as .xlsx.');
    }
    final sh = x.tables[txnSheet] ?? (x.tables.isEmpty ? null : x.tables.values.first);
    if (sh == null || sh.maxRows < 1) return BulkResult(fy, [], fileError: 'The "$txnSheet" sheet is empty.');

    final rows = sh.rows;
    final col = <String, int>{};
    for (var c = 0; c < rows.first.length; c++) {
      final h = _norm(_text(rows.first[c]?.value));
      for (var k = 0; k < headers.length; k++) {
        if (_norm(headers[k]) == h) col[_keys[k]] = c;
      }
    }
    final missing = [for (var k = 0; k < headers.length; k++) if (headers[k].endsWith('*') && !col.containsKey(_keys[k])) headers[k]];
    if (missing.isNotEmpty) {
      return BulkResult(fy, [], fileError: 'Missing column(s): ${missing.join(', ')}. Please download the template again and keep the header row.');
    }
    CellValue? cell(List<Data?> row, String key) {
      final c = col[key];
      return (c == null || c >= row.length) ? null : row[c]?.value;
    }

    // Existing live entries of this FY: an uploaded row matching one is skipped (one existing entry per uploaded row).
    final all = await Store.txns(fy: fy);
    final existing = <String, int>{};
    final knownHeads = <String, String>{};
    for (final t in all) {
      if (Store.isVoid(t)) continue;
      final k = _sig(t.s('date'), t.s('kind'), t.s('head'), t.s('mode'), amountOf(t), t.s('narration'), t.s('ref'));
      existing[k] = (existing[k] ?? 0) + 1;
    }
    for (final h in [...defaultReceiptHeads, ...defaultPaymentHeads, for (final t in all) t.s('head')]) {
      if (h.isNotEmpty) knownHeads.putIfAbsent(h.toLowerCase(), () => h);
    }

    final out = <BulkRow>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((c) => _text(c?.value).isEmpty)) continue;
      if (out.length >= maxRows) {
        return BulkResult(fy, out, fileError: 'Too many rows. Upload at most $maxRows entries at a time.');
      }
      final errors = <String>[];

      final dRaw = cell(row, 'date');
      final date = _date(dRaw);
      if (_text(dRaw).isEmpty) {
        errors.add('Date is required');
      } else if (date == null) {
        errors.add('Date is not valid (use DD-MM-YYYY)');
      } else if (fyStartOf(date) != fy) {
        errors.add('Date ${fmtDate(dateStr(date))} is outside FY ${fyLabel(fy)}');
      }

      final kind = parseKind(_text(cell(row, 'type')));
      if (kind == null) errors.add('Type must be Receipt or Payment');

      var head = _text(cell(row, 'head'));
      if (head.isEmpty) {
        errors.add('Head of account is required');
      } else {
        head = knownHeads[head.toLowerCase()] ?? head;
      }

      final mode = parseMode(_text(cell(row, 'mode')));
      if (mode == null) errors.add('Mode must be Cash or Bank');

      final amt = parseAmount(cell(row, 'amount'));
      if (amt == null || amt.isNaN || amt.isInfinite || amt <= 0) errors.add('Amount must be a number greater than zero');

      final narr = _text(cell(row, 'narration'));
      final ref = _text(cell(row, 'ref'));
      final data = <String, dynamic>{
        'date': date == null ? '' : dateStr(date), 'kind': kind ?? '', 'head': head, 'mode': mode ?? '',
        'amount': amt == null ? 0.0 : r2(amt), 'narration': narr, 'ref': ref,
      };
      final r = BulkRow(i + 1, data, errors);
      if (errors.isEmpty) {
        final k = _sig(data['date'] as String, kind!, head, mode!, amt!, narr, ref);
        final n = existing[k] ?? 0;
        if (n > 0) {
          existing[k] = n - 1;
          r.skipReason = 'Already in the app (same date, head, amount, mode and details)';
        }
      }
      out.add(r);
    }

    // Optional opening balance
    ({double cash, double bank})? opening;
    final ob = x.tables[openSheet];
    if (ob != null && ob.rows.length > 1) {
      final row = ob.rows[1];
      final cash = row.isNotEmpty ? parseAmount(row[0]?.value) : null;
      final bank = row.length > 1 ? parseAmount(row[1]?.value) : null;
      if (cash != null || bank != null) opening = (cash: r2(cash ?? 0), bank: r2(bank ?? 0));
    }

    if (out.isEmpty && opening == null) return BulkResult(fy, [], fileError: 'No entries found below the header row.');
    return BulkResult(fy, out, opening: opening);
  }

  // ------------------------------------------------------------------ saving
  /// Saves every valid row on the phone (it syncs like any other entry). Returns how many were added.
  static Future<int> commit(BulkResult res) async {
    var n = 0;
    for (final r in res.valid) {
      await Store.save(tTxn, audit: false, data: r.data);
      n++;
    }
    if (res.opening != null) await Store.saveOpening(res.fy, res.opening!.cash, res.opening!.bank);
    if (n > 0) {
      await Store.audit('created', tTxn, 'bulk-${res.fy}', 'Bulk upload: $n entries added for FY ${fyLabel(res.fy)} (receipts ${money(res.receipts)}, payments ${money(res.payments)})');
    }
    return n;
  }
}
