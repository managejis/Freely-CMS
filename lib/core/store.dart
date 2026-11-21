import 'app_state.dart';
import 'db.dart';
import 'sync.dart';
import 'util.dart';

const tMember = 'member';
const tBaptism = 'baptism'; // restricted: kept apart from the member so that only authorised roles ever receive it
const tAttendance = 'attendance';
const tEvent = 'event';
const tAnnouncement = 'announcement';
const tTxn = 'txn';
const tOpening = 'opening'; // opening cash / bank balance of a financial year
const tAudit = 'audit';
const tSettings = 'settings';
const entityTypes = {tMember, tBaptism, tAttendance, tEvent, tAnnouncement, tTxn, tOpening, tAudit, tSettings};

/// Types where the newest write simply wins (no conflict dialog).
const lastWriterWinsTypes = {tAudit, tSettings, tOpening};

const memberStatuses = ['Active', 'Inactive', 'Transferred'];
const services = ['Sunday Worship', 'Sunday School', 'Youth Meeting', 'Prayer Meeting', 'Special Meeting'];
const eventKinds = ['Sunday Worship', 'Special Meeting', 'Convention', 'Youth Meeting', 'VBS / Sunday School', 'Other'];

/// Heads of account, taken from the church's own "Receipts & Expenses" sheet. Treasurers can also type a new head.
const defaultReceiptHeads = [
  'Sunday Offering A/C', 'Special Offering A/C', 'Offering A/C', 'Sunday School A/C', 'Special Meeting A/C', 'Sale of Coconut',
  'Sale of Song book', 'Medical support', 'Social support', 'Bank A/C',
];
const defaultPaymentHeads = [
  'Auditor Fees', 'Building Maintenance', 'CC TV A/C', 'Cemetery Renewal', 'Electricity and water', 'Equipment Maintenance',
  'Equipment Purchase', 'Evangelist Fund A/C', 'Furniture Purchased', 'Gas Stove', 'General Expenses', 'Gift - Speaker',
  'House Keeping', 'Land Regulatory', 'Lift Maintenance', 'Literature support', 'Medical support', 'Meeting Expense A/C',
  'Mission Support', 'Printing & Stationery', 'Property tax', 'Social support', 'Song Book A/C', 'Special Meeting A/C',
  'Sunday School A/C', 'Bank A/C',
];

/// Financial year runs April - March (the sample is "2022-23"). The value is the calendar year in which April falls.
int fyStartOf(DateTime d) => d.month >= 4 ? d.year : d.year - 1;
String fyLabel(int start) => '$start-${((start + 1) % 100).toString().padLeft(2, '0')}';

double r2(num v) => (v * 100).round() / 100;

/// 1234567.5 -> "12,34,567.50" (Indian digit grouping).
String money(num v) {
  final neg = v < 0;
  final parts = v.abs().toStringAsFixed(2).split('.');
  var i = parts[0];
  if (i.length > 3) {
    final last3 = i.substring(i.length - 3);
    var rest = i.substring(0, i.length - 3);
    final g = <String>[];
    while (rest.length > 2) {
      g.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) g.insert(0, rest);
    i = '${g.join(',')},$last3';
  }
  return '${neg ? '-' : ''}$i.${parts[1]}';
}

double amountOf(Rec t) => ((t.data['amount'] ?? 0) as num).toDouble();

/// One month of the cash book, laid out like the church's sheet: Opening Balance, receipts, payments, totals, Balance C/F.
class MonthBook {
  final int year, month;
  final double openCash, openBank;
  final List<Rec> receipts, payments;
  MonthBook(this.year, this.month, this.openCash, this.openBank, this.receipts, this.payments);

  double _sum(List<Rec> l, String mode) => r2(l.where((t) => t.s('mode') == mode).fold(0.0, (a, t) => a + amountOf(t)));
  double get rCash => _sum(receipts, 'cash');
  double get rBank => _sum(receipts, 'bank');
  double get pCash => _sum(payments, 'cash');
  double get pBank => _sum(payments, 'bank');
  double get totalReceiptsCash => r2(openCash + rCash);
  double get totalReceiptsBank => r2(openBank + rBank);
  double get closeCash => r2(totalReceiptsCash - pCash); // Balance C/F
  double get closeBank => r2(totalReceiptsBank - pBank);
}

/// Records are always read from / written to the phone first. The sync engine copies them to the Google Sheet later.
class Store {
  static Db get _db => Db.instance;
  static AppState get _app => AppState.instance;

  static Future<List<Rec>> list(String type) => _db.list(_app.orgId, type);

  // ------------------------------------------------------------------ members
  static Future<List<Rec>> members() async {
    final r = await list(tMember);
    r.sort((a, b) => a.s('name').toLowerCase().compareTo(b.s('name').toLowerCase()));
    return r;
  }

  static Future<Rec?> baptismOf(String memberId) async {
    final r = await _db.get('bap-$memberId');
    return (r == null || r.deleted) ? null : r;
  }

  // ------------------------------------------------------------------ attendance
  /// One attendance sheet per service per day, so the same id is used by everyone who records it.
  static String attendanceId(String date, String service) =>
      'att-$date-${service.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';

  static Future<List<Rec>> attendance() async {
    final r = await list(tAttendance);
    r.sort((a, b) => b.s('date').compareTo(a.s('date')));
    return r;
  }

  // ------------------------------------------------------------------ events and announcements
  static Future<List<Rec>> events() async {
    final r = await list(tEvent);
    r.sort((a, b) => a.s('date').compareTo(b.s('date')));
    return r;
  }

  static Future<List<Rec>> announcements() async {
    final r = await list(tAnnouncement);
    r.sort((a, b) {
      final e = (b.data['urgent'] == true ? 1 : 0) - (a.data['urgent'] == true ? 1 : 0);
      return e != 0 ? e : b.s('date').compareTo(a.s('date'));
    });
    return r;
  }

  // ------------------------------------------------------------------ finance
  /// Transactions (voided ones included, flagged), oldest first; optionally one financial year only.
  static Future<List<Rec>> txns({int? fy}) async {
    var r = await list(tTxn);
    if (fy != null) r = r.where((t) => fyStartOf(parseDate(t.s('date')) ?? DateTime(2000)) == fy).toList();
    r.sort((a, b) {
      final c = a.s('date').compareTo(b.s('date'));
      return c != 0 ? c : a.updatedAt.compareTo(b.updatedAt);
    });
    return r;
  }

  static bool isVoid(Rec t) => t.data['void'] == true;

  static Future<({double cash, double bank})> opening(int fy) async {
    final o = await _db.get('open-${_app.orgId}-$fy');
    if (o == null || o.deleted) return (cash: 0.0, bank: 0.0);
    return (cash: ((o.data['cash'] ?? 0) as num).toDouble(), bank: ((o.data['bank'] ?? 0) as num).toDouble());
  }

  static Future<void> saveOpening(int fy, double cash, double bank) => save(tOpening,
      id: 'open-${_app.orgId}-$fy',
      data: {'fy': fy, 'cash': r2(cash), 'bank': r2(bank)},
      summary: 'Opening balance ${fyLabel(fy)}: cash ${money(cash)}, bank ${money(bank)}');

  static Future<MonthBook> monthBook(int fy, int year, int month, {List<Rec>? all}) async {
    final fyTx = (all ?? await txns(fy: fy)).where((t) => !isVoid(t)).toList();
    final op = await opening(fy);
    var cash = op.cash, bank = op.bank;
    final start = DateTime(year, month, 1), end = DateTime(year, month + 1, 1);
    final rec = <Rec>[], pay = <Rec>[];
    for (final t in fyTx) {
      final d = parseDate(t.s('date'));
      if (d == null) continue;
      if (d.isBefore(start)) {
        final amt = amountOf(t) * (t.s('kind') == 'receipt' ? 1 : -1);
        if (t.s('mode') == 'cash') {
          cash += amt;
        } else {
          bank += amt;
        }
      } else if (d.isBefore(end)) {
        (t.s('kind') == 'receipt' ? rec : pay).add(t);
      }
    }
    return MonthBook(year, month, r2(cash), r2(bank), rec, pay);
  }

  static List<String> heads(String kind, List<Rec> used) {
    final base = kind == 'receipt' ? defaultReceiptHeads : defaultPaymentHeads;
    final set = <String>{...base, for (final t in used) if (t.s('kind') == kind && t.s('head').isNotEmpty) t.s('head')};
    return set.toList()..sort();
  }

  // ------------------------------------------------------------------ writing
  /// Creates (id == null) or edits a record. Saved on the phone first and marked for upload to the sheet.
  static Future<Rec> save(String type, {String? id, required Map<String, dynamic> data, String? summary, bool audit = true}) async {
    final me = _app.mobile;
    final existing = id == null ? null : await _db.get(id);
    final Rec rec;
    if (existing != null) {
      existing.edit(by: me, newData: data, isDeleted: existing.deleted ? false : null);
      rec = existing;
    } else {
      rec = Rec(id: id ?? newId(), orgId: _app.orgId, type: type, data: data, updatedAt: nowIso(), by: me);
    }
    rec.dirty = !_app.isLocal;
    await _db.put(rec);
    if (audit && summary != null) await _audit(existing == null ? 'created' : 'edited', type, rec.id, summary);
    SyncEngine.instance.trigger();
    return rec;
  }

  static Future<void> remove(Rec r, String summary) async {
    r.edit(by: _app.mobile, isDeleted: true);
    r.dirty = !_app.isLocal;
    await _db.put(r);
    await _audit('deleted', r.type, r.id, summary);
    SyncEngine.instance.trigger();
  }

  /// Financial transactions are never deleted: they are voided with a reason and stay visible (struck through) for the audit.
  static Future<void> voidTxn(Rec t, String reason) => save(tTxn,
      id: t.id,
      data: {...t.data, 'void': true, 'voidReason': reason, 'voidedBy': _app.mobile, 'voidedAt': nowIso()},
      summary: 'Voided ${t.s('kind')} ${money(amountOf(t))} ${t.s('head')}: $reason');

  static Future<void> _audit(String action, String type, String targetId, String summary) async {
    final rec = Rec(
      id: newId(), orgId: _app.orgId, type: tAudit, updatedAt: nowIso(), by: _app.mobile,
      data: {'action': action, 'entity': type, 'targetId': targetId, 'summary': summary, 'by': _app.mobile, 'at': nowIso()},
    )..dirty = !_app.isLocal;
    await _db.put(rec);
  }

  static Future<void> audit(String action, String type, String targetId, String summary) => _audit(action, type, targetId, summary);

  static Future<List<Rec>> audits() async {
    final r = await list(tAudit);
    r.sort((a, b) => b.s('at').compareTo(a.s('at')));
    return r;
  }

  // ------------------------------------------------------------------ church settings (admin)
  static Future<void> saveSettings({String? name, String? logo, bool clearLogo = false}) async {
    final cur = <String, dynamic>{'name': name ?? _app.orgName, 'logo': clearLogo ? null : (logo ?? _app.logo)};
    await _app.applySettings(cur);
    await save(tSettings, id: 'settings-${_app.orgId}', data: cur, summary: 'Church settings changed');
  }
}
