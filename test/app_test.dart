import 'package:excel/excel.dart';
import 'package:freely_cms/core/bulk_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freely_cms/core/db.dart';
import 'package:freely_cms/core/store.dart';
import 'package:freely_cms/core/util.dart';
import 'package:freely_cms/core/cloud.dart';

Rec txn(String kind, String mode, double amt, {String date = '2022-04-05', String head = 'General Expenses'}) =>
    Rec(id: newId(), orgId: 'o', type: tTxn, updatedAt: nowIso(), data: {'date': date, 'kind': kind, 'mode': mode, 'amount': amt, 'head': head});

void main() {
  test('financial year runs April to March', () {
    expect(fyStartOf(DateTime(2022, 4, 1)), 2022);
    expect(fyStartOf(DateTime(2023, 3, 31)), 2022);
    expect(fyStartOf(DateTime(2023, 4, 1)), 2023);
    expect(fyLabel(2022), '2022-23');
    expect(fyLabel(2099), '2099-00');
  });

  test('money uses Indian digit grouping', () {
    expect(money(0), '0.00');
    expect(money(999.5), '999.50');
    expect(money(1234567.5), '12,34,567.50');
    expect(money(100000), '1,00,000.00');
    expect(money(-4500), '-4,500.00');
  });

  test('month book: opening + receipts = payments + balance C/F, cash and bank kept apart', () {
    final b = MonthBook(2022, 4, 1000, 5000, [txn('receipt', 'cash', 200), txn('receipt', 'bank', 300)], [txn('payment', 'cash', 150), txn('payment', 'bank', 50.25)]);
    expect(b.totalReceiptsCash, 1200);
    expect(b.totalReceiptsBank, 5300);
    expect(b.closeCash, 1050);
    expect(b.closeBank, 5249.75);
    expect(b.pCash + b.closeCash, b.totalReceiptsCash);
    expect(b.pBank + b.closeBank, b.totalReceiptsBank);
  });

  test('rounding never drifts on repeated cents', () {
    final b = MonthBook(2022, 4, 0, 0, [for (var i = 0; i < 100; i++) txn('receipt', 'cash', 0.1)], []);
    expect(b.rCash, 10.0);
  });

  test('attendance ids are stable per day and service', () {
    expect(Store.attendanceId('2026-11-15', 'Sunday Worship'), 'att-2026-11-15-sunday-worship');
    expect(Store.attendanceId('2026-11-15', 'Sunday School'), isNot(Store.attendanceId('2026-11-15', 'Sunday Worship')));
  });

  test('default heads come from the church sample sheet and custom heads are added', () {
    final used = [txn('receipt', 'cash', 1, head: 'Christmas Offering')];
    final heads = Store.heads('receipt', used);
    expect(heads, contains('Sunday Offering A/C'));
    expect(heads, contains('Christmas Offering'));
    expect(Store.heads('payment', used), isNot(contains('Christmas Offering')));
  });

  test('invite code and admin key round-trip', () {
    const url = 'https://script.google.com/macros/s/AKfycbxyz123/exec';
    final inv = Sheets.parseInvite(Sheets.invite('ABCD2345', url))!;
    expect(inv.code, 'ABCD2345');
    expect(inv.url, url);
    expect(normMobile('+91 98765 43210'), '9876543210');
    expect(validMobile('12345'), false);
  });

  test('bulk import: parsing helpers and financial year', () {
    expect(BulkImport.parseDateText('15-06-2025'), DateTime(2025, 6, 15));
    expect(BulkImport.parseDateText('31-02-2025'), isNull);
    expect(BulkImport.parseKind(' Receipt '), 'receipt');
    expect(BulkImport.parseKind('Payments'), 'payment');
    expect(BulkImport.parseKind('x'), isNull);
    expect(BulkImport.parseMode('UPI'), 'bank');
    expect(BulkImport.parseMode('Cash'), 'cash');
    expect(BulkImport.parseAmount(TextCellValue('Rs. 12,500.50')), 12500.5);
    expect(BulkImport.parseAmount(TextCellValue('abc')), isNull);
    expect(fyStartOf(DateTime(2026, 3, 31)), 2025);
    final x = Excel.decodeBytes(BulkImport.buildTemplate(2025));
    expect(x.tables.keys, containsAll(['Transactions', 'Opening Balance', 'Heads', 'Instructions']));
    expect(x.tables['Transactions']!.rows.first.length, 7);
  });
}
