// Runs Code.gs against an in-memory mock of Google's services.   node google-apps-script/test.js
const fs = require('fs');
const vm = require('vm');
const crypto = require('crypto');
const path = require('path');

class Range {
  constructor(sh, r, c, nr, nc) { Object.assign(this, { sh, r, c, nr, nc }); }
  getValues() { const o = []; for (let i = 0; i < this.nr; i++) { const row = []; for (let j = 0; j < this.nc; j++) row.push(this.sh.get(this.r + i, this.c + j)); o.push(row); } return o; }
  setValues(v) { for (let i = 0; i < v.length; i++) for (let j = 0; j < v[i].length; j++) this.sh.set(this.r + i, this.c + j, v[i][j]); return this; }
  setValue(v) { this.sh.set(this.r, this.c, v); return this; }
  setNumberFormat() { return this; }
  setFontWeight() { return this; }
}
class Sheet {
  constructor(name) { this.name = name; this.cells = {}; }
  get(r, c) { const v = this.cells[r + ',' + c]; return v === undefined ? '' : v; }
  set(r, c, v) { this.cells[r + ',' + c] = String(v); }
  getRange(r, c, nr = 1, nc = 1) { return new Range(this, r, c, nr, nc); }
  getLastRow() { let m = 0; for (const k of Object.keys(this.cells)) if (this.cells[k] !== '') m = Math.max(m, +k.split(',')[0]); return m; }
  getMaxRows() { return 1000; }
  setFrozenRows() {}
}
const sheets = [new Sheet('Sheet1')];
const store = {};
let uuid = 0;
const ctx = {
  console, JSON, Math, Date, String, Number, Object, Array, Error,
  SpreadsheetApp: { getActiveSpreadsheet: () => ({
    getSheetByName: n => sheets.find(s => s.name === n) || null,
    insertSheet: n => { const s = new Sheet(n); sheets.push(s); return s; },
    getSheets: () => sheets,
    deleteSheet: s => sheets.splice(sheets.indexOf(s), 1),
  }) },
  PropertiesService: { getScriptProperties: () => ({
    getProperty: k => (k in store ? store[k] : null),
    getProperties: () => ({ ...store }),
    setProperty: (k, v) => { store[k] = String(v); },
    setProperties: o => { for (const k in o) store[k] = String(o[k]); },
  }) },
  LockService: { getScriptLock: () => ({ waitLock() {}, releaseLock() {} }) },
  Utilities: {
    getUuid: () => crypto.randomUUID(),
    computeDigest: (_a, s) => Array.from(crypto.createHash('sha256').update(s).digest()).map(x => (x > 127 ? x - 256 : x)),
    DigestAlgorithm: { SHA_256: 1 }, Charset: { UTF_8: 1 },
  },
  ContentService: { createTextOutput: s => ({ text: s, setMimeType() { return this; } }), MimeType: { JSON: 1 } },
};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, 'Code.gs'), 'utf8'), ctx);

const call = req => JSON.parse(ctx.doPost({ postData: { contents: JSON.stringify(req) } }).text);
let failed = 0;
const ok = (cond, msg) => { if (cond) console.log('  ok   ' + msg); else { failed++; console.log('  FAIL ' + msg); } };

let n = 0;
const rec = (type, id, data, o = {}) => ({ id, type, data, version: 1, updatedAt: new Date(Date.now() + ++n).toISOString(), by: 'x', deleted: false, hash: crypto.randomBytes(6).toString('hex'), lineage: [], ...o });

console.log('setup');
let r = call({ action: 'init', orgName: 'Grace Assembly', mobile: '9876543210', name: 'Admin Pastor' });
ok(r.ok && r.orgCode.length === 8 && r.adminToken, 'admin creates the organization');
const A = { mobile: '9876543210', deviceId: 'adm', token: r.adminToken };
const CODE = r.orgCode;
ok(!call({ action: 'init', orgName: 'Other', mobile: '9876543210' }).ok, 'second init is refused');
ok(sheets.map(s => s.name).includes('Finance') && !sheets.some(s => s.name === 'Sheet1'), 'tabs created, default Sheet1 removed');

console.log('joining');
r = call({ action: 'join', orgCode: 'WRONG', mobile: '9000000001', name: 'Asha', deviceId: 'd1' });
ok(!r.ok, 'wrong org code rejected');
r = call({ action: 'join', orgCode: CODE, mobile: '+91 90000 00001', name: 'Asha', deviceId: 'd1' });
ok(r.ok && r.status === 'pending', 'user requests access (mobile normalised)');
ok(call({ action: 'status', orgCode: CODE, mobile: '9000000001', deviceId: 'd1' }).status === 'pending', 'still pending');
ok(call({ action: 'sync', mobile: '9000000001', deviceId: 'd1', token: 'guess', since: 0 }).code === 'DENIED', 'pending phone cannot sync');
r = call({ action: 'users', ...A });
ok(r.ok && r.devices.length === 1 && r.users.length === 2, 'admin sees the pending request');
ok(call({ action: 'approve', mobile: '9000000001', deviceId: 'd1', token: 'x', targetDevice: 'd1' }).code === 'DENIED', 'a user cannot approve');
ok(call({ action: 'approve', ...A, deviceId: 'd1' }).ok, 'admin approves');
r = call({ action: 'status', orgCode: CODE, mobile: '9000000001', deviceId: 'd1' });
ok(r.status === 'approved' && r.token, 'user phone receives its token');
const U = { mobile: '9000000001', deviceId: 'd1', token: r.token };
ok(!call({ action: 'status', orgCode: CODE, mobile: '9000000001', deviceId: 'd1' }).token, 'token is handed over only once');

console.log('roles and visibility');
const mem = rec('member', 'm1', { name: 'John', phone: '111', status: 'Active' });
const bap = rec('baptism', 'bap-m1', { memberId: 'm1', baptised: true, baptismDate: '2015-05-05' });
const ev = rec('event', 'e1', { title: 'Convention', date: '2026-12-01' });
const tx = rec('txn', 't1', { date: '2026-11-01', kind: 'receipt', head: 'Sunday Offering A/C', mode: 'cash', amount: 1500 });
const st = rec('settings', 'settings-1', { name: 'Grace Assembly HQ' });
r = call({ action: 'sync', ...A, since: 0, changes: [mem, bap, ev, tx, st] });
ok(r.ok && r.accepted.length === 5, 'admin pushes member, baptism, event, finance, settings');
ok(sheets.find(s => s.name === 'Members').get(2, 9) === 'John' && sheets.find(s => s.name === 'Finance').get(2, 13) === '1500', 'rows are readable in their tabs');
ok(sheets.find(s => s.name === 'Organization').get(2, 2) === 'Grace Assembly HQ', 'church name updated from settings');
r = call({ action: 'sync', ...U, since: 0, changes: [] });
const types = r.records.map(x => x.type);
ok(r.roles.join() === 'member', 'a new user has the Church Member role');
ok(types.includes('event') && types.includes('settings') && !types.includes('member') && !types.includes('baptism') && !types.includes('txn'), 'plain member only receives events and settings');
ok(call({ action: 'sync', ...U, since: 0, changes: [rec('event', 'e2', { title: 'Nope' })] }).accepted.length === 0, 'plain member cannot create events');
ok(call({ action: 'setRoles', ...A, targetMobile: '9000000001', roles: ['treasurer', 'bogus'] }).roles.join() === 'treasurer', 'admin gives the treasurer role (unknown roles dropped)');
ok(!call({ action: 'setRoles', ...U, targetMobile: '9000000001', roles: ['pastor'] }).ok, 'a user cannot give roles');
r = call({ action: 'sync', ...U, since: 0, changes: [] });
const t2 = r.records.map(x => x.type);
ok(r.roles.join() === 'treasurer' && t2.includes('txn') && !t2.includes('member') && !t2.includes('baptism'), 'treasurer sees finance but not members or baptism details');
const tx2 = rec('txn', 't2', { date: '2026-11-02', kind: 'payment', head: 'Electricity and water', mode: 'bank', amount: 800 });
ok(call({ action: 'sync', ...U, since: 0, changes: [tx2, rec('member', 'm9', { name: 'X' })] }).accepted.length === 1, 'treasurer can add a transaction but not a member');

console.log('multiple roles');
call({ action: 'setRoles', ...A, targetMobile: '9000000001', roles: ['treasurer', 'secretary'] });
r = call({ action: 'sync', ...U, since: 0, changes: [] });
const t3 = r.records.map(x => x.type);
ok(t3.includes('txn') && t3.includes('member') && !t3.includes('baptism'), 'treasurer + secretary: finance and members, still no baptism');
call({ action: 'setRoles', ...A, targetMobile: '9000000001', roles: ['pastor'] });
r = call({ action: 'sync', ...U, since: 0, changes: [] });
ok(r.records.some(x => x.type === 'baptism') && !r.records.some(x => x.type === 'txn'), 'pastor sees baptism details but not finance');

console.log('finance rules');
const voided = rec('txn', 't1', { ...tx.data, void: true, voidReason: 'wrong entry' }, { version: 2, lineage: [tx.hash] });
call({ action: 'setRoles', ...A, targetMobile: '9000000001', roles: ['treasurer'] });
ok(call({ action: 'sync', ...U, since: 0, changes: [voided] }).accepted.length === 1, 'treasurer voids a transaction');
const revive = rec('txn', 't1', { ...tx.data }, { version: 3, lineage: [tx.hash, voided.hash] });
call({ action: 'sync', ...U, since: 0, changes: [revive] });
r = call({ action: 'sync', ...A, since: 0, changes: [] });
ok(r.records.find(x => x.id === 't1').data.void === true, 'a voided transaction cannot be silently revived');

console.log('conflicts');
const base = r.records.find(x => x.id === 'm1');
const byA = rec('member', 'm1', { ...base.data, phone: '222' }, { version: base.version + 1, lineage: [...base.lineage, base.hash] });
const byB = rec('member', 'm1', { ...base.data, phone: '333' }, { version: base.version + 1, lineage: [...base.lineage, base.hash] });
ok(call({ action: 'sync', ...A, since: 0, changes: [byA] }).accepted.length === 1, 'first edit accepted');
call({ action: 'setRoles', ...A, targetMobile: '9000000001', roles: ['secretary'] });
r = call({ action: 'sync', ...U, since: 0, changes: [byB] });
ok(r.conflicts.length === 1 && r.conflicts[0].server.data.phone === '222', 'second edit from the same base is a conflict; nothing overwritten');
const merged = rec('member', 'm1', { ...base.data, phone: '222' }, { version: byA.version + 1, lineage: [...byB.lineage, byB.hash, byA.hash] });
ok(call({ action: 'sync', ...U, since: 0, changes: [merged] }).accepted.length === 1, 'resolved version (descends from both) accepted');

console.log('access control');
ok(call({ action: 'sync', ...U, since: 0, changes: [rec('settings', 'settings-1', { name: 'Hacked' })] }).accepted.length === 0, 'user cannot change church settings');
ok(call({ action: 'setUserStatus', ...A, targetMobile: '9000000001', status: 'disabled' }).ok, 'admin disables the user');
r = call({ action: 'sync', ...U, since: 0, changes: [] });
ok(r.code === 'DENIED' && r.status === 'disabled', 'disabled user is denied with the reason');
ok(!call({ action: 'join', orgCode: CODE, mobile: '9000000001', name: 'Asha', deviceId: 'd9' }).ok, 'disabled user cannot rejoin');
call({ action: 'setUserStatus', ...A, targetMobile: '9000000001', status: 'approved' });
ok(call({ action: 'join', orgCode: CODE, mobile: '9000000001', name: 'Asha', deviceId: 'd9' }).status === 'pending', 're-enabled user must be approved again');
call({ action: 'approve', ...A, deviceId: 'd9' });
const U2 = { mobile: '9000000001', deviceId: 'd9', token: call({ action: 'status', orgCode: CODE, mobile: '9000000001', deviceId: 'd9' }).token };
ok(call({ action: 'sync', ...U2, since: 0, changes: [] }).ok, 'approved again, sync works');
call({ action: 'forceLogout', ...A });
ok(call({ action: 'sync', ...U2, since: 0, changes: [] }).status === 'loggedout', 'force logout cuts every user phone');
ok(call({ action: 'recover', ...A, deviceId: 'new-admin-phone' }).orgCode === CODE, 'admin key recovers the church on a new phone');
ok(call({ action: 'recover', ...A, token: 'bad' }).code === 'DENIED', 'wrong admin key is refused');

console.log(failed ? `\n${failed} FAILED` : '\nall passed');
process.exit(failed ? 1 : 0);
