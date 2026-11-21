import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'sync_screen.dart';

IconData eventIcon(String kind) => switch (kind) {
      'Sunday Worship' => Icons.church_outlined,
      'Convention' => Icons.campaign_outlined,
      'Youth Meeting' => Icons.groups_outlined,
      'VBS / Sunday School' => Icons.child_care,
      'Special Meeting' => Icons.star_outline,
      _ => Icons.event_outlined,
    };

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  bool _past = false;
  DateTime? _day; // a day picked on the week strip (null = all upcoming)
  late DateTime _weekStart = _mondayOf(today());

  static DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Events')),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Perms.editEvents ? FloatingActionButton(tooltip: 'Add event', shape: const CircleBorder(), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EventEditScreen())), child: const Icon(Icons.add, size: 30)) : null,
      body: Live<List<Rec>>(
        load: Store.events,
        builder: (c, all) {
          final t = dateStr(today());
          final days = {for (final e in all) e.s('date')};
          List<Rec> list;
          if (_day != null) {
            list = all.where((e) => e.s('date') == dateStr(_day!)).toList();
          } else {
            list = all.where((e) => _past ? e.s('date').compareTo(t) < 0 : e.s('date').compareTo(t) >= 0).toList();
            if (_past) list.sort((a, b) => b.s('date').compareTo(a.s('date')));
          }
          return Column(children: [
            // month + week strip
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)))),
                Expanded(child: Text(monthYear(_weekStart.add(const Duration(days: 3))), textAlign: TextAlign.center, style: serif(22))),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _weekStart = _weekStart.add(const Duration(days: 7)))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(children: [
                for (var i = 0; i < 7; i++) _dayCell(_weekStart.add(Duration(days: i)), days),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: _day != null
                  ? Row(children: [
                      Expanded(child: Text(fmtDate(dateStr(_day!)), style: serif(20))),
                      TextButton.icon(onPressed: () => setState(() => _day = null), icon: const Icon(Icons.close, size: 18), label: const Text('Clear')),
                    ])
                  : SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [ButtonSegment(value: false, label: Text('Upcoming')), ButtonSegment(value: true, label: Text('Past'))],
                      selected: {_past},
                      onSelectionChanged: (v) => setState(() => _past = v.first),
                    ),
            ),
            Expanded(
              child: list.isEmpty
                  ? EmptyState(Icons.event_busy_outlined, _day != null ? 'Nothing on this day.' : (_past ? 'No past events.' : 'No upcoming events.'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 100, top: 4),
                      itemCount: list.length,
                      itemBuilder: (c, i) => _EventTile(list[i], i),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _dayCell(DateTime d, Set<String> eventDays) {
    final sel = _day != null && dateStr(_day!) == dateStr(d);
    final isToday = dateStr(d) == dateStr(today());
    final has = eventDays.contains(dateStr(d));
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _day = sel ? null : d),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? brandBlue : (isToday ? const Color(0xFFDCE8FD) : Colors.transparent),
            borderRadius: BorderRadius.circular(22),
            boxShadow: sel ? [BoxShadow(color: brandBlue.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 5))] : null,
          ),
          child: Column(children: [
            Text(names[d.weekday - 1], style: TextStyle(fontSize: 11, color: sel ? Colors.white70 : const Color(0xFF8795B0))),
            const SizedBox(height: 4),
            Text('${d.day}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: sel ? Colors.white : null)),
            const SizedBox(height: 4),
            Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: has ? (sel ? Colors.white : accentOrange) : Colors.transparent)),
          ]),
        ),
      ),
    );
  }
}

/// Event card in the style of the reference: serif title, a time pill, the details, and a round icon button.
class _EventTile extends StatelessWidget {
  final Rec e;
  final int index;
  const _EventTile(this.e, this.index);
  @override
  Widget build(BuildContext context) {
    final color = [brandBlue, accentPink, accentGreen, accentOrange, accentViolet][index % 5];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(28), boxShadow: softShadow(context)),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailScreen(id: e.id))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.s('title'), style: serif(22)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _pill(Icons.calendar_today_rounded, fmtDate(e.s('date')), color),
                    if (e.s('time').isNotEmpty) _pill(Icons.access_time_rounded, e.s('time'), color),
                  ]),
                  if (e.s('venue').isNotEmpty || e.s('description').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text([if (e.s('venue').isNotEmpty) e.s('venue'), if (e.s('description').isNotEmpty) e.s('description')].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Color(0xFF8795B0))),
                  ],
                ]),
              ),
              const SizedBox(width: 10),
              CircleAvatar(radius: 24, backgroundColor: color.withValues(alpha: 0.14), child: Icon(eventIcon(e.s('kind')), color: color)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData i, String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 14, color: c), const SizedBox(width: 5), Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c))]),
      );
}

String monthYear(DateTime d) {
  const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${m[d.month - 1]} ${d.year}';
}

class EventDetailScreen extends StatelessWidget {
  final String id;
  const EventDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Live<Rec?>(
      load: () => Db.instance.get(id),
      builder: (c, e) {
        if (e == null || e.deleted) return SkyScaffold(appBar: AppBar(), body: const EmptyState(Icons.event_busy_outlined, 'This event no longer exists.'));
        return SkyScaffold(
          appBar: AppBar(title: Text(e.s('title')), actions: [
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => Share.share('${AppState.instance.orgName}\n${e.s('title')}\n${fmtDate(e.s('date'))} ${e.s('time')}\n${e.s('venue')}\n${e.s('description')}'.trim()),
            ),
            if (Perms.editEvents) IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventEditScreen(existing: e)))),
            if (Perms.editEvents)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirm(context, 'Delete this event?', e.s('title'), yes: 'Delete')) return;
                  await Store.remove(e, 'Event ${e.s('title')}');
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            if (e.conflict != null) ConflictBanner(rec: e),
            ListTile(leading: Icon(eventIcon(e.s('kind'))), title: Text(e.s('kind'))),
            ListTile(leading: const Icon(Icons.calendar_today_outlined), title: Text(fmtDate(e.s('date')))),
            if (e.s('time').isNotEmpty) ListTile(leading: const Icon(Icons.schedule), title: Text(e.s('time'))),
            if (e.s('venue').isNotEmpty) ListTile(leading: const Icon(Icons.place_outlined), title: Text(e.s('venue'))),
            if (e.s('description').isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(e.s('description'))),
          ]),
        );
      },
    );
  }
}

class EventEditScreen extends StatefulWidget {
  final Rec? existing;
  const EventEditScreen({super.key, this.existing});
  @override
  State<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends State<EventEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.s('title'));
  late final _date = TextEditingController(text: widget.existing?.s('date') ?? dateStr(today()));
  late final _time = TextEditingController(text: widget.existing?.s('time'));
  late final _venue = TextEditingController(text: widget.existing?.s('venue'));
  late final _desc = TextEditingController(text: widget.existing?.s('description'));
  late String _kind = eventKinds.contains(widget.existing?.s('kind')) ? widget.existing!.s('kind') : eventKinds.first;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await Store.save(tEvent, id: widget.existing?.id, summary: 'Event ${_title.text.trim()}', data: {
      'title': _title.text.trim(), 'kind': _kind, 'date': _date.text, 'time': _time.text.trim(), 'venue': _venue.text.trim(), 'description': _desc.text.trim(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return SkyScaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add event' : 'Edit event')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: _title, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Title *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
          gap,
          DropdownButtonFormField<String>(initialValue: _kind, decoration: const InputDecoration(labelText: 'Type'), items: [for (final k in eventKinds) DropdownMenuItem(value: k, child: Text(k))], onChanged: (v) => _kind = v ?? _kind),
          gap,
          DateField(label: 'Date', controller: _date, required: true),
          gap,
          TextFormField(controller: _time, decoration: const InputDecoration(labelText: 'Time', hintText: 'e.g. 10:00 AM')),
          gap,
          TextFormField(controller: _venue, decoration: const InputDecoration(labelText: 'Venue')),
          gap,
          TextFormField(controller: _desc, maxLines: 4, decoration: const InputDecoration(labelText: 'Details')),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ]),
      ),
    );
  }
}
