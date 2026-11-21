/**
 * Freely CMS - spreadsheet API.  Paste this whole file into the Apps Script editor of YOUR Google Sheet
 * (Sheet > Extensions > Apps Script), then Deploy > New deployment > type "Web app":
 *     Execute as: Me          Who has access: Anyone
 * Google asks you ONCE to approve the permissions - that is the admin approval. Copy the Web app URL into the Freely CMS app.
 *
 * The spreadsheet is the organization's central copy of all data. Every phone keeps its own SQLite copy and syncs with this
 * script whenever the internet is on. Tabs (readable in Google Sheets, please edit data in the app, not here):
 *   Users, Devices, Members, Baptism, Attendance, Events, Announcements, Finance, Opening, AuditLog, Settings, Organization
 *
 * Security: phones identify themselves with a mobile number + a secret token that the admin approved. Only the hash of a token
 * is stored. Role-based access: a phone only receives (and may only write) the record types its user's roles allow, e.g. only the
 * treasurer sees Finance and only the pastor sees Baptism details.
 */

var TYPES = {
  member:       { tab: 'Members',       cols: ['name', 'phone', 'email', 'gender', 'dob', 'address', 'familyName', 'relation', 'status', 'emergencyContact', 'notes'] },
  baptism:      { tab: 'Baptism',       cols: ['memberId', 'memberName', 'baptised', 'baptismDate', 'salvationDate', 'church', 'notes'] },
  attendance:   { tab: 'Attendance',    cols: ['date', 'service', 'presentCount', 'presentNames', 'notes'] },
  event:        { tab: 'Events',        cols: ['title', 'kind', 'date', 'time', 'venue', 'description'] },
  announcement: { tab: 'Announcements', cols: ['title', 'body', 'date', 'urgent'] },
  txn:          { tab: 'Finance',       cols: ['date', 'kind', 'head', 'mode', 'amount', 'narration', 'ref', 'void', 'voidReason'] },
  opening:      { tab: 'Opening',       cols: ['fy', 'cash', 'bank'] },
  audit:        { tab: 'AuditLog',      cols: ['action', 'entity', 'targetId', 'summary', 'by', 'at'] },
  settings:     { tab: 'Settings',      cols: ['name'] }
};
var META = ['id', 'rev', 'version', 'updatedAt', 'by', 'deleted', 'hash', 'lineage'];   // then the readable columns, then json
var LWW = { audit: 1, settings: 1, opening: 1 };   // types where the newest write simply wins (no conflict dialog)

// Role-based access control (mirror of lib/core/perms.dart). The admin may do everything. null = every approved user.
var PASTORAL = ['pastor'], OFFICE = ['pastor', 'secretary'];
var CARE = ['pastor', 'secretary', 'deacon', 'ss_coordinator', 'ss_teacher', 'ministry_leader'];
var TAKERS = ['pastor', 'secretary', 'ss_coordinator', 'ss_teacher', 'ministry_leader'];
var MONEY = ['treasurer'];
var ALL_ROLES = ['pastor', 'secretary', 'treasurer', 'deacon', 'ss_coordinator', 'ss_teacher', 'ministry_leader', 'parent', 'member'];
var READ = { member: CARE, baptism: PASTORAL, attendance: CARE, event: null, announcement: null, txn: MONEY, opening: MONEY, settings: null, audit: null };
var WRITE = { member: OFFICE, baptism: PASTORAL, attendance: TAKERS, event: OFFICE, announcement: OFFICE, txn: MONEY, opening: MONEY, settings: [], audit: null };

function allowed_(who, table, type) {
  if (who.role === 'admin') return true;
  var need = table[type];
  if (need === null || need === undefined) return need === null;
  for (var i = 0; i < who.roles.length; i++) if (need.indexOf(who.roles[i]) >= 0) return true;
  return false;
}
var USER_HEADER = ['mobile', 'name', 'role', 'status', 'lastSeen', 'createdAt', 'roles'];
var DEVICE_HEADER = ['deviceId', 'mobile', 'name', 'status', 'tokenHash', 'issue', 'requestedAt', 'lastSeen'];
var PAGE = 1500;

// ------------------------------------------------------------------ entry points
function doGet() {
  return out_({ ok: true, app: 'Freely CMS', initialised: !!props_().getProperty('ORG_ID') });
}

function doPost(e) {
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(30000);
    var req = JSON.parse(e.postData.contents);
    var fn = ACTIONS[req.action];
    if (!fn) throw err_('Unknown action', 'BAD');
    return out_(fn(req));
  } catch (ex) {
    return out_({ ok: false, error: String(ex.message || ex), code: ex.code || 'ERR', status: ex.status || '' });
  } finally {
    try { lock.releaseLock(); } catch (x) {}
  }
}

var ACTIONS = {
  init: init_, join: join_, status: status_, recover: recover_,
  sync: sync_, users: users_, approve: approve_, reject: reject_, setUserStatus: setUserStatus_, setRoles: setRoles_, forceLogout: forceLogout_
};

// ------------------------------------------------------------------ small helpers
function out_(o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); }
function err_(msg, code, status) { var e = new Error(msg); e.code = code || 'ERR'; e.status = status || ''; return e; }
function props_() { return PropertiesService.getScriptProperties(); }
function ss_() { return SpreadsheetApp.getActiveSpreadsheet(); }
function nowIso_() { return new Date().toISOString(); }
function token_() { return Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, ''); }

function sha_(s) {
  var b = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, s, Utilities.Charset.UTF_8);
  return b.map(function (x) { var h = (x < 0 ? x + 256 : x).toString(16); return h.length < 2 ? '0' + h : h; }).join('');
}

function mobile_(s) {
  var d = String(s || '').replace(/\D/g, '');
  if (d.length === 12 && d.indexOf('91') === 0) d = d.substring(2);
  if (d.length === 11 && d.charAt(0) === '0') d = d.substring(1);
  return d;
}

function rolesOf_(cell) {
  var l = String(cell || '').split(',').map(function (x) { return x.trim(); }).filter(function (x) { return ALL_ROLES.indexOf(x) >= 0; });
  return l.length ? l : ['member'];
}

function header_(type) { return META.concat(TYPES[type].cols).concat(['json']); }

/** Creates the tab when missing. Whole tab is plain text so that nothing typed by a user is ever treated as a formula. */
function sheet_(name, header) {
  var ss = ss_(), sh = ss.getSheetByName(name);
  if (!sh) {
    sh = ss.insertSheet(name);
    sh.getRange(1, 1, sh.getMaxRows(), Math.max(header.length, 10)).setNumberFormat('@');
    sh.getRange(1, 1, 1, header.length).setValues([header]).setFontWeight('bold');
    sh.setFrozenRows(1);
  }
  return sh;
}

function write_(sh, row, values) {   // values: array of rows, written starting at 'row'
  var r = sh.getRange(row, 1, values.length, values[0].length);
  r.setNumberFormat('@');
  r.setValues(values);
}

function table_(sh, width) {
  var last = sh.getLastRow();
  return last > 1 ? sh.getRange(2, 1, last - 1, width).getValues() : [];
}

function cell_(v) {
  if (v === null || v === undefined) return '';
  if (Object.prototype.toString.call(v) === '[object Array]') return v.join(', ');
  return String(v);
}

function parse_(s, fallback) { try { return JSON.parse(s); } catch (e) { return fallback; } }

// ------------------------------------------------------------------ users and devices
function userRows_() { var sh = sheet_('Users', USER_HEADER); return { sh: sh, rows: table_(sh, USER_HEADER.length) }; }
function deviceRows_() { var sh = sheet_('Devices', DEVICE_HEADER); return { sh: sh, rows: table_(sh, DEVICE_HEADER.length) }; }

function indexOf_(rows, col, val) {
  for (var i = 0; i < rows.length; i++) if (String(rows[i][col]) === String(val)) return i;
  return -1;
}

function setCell_(sh, rowIdx, col, value) {   // rowIdx = index in rows (0 based) -> sheet row rowIdx + 2
  var r = sh.getRange(rowIdx + 2, col + 1);
  r.setNumberFormat('@');
  r.setValue(value);
}

/** Who is calling? Throws a DENIED error (with the reason in .status) when the phone is not allowed. */
function auth_(req, needAdmin) {
  var p = props_().getProperties();
  if (!p.ORG_ID) throw err_('The organization is not set up yet', 'NOSETUP');
  var mobile = mobile_(req.mobile), token = String(req.token || '');
  if (!mobile || !token) throw err_('Not authorised', 'DENIED', 'unknown');
  var h = sha_(token);
  if (h === p.ADMIN_HASH && mobile === p.ADMIN_MOBILE) return { role: 'admin', roles: ALL_ROLES, mobile: mobile, deviceId: String(req.deviceId || '') };
  if (needAdmin) throw err_('Admin only', 'DENIED', 'user');
  var devs = deviceRows_(), di = indexOf_(devs.rows, 0, req.deviceId);
  if (di < 0 || String(devs.rows[di][1]) !== mobile) throw err_('Not authorised', 'DENIED', 'unknown');
  var dstatus = String(devs.rows[di][3]);
  if (dstatus !== 'approved') throw err_('This phone is not approved', 'DENIED', dstatus);   // pending / rejected / disabled / loggedout
  if (devs.rows[di][4] !== h) throw err_('Not authorised', 'DENIED', 'unknown');
  var us = userRows_(), ui = indexOf_(us.rows, 0, mobile);
  if (ui < 0 || us.rows[ui][3] !== 'approved') throw err_('Your access was removed', 'DENIED', ui < 0 ? 'unknown' : String(us.rows[ui][3]));
  return { role: String(us.rows[ui][2]), roles: rolesOf_(us.rows[ui][6]), mobile: mobile, deviceId: String(req.deviceId) };
}

function touch_(who) {
  var now = nowIso_();
  var us = userRows_(), ui = indexOf_(us.rows, 0, who.mobile);
  if (ui >= 0) setCell_(us.sh, ui, 4, now);
  if (who.deviceId) {
    var ds = deviceRows_(), di = indexOf_(ds.rows, 0, who.deviceId);
    if (di >= 0) setCell_(ds.sh, di, 7, now);
  }
}

// ------------------------------------------------------------------ setup / joining
function init_(req) {
  var p = props_();
  if (p.getProperty('ORG_ID')) throw err_('This spreadsheet already has an organization. If you are the admin on a new phone, use "New phone? Enter admin key".', 'ALREADY');
  var name = String(req.orgName || '').trim(), mob = mobile_(req.mobile);
  if (name.length < 2) throw err_('Church name is required', 'BAD');
  if (mob.length !== 10) throw err_('A 10-digit mobile number is required', 'BAD');
  var code = '';
  var chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  for (var i = 0; i < 8; i++) code += chars.charAt(Math.floor(Math.random() * chars.length));
  var token = token_();
  p.setProperties({
    ORG_ID: Utilities.getUuid(), ORG_NAME: name, ORG_CODE: code, ADMIN_MOBILE: mob, ADMIN_HASH: sha_(token), REV: '0'
  });
  sheet_('Users', USER_HEADER);
  sheet_('Devices', DEVICE_HEADER);
  for (var t in TYPES) sheet_(TYPES[t].tab, header_(t));
  var org = sheet_('Organization', ['key', 'value']);
  write_(org, 2, [['Church name', name], ['Church code', code], ['Organization id', p.getProperty('ORG_ID')], ['Admin mobile', mob], ['Created', nowIso_()]]);
  var us = userRows_();
  write_(us.sh, 2, [[mob, String(req.name || '').trim(), 'admin', 'approved', nowIso_(), nowIso_(), ALL_ROLES.join(',')]]);
  var s1 = ss_().getSheetByName('Sheet1');
  if (s1 && ss_().getSheets().length > 1) ss_().deleteSheet(s1);
  return { ok: true, orgId: p.getProperty('ORG_ID'), orgName: name, orgCode: code, adminToken: token };
}

function checkCode_(req) {
  var p = props_().getProperties();
  if (!p.ORG_ID) throw err_('The organization is not set up yet', 'NOSETUP');
  if (String(req.orgCode || '').trim().toUpperCase() !== p.ORG_CODE) throw err_('Invalid organization code', 'BAD');
  return p;
}

/** A user asks to join with this phone. Always needs the admin's approval (also after a logout). */
function join_(req) {
  var p = checkCode_(req);
  var mob = mobile_(req.mobile), dev = String(req.deviceId || '');
  if (mob.length !== 10 || !dev) throw err_('A 10-digit mobile number is required', 'BAD');
  var us = userRows_(), ui = indexOf_(us.rows, 0, mob);
  if (mob === p.ADMIN_MOBILE) throw err_('This mobile number belongs to the admin. Choose "I am the admin" and use your admin key.', 'BAD');
  if (ui >= 0 && us.rows[ui][3] === 'disabled') throw err_('Your access was removed by the admin', 'DENIED', 'disabled');
  var name = String(req.name || '').trim();
  if (ui < 0) write_(us.sh, us.rows.length + 2, [[mob, name, 'user', 'pending', '', nowIso_(), 'member']]);
  else if (name) setCell_(us.sh, ui, 1, name);
  var ds = deviceRows_(), di = indexOf_(ds.rows, 0, dev);
  var row = [dev, mob, name, 'pending', '', '', nowIso_(), ''];
  if (di < 0) write_(ds.sh, ds.rows.length + 2, [row]); else write_(ds.sh, di + 2, [row]);
  return { ok: true, status: 'pending', orgName: p.ORG_NAME, orgId: p.ORG_ID };
}

/** The waiting phone asks whether it was approved. The secret token is handed over exactly once. */
function status_(req) {
  var p = checkCode_(req);
  var ds = deviceRows_(), di = indexOf_(ds.rows, 0, req.deviceId);
  if (di < 0 || String(ds.rows[di][1]) !== mobile_(req.mobile)) return { ok: true, status: 'unknown', orgName: p.ORG_NAME };
  var st = String(ds.rows[di][3]);
  if (st === 'approved' && ds.rows[di][5] === 'yes') {
    var token = token_();
    setCell_(ds.sh, di, 4, sha_(token));
    setCell_(ds.sh, di, 5, '');
    return { ok: true, status: 'approved', token: token, role: 'user', orgName: p.ORG_NAME, orgId: p.ORG_ID };
  }
  return { ok: true, status: st, orgName: p.ORG_NAME };
}

/** The admin on a new phone proves ownership with the admin key. */
function recover_(req) {
  var who = auth_(req, true);
  var p = props_().getProperties();
  touch_(who);
  return { ok: true, orgId: p.ORG_ID, orgName: p.ORG_NAME, orgCode: p.ORG_CODE, role: 'admin' };
}

// ------------------------------------------------------------------ admin actions
function users_(req) {
  auth_(req, true);
  var us = userRows_(), ds = deviceRows_(), p = props_().getProperties();
  return {
    ok: true, orgCode: p.ORG_CODE,
    users: us.rows.map(function (r) { return { mobile: String(r[0]), name: String(r[1]), role: String(r[2]), status: String(r[3]), lastSeen: String(r[4]), createdAt: String(r[5]), roles: String(r[2]) === 'admin' ? ALL_ROLES : rolesOf_(r[6]) }; }),
    devices: ds.rows.map(function (r) { return { deviceId: String(r[0]), mobile: String(r[1]), name: String(r[2]), status: String(r[3]), requestedAt: String(r[6]), lastSeen: String(r[7]) }; })
  };
}

function approve_(req) {
  auth_(req, true);
  var ds = deviceRows_(), di = indexOf_(ds.rows, 0, req.deviceId);
  if (di < 0) throw err_('Request not found', 'BAD');
  setCell_(ds.sh, di, 3, 'approved');
  setCell_(ds.sh, di, 5, 'yes');   // the phone collects its token on its next status check
  var us = userRows_(), ui = indexOf_(us.rows, 0, ds.rows[di][1]);
  if (ui >= 0) setCell_(us.sh, ui, 3, 'approved');
  return { ok: true };
}

function reject_(req) {
  auth_(req, true);
  var ds = deviceRows_(), di = indexOf_(ds.rows, 0, req.deviceId);
  if (di < 0) throw err_('Request not found', 'BAD');
  setCell_(ds.sh, di, 3, 'rejected');
  var us = userRows_(), ui = indexOf_(us.rows, 0, ds.rows[di][1]);
  if (ui >= 0 && us.rows[ui][3] === 'pending') setCell_(us.sh, ui, 3, 'rejected');
  return { ok: true };
}

function setUserStatus_(req) {
  auth_(req, true);
  var st = String(req.status);
  if (st !== 'approved' && st !== 'disabled') throw err_('Invalid status', 'BAD');
  var mob = mobile_(req.targetMobile);
  var us = userRows_(), ui = indexOf_(us.rows, 0, mob);
  if (ui < 0 || us.rows[ui][2] === 'admin') throw err_('User not found', 'BAD');
  setCell_(us.sh, ui, 3, st);
  if (st === 'disabled') {
    var ds = deviceRows_();
    for (var i = 0; i < ds.rows.length; i++) if (String(ds.rows[i][1]) === mob) setCell_(ds.sh, i, 3, 'disabled');
  }
  return { ok: true };
}

/** The admin gives a person one or more church roles (pastor, treasurer, ...). Takes effect at that person's next sync. */
function setRoles_(req) {
  auth_(req, true);
  var mob = mobile_(req.targetMobile), roles = rolesOf_((req.roles || []).join(','));
  var us = userRows_(), ui = indexOf_(us.rows, 0, mob);
  if (ui < 0 || us.rows[ui][2] === 'admin') throw err_('User not found', 'BAD');
  setCell_(us.sh, ui, 6, roles.join(','));
  return { ok: true, roles: roles };
}

/** Every user phone is logged out: their tokens stop working and they must join and be approved again. */
function forceLogout_(req) {
  auth_(req, true);
  var ds = deviceRows_();
  for (var i = 0; i < ds.rows.length; i++) {
    if (ds.rows[i][3] === 'approved') { setCell_(ds.sh, i, 3, 'loggedout'); setCell_(ds.sh, i, 4, ''); }
  }
  return { ok: true };
}

// ------------------------------------------------------------------ data sync
function loadTab_(type) {
  var width = header_(type).length;
  var sh = sheet_(TYPES[type].tab, header_(type));
  var vals = table_(sh, width);
  var index = {};
  for (var i = 0; i < vals.length; i++) index[String(vals[i][0])] = i;
  return { type: type, sh: sh, width: width, vals: vals, index: index, appended: [] };
}

function wireOf_(type, row) {
  return {
    id: String(row[0]), type: type, rev: Number(row[1]) || 0, version: Number(row[2]) || 1, updatedAt: String(row[3]), by: String(row[4]),
    deleted: String(row[5]) === 'true', hash: String(row[6]), lineage: parse_(row[7], []), data: parse_(row[row.length - 1], {})
  };
}

function rowOf_(type, w, rev) {
  var cols = TYPES[type].cols;
  var row = [w.id, String(rev), String(w.version), String(w.updatedAt), String(w.by || ''), w.deleted ? 'true' : 'false', w.hash, JSON.stringify(w.lineage || [])];
  for (var i = 0; i < cols.length; i++) row.push(cell_(w.data[cols[i]]));
  row.push(JSON.stringify(w.data));
  return row;
}

function has_(list, v) { return list && list.indexOf(v) >= 0; }

function sync_(req) {
  var who = auth_(req, false);
  var admin = who.role === 'admin';
  var p = props_();
  var rev = Number(p.getProperty('REV')) || 0;
  var since = Number(req.since) || 0;
  var tabs = {};
  function tab(t) { return tabs[t] || (tabs[t] = loadTab_(t)); }

  // ---- 1. changes sent by the phone
  var accepted = [], conflicts = [], changes = req.changes || [];
  function write(t, c, existingIdx) {
    rev += 1;
    var row = rowOf_(t.type, c, rev);
    if (existingIdx === undefined) {
      t.index[c.id] = t.vals.length;
      t.vals.push(row);
      t.appended.push(row);
    } else {
      t.vals[existingIdx] = row;
      write_(t.sh, existingIdx + 2, [row]);
    }
    if (t.type === 'settings' && c.data && c.data.name) {
      p.setProperty('ORG_NAME', String(c.data.name));
      var org = ss_().getSheetByName('Organization');
      if (org) { var r = org.getRange(2, 2); r.setNumberFormat('@'); r.setValue(String(c.data.name)); }
    }
  }
  for (var k = 0; k < changes.length; k++) {
    var c = changes[k];
    if (!c || !TYPES[c.type] || !c.id || !c.hash || !c.data || typeof c.data !== 'object') continue;
    var t = tab(c.type);
    var ex = t.index[String(c.id)];
    var cur = ex === undefined ? null : wireOf_(c.type, t.vals[ex]);
    if (!allowed_(who, WRITE, c.type)) continue;              // this user's roles may not write this kind of record
    if (c.type === 'audit' && !admin && c.data.by !== who.mobile) continue;
    if (c.type === 'txn' && cur && cur.data.void === true && c.data.void !== true) continue;   // a voided transaction stays voided

    if (!cur) {
      write(t, c);
      accepted.push({ id: c.id, hash: c.hash });
    } else if (cur.hash === c.hash) {
      accepted.push({ id: c.id, hash: c.hash });
    } else if (LWW[c.type]) {
      if (Number(c.version) > cur.version || (Number(c.version) === cur.version && String(c.updatedAt) > cur.updatedAt)) write(t, c, ex);
      accepted.push({ id: c.id, hash: c.hash });
    } else if (has_(c.lineage, cur.hash)) {
      write(t, c, ex);                                        // the phone's copy was made from the sheet's copy: take it
      accepted.push({ id: c.id, hash: c.hash });
    } else if (has_(cur.lineage, c.hash)) {
      accepted.push({ id: c.id, hash: c.hash });              // the phone's copy is older than the sheet's: it will get the newer one below
    } else {
      conflicts.push({ id: c.id, server: cur });              // both changed it: nothing is overwritten, the phone asks the user
    }
  }
  for (var tn in tabs) {                                      // new rows in one write per tab
    var tb = tabs[tn];
    if (tb.appended.length) {
      var first = tb.vals.length - tb.appended.length + 2;
      write_(tb.sh, first, tb.appended);
      tb.appended = [];
    }
  }
  p.setProperty('REV', String(rev));
  touch_(who);

  // ---- 2. what changed since the phone's last sync
  var send = [];
  for (var type in TYPES) {
    if (!allowed_(who, READ, type)) continue;                  // never leaves the sheet for phones without the role
    var tt = tab(type);
    for (var r = 0; r < tt.vals.length; r++) {
      if ((Number(tt.vals[r][1]) || 0) <= since) continue;
      var w = wireOf_(type, tt.vals[r]);
      if (type === 'audit' && !admin && w.data.by !== who.mobile) continue;
      send.push(w);
    }
  }
  send.sort(function (x, y) { return x.rev - y.rev; });
  var more = false, newRev = rev;
  if (send.length > PAGE) { send = send.slice(0, PAGE); more = true; newRev = send[send.length - 1].rev; }
  return {
    ok: true, rev: newRev, more: more, records: send, accepted: accepted, conflicts: conflicts,
    orgName: p.getProperty('ORG_NAME'), role: who.role, roles: who.roles
  };
}
