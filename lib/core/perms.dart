import 'app_state.dart';

/// Role-based access control. A person can hold several roles; the admin (the church's primary administrator) holds everything.
/// The same matrix is enforced by the spreadsheet script (google-apps-script/Code.gs), so a phone never receives records its
/// roles may not read, and the sheet refuses writes the roles may not make.
const roleLabels = <String, String>{
  'pastor': 'Pastor',
  'secretary': 'Church Secretary',
  'treasurer': 'Treasurer',
  'deacon': 'Deacon',
  'ss_coordinator': 'Sunday School Coordinator',
  'ss_teacher': 'Sunday School Teacher',
  'ministry_leader': 'Ministry Leader',
  'parent': 'Parent',
  'member': 'Church Member',
};

const _pastoral = {'pastor'};
const _office = {'pastor', 'secretary'};
const _careTeam = {'pastor', 'secretary', 'deacon', 'ss_coordinator', 'ss_teacher', 'ministry_leader'};
const _takers = {'pastor', 'secretary', 'ss_coordinator', 'ss_teacher', 'ministry_leader'};
const _money = {'treasurer'};

/// Record type -> roles that may read / write it (the admin is always allowed). `null` = everybody.
const _read = <String, Set<String>?>{
  'member': _careTeam, 'baptism': _pastoral, 'attendance': _careTeam, 'event': null, 'announcement': null,
  'txn': _money, 'opening': _money, 'settings': null, 'audit': null,
};
const _write = <String, Set<String>?>{
  'member': _office, 'baptism': _pastoral, 'attendance': _takers, 'event': _office, 'announcement': _office,
  'txn': _money, 'opening': _money, 'settings': <String>{}, 'audit': null,
};

class Perms {
  static AppState get _a => AppState.instance;

  static bool _has(Set<String>? allowed) {
    if (_a.isAdmin) return true;
    if (allowed == null) return true;
    return _a.roles.any(allowed.contains);
  }

  static bool canRead(String type) => _has(_read[type]);
  static bool canWrite(String type) => _has(_write[type]);

  static bool get members => canRead('member');
  static bool get editMembers => canWrite('member');
  static bool get baptism => canRead('baptism');
  static bool get attendance => canRead('attendance');
  static bool get takeAttendance => canWrite('attendance');
  static bool get editEvents => canWrite('event');
  static bool get editAnnouncements => canWrite('announcement');
  static bool get finance => canRead('txn');
  static bool get reports => members || finance;
  static bool get manageUsers => _a.isAdmin;

  static String rolesText(List<String> r) => r.isEmpty ? 'Church Member' : r.map((x) => roleLabels[x] ?? x).join(', ');
}
