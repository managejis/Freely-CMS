import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'sync_screen.dart';

// ====================================================================== history
class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Attendance')),
      floatingActionButton: Perms.takeAttendance ? FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceTakeScreen())), icon: const Icon(Icons.fact_check_outlined), label: const Text('Take attendance')) : null,
      body: Live<List<Rec>>(
        load: Store.attendance,
        builder: (c, list) => list.isEmpty
            ? const EmptyState(Icons.fact_check_outlined, 'No attendance recorded yet.')
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final a = list[i];
                  return RowCard(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceTakeScreen(existing: a))),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                      title: Text('${a.s('service')} · ${fmtDate(a.s('date'))}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${a.i('presentCount')} present${a.i('visitors') > 0 ? ' + ${a.i('visitors')} visitors' : ''}'),
                      trailing: a.conflict != null ? const Icon(Icons.warning_amber, color: Colors.deepOrange) : const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ====================================================================== take / edit one attendance sheet
/// One attendance sheet per service per day. Opening the same day and service again edits the same sheet.
class AttendanceTakeScreen extends StatefulWidget {
  final Rec? existing;
  const AttendanceTakeScreen({super.key, this.existing});
  @override
  State<AttendanceTakeScreen> createState() => _AttendanceTakeScreenState();
}

class _AttendanceTakeScreenState extends State<AttendanceTakeScreen> {
  late String _date, _service;
  final Set<String> _present = {};
  final _visitors = TextEditingController(), _notes = TextEditingController();
  String _q = '';
  bool _loaded = false;

  bool get _canEdit => Perms.takeAttendance;

  @override
  void initState() {
    super.initState();
    _date = widget.existing?.s('date') ?? dateStr(today());
    _service = widget.existing?.s('service') ?? services.first;
    _load();
  }

  /// Loads an earlier sheet for the chosen date and service, if somebody already took it.
  Future<void> _load() async {
    final a = await Db.instance.get(Store.attendanceId(_date, _service));
    _present.clear();
    if (a != null && !a.deleted) {
      _present.addAll([for (final x in (a.data['presentIds'] as List? ?? const [])) '$x']);
      _visitors.text = a.i('visitors') > 0 ? '${a.i('visitors')}' : '';
      _notes.text = a.s('notes');
    } else {
      _visitors.clear();
      _notes.clear();
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save(List<Rec> members) async {
    final names = [for (final m in members) if (_present.contains(m.id)) m.s('name')];
    final presentIds = [for (final m in members) if (_present.contains(m.id)) m.id];
    await Store.save(tAttendance, id: Store.attendanceId(_date, _service), summary: '$_service $_date: ${presentIds.length} present', data: {
      'date': _date, 'service': _service, 'presentIds': presentIds, 'presentNames': names, 'presentCount': presentIds.length,
      'visitors': int.tryParse(_visitors.text.trim()) ?? 0, 'notes': _notes.text.trim(),
    });
    if (mounted) {
      toast(context, 'Attendance saved');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: Text(_canEdit ? 'Take attendance' : 'Attendance')),
      body: Live<List<Rec>>(
        load: () async => (await Store.members()).where((m) => m.s('status') != 'Transferred').toList(),
        builder: (c, members) {
          final shown = members.where((m) => _q.isEmpty || m.s('name').toLowerCase().contains(_q)).toList();
          final att = widget.existing;
          return Column(children: [
            if (att?.conflict != null) ConflictBanner(rec: att!),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _service,
                    decoration: const InputDecoration(labelText: 'Service', isDense: true),
                    items: [for (final s in services) DropdownMenuItem(value: s, child: Text(s))],
                    onChanged: _canEdit ? (v) { _service = v ?? _service; _load(); } : null,
                  ),
                ),
                const SizedBox(width: 10),
                ActionChip(
                  avatar: const Icon(Icons.calendar_today, size: 16),
                  label: Text(fmtDate(_date)),
                  onPressed: !_canEdit ? null : () async {
                    final d = await showDatePicker(context: context, initialDate: parseDate(_date) ?? today(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) { _date = dateStr(d); _load(); }
                  },
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: TextField(decoration: searchDecoration('Search members'), onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Text('${_present.length} of ${members.length} present', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_canEdit) ...[
                  TextButton(onPressed: () => setState(() => _present.addAll(shown.map((m) => m.id))), child: const Text('All')),
                  TextButton(onPressed: () => setState(() => _present.removeAll(shown.map((m) => m.id))), child: const Text('None')),
                ],
              ]),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : members.isEmpty
                      ? const EmptyState(Icons.people_outline, 'Add members first, then take attendance.')
                      : ListView(children: [
                          for (final m in shown)
                            CheckboxListTile(
                              value: _present.contains(m.id),
                              title: Text(m.s('name')),
                              subtitle: m.s('familyName').isEmpty ? null : Text('${m.s('familyName')} family'),
                              onChanged: !_canEdit ? null : (v) => setState(() => v == true ? _present.add(m.id) : _present.remove(m.id)),
                            ),
                          if (_canEdit)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                              child: Column(children: [
                                TextField(controller: _visitors, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Visitors (count)')),
                                const SizedBox(height: 10),
                                TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes')),
                              ]),
                            ),
                        ]),
            ),
            if (_canEdit)
              SafeArea(
                child: Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _save(members), icon: const Icon(Icons.check), label: const Text('Save attendance')))),
              ),
          ]);
        },
      ),
    );
  }
}
