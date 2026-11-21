import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'sync_screen.dart';

const _genders = ['Male', 'Female'];
const _relations = ['Head', 'Spouse', 'Son', 'Daughter', 'Parent', 'Other'];

Color statusColor(String s) => switch (s) { 'Active' => Colors.green.shade700, 'Inactive' => Colors.orange.shade800, _ => Colors.blueGrey };

// ====================================================================== list
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});
  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  String _q = '', _status = 'All';

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Members')),
      floatingActionButton: Perms.editMembers ? FloatingActionButton(tooltip: 'Add member', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberEditScreen())), child: const Icon(Icons.person_add_alt_1)) : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: TextField(decoration: searchDecoration('Search name, phone, family'), onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final s in ['All', ...memberStatuses])
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: ChoiceChip(label: Text(s), selected: _status == s, onSelected: (_) => setState(() => _status = s))),
          ]),
        ),
        Expanded(
          child: Live<List<Rec>>(
            load: Store.members,
            builder: (c, all) {
              final list = all.where((m) {
                if (_status != 'All' && m.s('status') != _status) return false;
                if (_q.isEmpty) return true;
                return '${m.s('name')} ${m.s('phone')} ${m.s('familyName')}'.toLowerCase().contains(_q);
              }).toList();
              if (list.isEmpty) return EmptyState(Icons.people_outline, all.isEmpty ? 'No members yet.${Perms.editMembers ? '\nTap + to add the first member.' : ''}' : 'No member matches.');
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final m = list[i];
                  return RowCard(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MemberDetailScreen(id: m.id))),
                    child: ListTile(
                      leading: CircleAvatar(child: Text(m.s('name').isEmpty ? '?' : m.s('name')[0].toUpperCase())),
                      title: Text(m.s('name'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([if (m.s('phone').isNotEmpty) m.s('phone'), if (m.s('familyName').isNotEmpty) '${m.s('familyName')} family'].join(' · ')),
                      trailing: m.conflict != null
                          ? const Icon(Icons.warning_amber, color: Colors.deepOrange)
                          : Text(m.s('status'), style: TextStyle(color: statusColor(m.s('status')), fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ====================================================================== detail
class MemberDetailScreen extends StatelessWidget {
  final String id;
  const MemberDetailScreen({super.key, required this.id});

  Widget _row(IconData i, String k, String v) => v.isEmpty ? const SizedBox.shrink() : ListTile(dense: true, leading: Icon(i), title: Text(k, style: const TextStyle(fontSize: 12.5)), subtitle: Text(v, style: const TextStyle(fontSize: 15)));

  @override
  Widget build(BuildContext context) {
    return Live<Rec?>(
      load: () => Db.instance.get(id),
      builder: (c, m) {
        if (m == null || m.deleted) return SkyScaffold(appBar: AppBar(), body: const EmptyState(Icons.person_off_outlined, 'This member no longer exists.'));
        return SkyScaffold(
          appBar: AppBar(title: Text(m.s('name')), actions: [
            if (Perms.editMembers) IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MemberEditScreen(existing: m)))),
            if (Perms.editMembers)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirm(context, 'Delete ${m.s('name')}?', 'Consider setting the status to Inactive or Transferred instead: those members keep their history.', yes: 'Delete')) return;
                  await Store.remove(m, 'Member ${m.s('name')}');
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ]),
          body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
            if (m.conflict != null) ConflictBanner(rec: m),
            _row(Icons.verified_outlined, 'Status', m.s('status')),
            _row(Icons.phone_outlined, 'Phone', m.s('phone')),
            _row(Icons.mail_outline, 'Email', m.s('email')),
            _row(Icons.wc, 'Gender', m.s('gender')),
            _row(Icons.cake_outlined, 'Date of birth', m.s('dob').isEmpty ? '' : fmtDate(m.s('dob'))),
            _row(Icons.home_outlined, 'Address', m.s('address')),
            _row(Icons.family_restroom, 'Family', m.s('familyName').isEmpty ? '' : '${m.s('familyName')} family · ${m.s('relation')}'),
            _row(Icons.emergency_outlined, 'Emergency contact', m.s('emergencyContact')),
            _row(Icons.notes, 'Notes', m.s('notes')),
            if (m.s('familyName').isNotEmpty)
              Live<List<Rec>>(
                load: Store.members,
                builder: (c, all) {
                  final fam = all.where((x) => x.id != m.id && x.s('familyName').toLowerCase() == m.s('familyName').toLowerCase()).toList();
                  if (fam.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SectionTitle('Family members'),
                    for (final f in fam)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline),
                        title: Text(f.s('name')),
                        subtitle: Text(f.s('relation')),
                        onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MemberDetailScreen(id: f.id))),
                      ),
                  ]);
                },
              ),
            if (Perms.baptism)
              FutureBuilder<Rec?>(
                future: Store.baptismOf(m.id),
                builder: (c, snap) {
                  final b = snap.data;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SectionTitle('Baptism and salvation (restricted)'),
                    if (b == null) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Not recorded.')),
                    if (b != null) ...[
                      _row(Icons.water_drop_outlined, 'Baptised', b.data['baptised'] == true ? 'Yes' : 'No'),
                      _row(Icons.event_outlined, 'Baptism date', b.s('baptismDate').isEmpty ? '' : fmtDate(b.s('baptismDate'))),
                      _row(Icons.favorite_outline, 'Salvation date', b.s('salvationDate').isEmpty ? '' : fmtDate(b.s('salvationDate'))),
                      _row(Icons.church_outlined, 'Church of baptism', b.s('church')),
                      _row(Icons.notes, 'Notes', b.s('notes')),
                    ],
                  ]);
                },
              ),
          ]),
        );
      },
    );
  }
}

// ====================================================================== add / edit
class MemberEditScreen extends StatefulWidget {
  final Rec? existing;
  const MemberEditScreen({super.key, this.existing});
  @override
  State<MemberEditScreen> createState() => _MemberEditScreenState();
}

class _MemberEditScreenState extends State<MemberEditScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> c;
  String _gender = '', _relation = 'Head', _status = 'Active';
  bool _baptised = false, _saving = false;
  final _bDate = TextEditingController(), _sDate = TextEditingController(), _bChurch = TextEditingController(), _bNotes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    c = {for (final k in ['name', 'phone', 'email', 'dob', 'address', 'familyName', 'emergencyContact', 'notes']) k: TextEditingController(text: m?.s(k) ?? '')};
    _gender = m?.s('gender') ?? '';
    _relation = (m?.s('relation').isNotEmpty ?? false) ? m!.s('relation') : 'Head';
    _status = (m?.s('status').isNotEmpty ?? false) ? m!.s('status') : 'Active';
    if (m != null && Perms.baptism) {
      Store.baptismOf(m.id).then((b) {
        if (b == null || !mounted) return;
        setState(() {
          _baptised = b.data['baptised'] == true;
          _bDate.text = b.s('baptismDate');
          _sDate.text = b.s('salvationDate');
          _bChurch.text = b.s('church');
          _bNotes.text = b.s('notes');
        });
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final name = c['name']!.text.trim();
    final id = widget.existing?.id ?? newId();
    await Store.save(tMember, id: id, summary: 'Member $name', data: {
      for (final e in c.entries) e.key: e.value.text.trim(),
      'gender': _gender, 'relation': _relation, 'status': _status,
    });
    if (Perms.baptism && (_baptised || _bDate.text.isNotEmpty || _sDate.text.isNotEmpty || await Store.baptismOf(id) != null)) {
      await Store.save(tBaptism, id: 'bap-$id', summary: 'Baptism details of $name', data: {
        'memberId': id, 'memberName': name, 'baptised': _baptised, 'baptismDate': _bDate.text, 'salvationDate': _sDate.text,
        'church': _bChurch.text.trim(), 'notes': _bNotes.text.trim(),
      });
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return SkyScaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add member' : 'Edit member')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: c['name'], textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
          gap,
          TextFormField(controller: c['phone'], keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
          gap,
          TextFormField(controller: c['email'], keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          gap,
          DropdownButtonFormField<String>(
            initialValue: _genders.contains(_gender) ? _gender : null,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: [for (final g in _genders) DropdownMenuItem(value: g, child: Text(g))],
            onChanged: (v) => _gender = v ?? '',
          ),
          gap,
          StatefulBuilder(builder: (_, __) => DateField(label: 'Date of birth', controller: c['dob']!)),
          gap,
          TextFormField(controller: c['address'], maxLines: 2, decoration: const InputDecoration(labelText: 'Address')),
          const SectionTitle('Family'),
          TextFormField(controller: c['familyName'], textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Family name', helperText: 'Members with the same family name are shown together')),
          gap,
          DropdownButtonFormField<String>(
            initialValue: _relation,
            decoration: const InputDecoration(labelText: 'Relationship in the family'),
            items: [for (final g in _relations) DropdownMenuItem(value: g, child: Text(g))],
            onChanged: (v) => _relation = v ?? 'Head',
          ),
          gap,
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Membership status'),
            items: [for (final g in memberStatuses) DropdownMenuItem(value: g, child: Text(g))],
            onChanged: (v) => _status = v ?? 'Active',
          ),
          gap,
          TextFormField(controller: c['emergencyContact'], decoration: const InputDecoration(labelText: 'Emergency contact (name and phone)')),
          gap,
          TextFormField(controller: c['notes'], maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
          if (Perms.baptism) ...[
            const SectionTitle('Baptism and salvation (restricted)'),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Baptised'), value: _baptised, onChanged: (v) => setState(() => _baptised = v)),
            StatefulBuilder(builder: (_, __) => DateField(label: 'Baptism date', controller: _bDate)),
            gap,
            StatefulBuilder(builder: (_, __) => DateField(label: 'Salvation date', controller: _sDate)),
            gap,
            TextFormField(controller: _bChurch, decoration: const InputDecoration(labelText: 'Church of baptism')),
            gap,
            TextFormField(controller: _bNotes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ]),
      ),
    );
  }
}
