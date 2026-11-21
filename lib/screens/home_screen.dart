import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/users.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'announcements_screen.dart';
import 'attendance_screen.dart';
import 'auth_screens.dart';
import 'backup_screen.dart';
import 'events_screen.dart';
import 'bulk_upload_screen.dart';
import 'finance_screen.dart';
import 'info_screens.dart';
import 'members_screen.dart';
import 'reports_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';
import 'users_screen.dart';

void go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

String greeting() {
  final h = DateTime.now().hour;
  return h < 12 ? 'Good Morning' : (h < 17 ? 'Good Afternoon' : 'Good Evening');
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _quickAdd(BuildContext context) {
    final items = <(IconData, String, Color, Widget)>[
      if (Perms.editMembers) (Icons.person_add_alt_1, 'Add member', accentViolet, const MemberEditScreen()),
      if (Perms.takeAttendance) (Icons.fact_check_outlined, 'Take attendance', accentGreen, const AttendanceTakeScreen()),
      if (Perms.editEvents) (Icons.event_outlined, 'Add event', brandBlue, const EventEditScreen()),
      if (Perms.editAnnouncements) (Icons.campaign_outlined, 'Post announcement', accentPink, const AnnouncementEditScreen()),
      if (Perms.finance) (Icons.south_west, 'Add receipt', accentGreen, const TxnEditScreen(kind: 'receipt')),
      if (Perms.finance) (Icons.north_east, 'Add payment', accentOrange, const TxnEditScreen(kind: 'payment')),
      if (Perms.canWrite(tTxn)) (Icons.upload_file, 'Bulk upload (Excel)', accentSky, const BulkUploadScreen()),
    ];
    if (items.isEmpty) {
      toast(context, 'Nothing to add with your role. Ask the admin if you need more access.');
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Quick add', style: serif(24)),
            const SizedBox(height: 8),
            for (final i in items)
              ListTile(
                leading: CircleAvatar(backgroundColor: i.$3.withValues(alpha: 0.15), child: Icon(i.$1, color: i.$3)),
                title: Text(i.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () { Navigator.pop(c); go(context, i.$4); },
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      drawer: const _AppDrawer(),
      floatingActionButtonLocation: brandFabLocation,
      floatingActionButton: BrandFab(icon: Icons.add, tooltip: 'Quick add', onPressed: () => _quickAdd(context)),
      bottomNavigationBar: BrandBottomBar(items: [
        NavItem(Icons.home_rounded, 'Home', () {}, selected: true),
        NavItem(Icons.calendar_month_outlined, 'Events', () => go(context, const EventsScreen())),
        NavItem(Icons.notifications_none_rounded, 'Announcements', () => go(context, const AnnouncementsScreen())),
        NavItem(Icons.person_outline_rounded, 'Profile', () => go(context, const ProfileScreen())),
      ]),
      header: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Builder(
            builder: (c) => Row(children: [
              RoundIconButton(icon: Icons.menu_rounded, tooltip: 'Menu', onTap: () => Scaffold.of(c).openDrawer()),
              const Spacer(),
              const BrandTitle(),
              const Spacer(),
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
                child: const ClipOval(child: OrgAvatar(size: 40)),
              ),
            ]),
          ),
        ),
      ),
      body: Live<_Summary>(load: _load, builder: (c, s) => _Dashboard(s)),
    );
  }

  static Future<_Summary> _load() async {
    final events = await Store.events();
    final t = dateStr(today());
    final upcoming = events.where((e) => e.s('date').compareTo(t) >= 0).toList();
    final ann = await Store.announcements();
    var active = 0, total = 0;
    if (Perms.members) {
      final m = await Store.members();
      total = m.length;
      active = m.where((x) => x.s('status') == 'Active').length;
    }
    var month = 0.0, bal = 0.0;
    if (Perms.finance) {
      final now = DateTime.now();
      final book = await Store.monthBook(fyStartOf(now), now.year, now.month);
      month = book.rCash + book.rBank;
      bal = book.closeCash + book.closeBank;
    }
    return _Summary(members: total, active: active, upcoming: upcoming, announcements: ann, monthReceipts: month, balance: bal);
  }
}

class _Summary {
  final int members, active;
  final List<dynamic> upcoming, announcements;
  final double monthReceipts, balance;
  _Summary({required this.members, required this.active, required this.upcoming, required this.announcements, required this.monthReceipts, required this.balance});
}

class _Dashboard extends StatelessWidget {
  final _Summary s;
  const _Dashboard(this.s);

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final first = app.userName.split(' ').first;
    final urgent = s.announcements.where((a) => a.data['urgent'] == true).toList();
    final tiles = <_Tile>[
      if (Perms.members) _Tile(Icons.people_alt_rounded, 'Members', accentViolet, () => go(context, const MembersScreen())),
      if (Perms.attendance) _Tile(Icons.fact_check_rounded, 'Attendance', accentGreen, () => go(context, const AttendanceScreen())),
      _Tile(Icons.event_rounded, 'Events', brandBlue, () => go(context, const EventsScreen())),
      _Tile(Icons.campaign_rounded, 'Announce', accentPink, () => go(context, const AnnouncementsScreen())),
      if (Perms.finance) _Tile(Icons.account_balance_wallet_rounded, 'Finance', accentOrange, () => go(context, const FinanceScreen())),
      if (Perms.reports) _Tile(Icons.insights_rounded, 'Reports', accentSky, () => go(context, const ReportsScreen())),
      if (app.isAdmin) _Tile(Icons.manage_accounts_rounded, 'Users', accentViolet, () => go(context, const UsersScreen())),
      if (app.isAdmin) _Tile(Icons.how_to_reg_rounded, 'Approvals', accentPink, () => go(context, const UsersScreen()), badge: true),
      _Tile(Icons.backup_rounded, 'Backup', accentGreen, () => go(context, const BackupScreen())),
    ];
    final pills = <(IconData, String, VoidCallback)>[
      if (Perms.members) (Icons.people_alt_outlined, 'Members', () => go(context, const MembersScreen())),
      (Icons.event_outlined, 'Events', () => go(context, const EventsScreen())),
      if (Perms.attendance) (Icons.fact_check_outlined, 'Attendance', () => go(context, const AttendanceScreen())),
      if (Perms.finance) (Icons.account_balance_wallet_outlined, 'Finance', () => go(context, const FinanceScreen())),
      if (Perms.reports) (Icons.insights_outlined, 'Reports', () => go(context, const ReportsScreen())),
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 110), children: [
      Text('Hi, $first', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 14)),
      const SizedBox(height: 2),
      Text(greeting(), style: serif(36)),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: () => go(context, const SearchScreen()),
        child: AbsorbPointer(child: TextField(decoration: searchDecoration('Search members, events, announcements'))),
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (var i = 0; i < pills.length; i++) PillChip(icon: pills[i].$1, label: pills[i].$2, onTap: pills[i].$3, filled: i == 0),
        ]),
      ),
      if (urgent.isNotEmpty) ...[
        const SizedBox(height: 16),
        Material(
          color: const Color(0xFFFFE1E4),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => go(context, const AnnouncementsScreen()),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.campaign, color: Colors.red)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Urgent announcement', style: TextStyle(fontSize: 11.5, color: Colors.black54)),
                  Text(urgent.first.s('title'), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
                ])),
                const Icon(Icons.chevron_right, color: Colors.black54),
              ]),
            ),
          ),
        ),
      ],
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: Text('Upcoming Events', style: serif(24))),
        TextButton(onPressed: () => go(context, const EventsScreen()), child: const Text('See all')),
      ]),
      if (s.upcoming.isEmpty)
        _EmptyCard(icon: Icons.event_available_outlined, text: 'No upcoming events.${Perms.editEvents ? ' Tap + to add one.' : ''}')
      else
        SizedBox(
          height: 214,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: s.upcoming.length > 8 ? 8 : s.upcoming.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (c, i) => _EventCard(e: s.upcoming[i], color: [brandBlue, accentPink, accentGreen, accentOrange, accentViolet][i % 5]),
          ),
        ),
      const SizedBox(height: 22),
      Text(s.upcoming.isEmpty ? 'Your Church' : 'Next Gathering', style: serif(24)),
      const SizedBox(height: 10),
      _NextCard(s.upcoming.isEmpty ? null : s.upcoming.first),
      if (Perms.members || Perms.finance) ...[
        const SizedBox(height: 22),
        Text('At a Glance', style: serif(24)),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: [
          if (Perms.members) _Stat('Members', '${s.members}', Icons.people_alt_rounded, accentViolet),
          if (Perms.members) _Stat('Active', '${s.active}', Icons.verified_rounded, accentGreen),
          if (Perms.finance) _Stat('Receipts this month', money(s.monthReceipts), Icons.south_west_rounded, accentGreen),
          if (Perms.finance) _Stat('Balance (cash + bank)', money(s.balance), Icons.account_balance_rounded, accentOrange),
        ]),
      ],
      const SizedBox(height: 22),
      Text('Church Tools', style: serif(24)),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 0.95,
        mainAxisSpacing: 12, crossAxisSpacing: 12,
        children: [for (final t in tiles) _TileView(t)],
      ),
      const SizedBox(height: 14),
      Align(alignment: Alignment.center, child: SyncChip(onTap: () => go(context, const SyncScreen()))),
    ]);
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyCard({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(24), boxShadow: softShadow(context)),
        child: Row(children: [Icon(icon, color: brandBlue), const SizedBox(width: 12), Expanded(child: Text(text))]),
      );
}

/// A portrait card like the "Near By Church" cards of the reference: coloured top with the date, title and place below.
class _EventCard extends StatelessWidget {
  final dynamic e;
  final Color color;
  const _EventCard({required this.e, required this.color});
  @override
  Widget build(BuildContext context) {
    final d = parseDate(e.s('date'));
    return GestureDetector(
      onTap: () => go(context, EventDetailScreen(id: e.id)),
      child: Container(
        width: 158,
        decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(26), boxShadow: softShadow(context)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 112,
            margin: const EdgeInsets.all(8),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, color.withValues(alpha: 0.6)])),
            child: Stack(children: [
              Positioned(right: -8, bottom: -10, child: Icon(eventIcon(e.s('kind')), size: 84, color: Colors.white.withValues(alpha: 0.22))),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(d == null ? '-' : '${d.day}', style: serif(40, color: Colors.white)),
                  Text(d == null ? '' : fmtDate(e.s('date')).substring(3), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Text(e.s('title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(17)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
            child: Row(children: [
              const Icon(Icons.place, size: 14, color: brandBlue),
              const SizedBox(width: 3),
              Expanded(child: Text(e.s('venue').isEmpty ? (e.s('time').isEmpty ? e.s('kind') : e.s('time')) : e.s('venue'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF8795B0)))),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The big blue "Next Sermons" style card with the church illustration.
class _NextCard extends StatelessWidget {
  final dynamic e;
  const _NextCard(this.e);
  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return GestureDetector(
      onTap: e == null ? null : () => go(context, EventDetailScreen(id: e.id)),
      child: Container(
        height: 168,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A8CF5), Color(0xFF2F6AE0)]),
          boxShadow: [BoxShadow(color: brandBlue.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Stack(children: [
          const Positioned(right: 6, bottom: 6, child: ChurchIllustration(size: 130, onBlue: true)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e == null ? app.orgName : (e.s('kind') == 'Sunday Worship' ? 'Next Service' : 'Next Event'), style: serif(22, color: Colors.white)),
              const SizedBox(height: 4),
              if (e != null) ...[
                Text(e.s('time').isEmpty ? fmtDate(e.s('date')) : e.s('time'), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                SizedBox(width: 170, child: Text('${e.s('title')} · ${fmtDate(e.s('date'))}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5))),
              ] else
                const Text('Welcome. Events you add\nwill appear here.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(20)),
                child: Text(e == null ? 'God bless you' : 'See details', style: const TextStyle(color: brandNavy, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Stat(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.of(context).size.width - 40 - 12) / 2;
    return Container(
      width: w,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(22), boxShadow: softShadow(context)),
      child: Row(children: [
        CircleAvatar(radius: 20, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: serif(22))),
          Text(label, maxLines: 2, style: const TextStyle(fontSize: 11, color: Color(0xFF8795B0))),
        ])),
      ]),
    );
  }
}

class _Tile {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool badge;
  _Tile(this.icon, this.label, this.color, this.onTap, {this.badge = false});
}

class _TileView extends StatelessWidget {
  final _Tile t;
  const _TileView(this.t);
  @override
  Widget build(BuildContext context) {
    Widget icon = CircleAvatar(radius: 26, backgroundColor: t.color.withValues(alpha: 0.16), child: Icon(t.icon, color: t.color, size: 28));
    if (t.badge) {
      icon = ValueListenableBuilder<int>(
        valueListenable: Users.pending,
        builder: (_, n, child) => Badge(isLabelVisible: n > 0, label: Text('$n'), child: child),
        child: icon,
      );
    }
    return Material(
      color: cardColor(context),
      borderRadius: BorderRadius.circular(24),
      elevation: isDark(context) ? 0 : 3,
      shadowColor: brandBlue.withValues(alpha: 0.18),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: t.onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          icon,
          const SizedBox(height: 8),
          Text(t.label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        ]),
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    void open(Widget w) {
      Navigator.pop(context);
      go(context, w);
    }

    Widget item(IconData i, String t, VoidCallback f) => ListTile(leading: Icon(i), title: Text(t, style: const TextStyle(fontWeight: FontWeight.w500)), onTap: f);

    return Drawer(
      backgroundColor: panelColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(32))),
      child: ListView(padding: EdgeInsets.zero, children: [
        Container(
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 22, 20, 22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [skyTop, brandBlue]),
            borderRadius: BorderRadius.only(bottomRight: Radius.circular(32)),
          ),
          child: Row(children: [
            Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)), child: const ClipOval(child: OrgAvatar(size: 54))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.orgName, style: serif(21, color: Colors.white)),
                Text(app.userName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(app.isAdmin ? 'Admin' : Perms.rolesText(app.roles), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        item(Icons.person_outline, 'Profile', () => open(const ProfileScreen())),
        item(Icons.settings_outlined, 'Settings', () => open(const SettingsScreen())),
        item(Icons.sync, 'Synchronization status', () => open(const SyncScreen())),
        item(Icons.backup_outlined, 'Backup / Restore', () => open(const BackupScreen())),
        if (app.isAdmin) item(Icons.history, 'Audit log', () => open(const AuditScreen())),
        item(Icons.privacy_tip_outlined, 'Privacy & Security', () => open(const PrivacyScreen())),
        item(Icons.help_outline, 'Help & Support', () => open(const HelpScreen())),
        item(Icons.info_outline, 'About App', () => open(const AboutScreen())),
        const Divider(),
        item(Icons.logout, 'Logout', () {
          Navigator.pop(context);
          logoutFlow(context);
        }),
      ]),
    );
  }
}
