import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/bulk_import.dart';
import '../core/store.dart';
import '../ui.dart';
import '../widgets.dart';

/// Bulk upload of receipts and payments from an Excel file for the selected financial year.
class BulkUploadScreen extends StatefulWidget {
  final int? fy;
  const BulkUploadScreen({super.key, this.fy});
  @override
  State<BulkUploadScreen> createState() => _BulkUploadScreenState();
}

class _BulkUploadScreenState extends State<BulkUploadScreen> {
  late int _fy = widget.fy ?? fyStartOf(DateTime.now());
  BulkResult? _res;
  String? _fileName;
  bool _busy = false;

  String get _range => '1 Apr $_fy to 31 Mar ${_fy + 1}';

  Future<void> _template() async {
    setState(() => _busy = true);
    try {
      final bytes = BulkImport.buildTemplate(_fy);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/Freely-CMS-Finance-Template-FY${fyLabel(_fy)}.xlsx');
      await f.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(f.path)], text: 'Freely CMS finance upload template - FY ${fyLabel(_fy)}');
    } catch (e) {
      if (mounted) toast(context, 'Could not create the template: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final pick = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
    final f = pick?.files.single;
    if (f == null || !mounted) return;
    setState(() { _busy = true; _res = null; _fileName = f.name; });
    try {
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      final r = await BulkImport.parse(bytes, _fy);
      if (mounted) setState(() => _res = r);
    } catch (e) {
      if (mounted) toast(context, 'Could not read the file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final r = _res!;
    final n = r.valid.length;
    final ob = r.opening;
    final msg = '$n entr${n == 1 ? 'y' : 'ies'} will be added for FY ${fyLabel(_fy)} (receipts ${money(r.receipts)}, payments ${money(r.payments)}).'
        '${ob == null ? '' : '\nOpening balance will be set to cash ${money(ob.cash)}, bank ${money(ob.bank)}.'}'
        '\nRows with errors or duplicates are not imported.';
    if (!await confirm(context, 'Import to FY ${fyLabel(_fy)}?', msg, yes: 'Import')) return;
    setState(() => _busy = true);
    try {
      final added = await BulkImport.commit(r);
      if (!mounted) return;
      toast(context, '$added entr${added == 1 ? 'y' : 'ies'} imported.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Import stopped: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _res;
    final fys = [for (var y = fyStartOf(DateTime.now()) - 8; y <= fyStartOf(DateTime.now()) + 1; y++) y].reversed.toList();
    return SkyScaffold(
      appBar: AppBar(title: const Text('Bulk upload (Excel)')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Step 1 - Select financial year', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _fy,
            decoration: const InputDecoration(labelText: 'Financial year'),
            items: [for (final y in fys) DropdownMenuItem(value: y, child: Text('FY ${fyLabel(y)}'))],
            onChanged: (v) => setState(() { _fy = v ?? _fy; _res = null; _fileName = null; }),
          ),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Entry dates must be between $_range.', style: const TextStyle(fontSize: 12.5))),
          const SizedBox(height: 18),
          const Text('Step 2 - Download the template and fill it in', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _template, icon: const Icon(Icons.download_outlined), label: Text('Download template (FY ${fyLabel(_fy)})')),
          const SizedBox(height: 18),
          const Text('Step 3 - Upload the completed file', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.upload_file), label: Text(_fileName == null ? 'Choose Excel file (.xlsx)' : 'Choose another file')),
          if (_busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          if (r != null) ..._preview(r),
        ]),
      ),
    );
  }

  List<Widget> _preview(BulkResult r) {
    if (r.fileError != null) {
      return [
        const SizedBox(height: 16),
        Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(14), child: Text(r.fileError!, style: const TextStyle(color: Colors.black87)))),
      ];
    }
    final bad = r.invalid;
    final skip = r.skipped;
    final ob = r.opening;
    return [
      const SizedBox(height: 18),
      Text('${_fileName ?? 'File'} - ${r.rows.length} row${r.rows.length == 1 ? '' : 's'} read', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Chip(avatar: const Icon(Icons.check_circle, color: Colors.green, size: 18), label: Text('${r.valid.length} ready')),
        Chip(avatar: const Icon(Icons.error, color: Colors.red, size: 18), label: Text('${bad.length} with errors')),
        Chip(avatar: const Icon(Icons.skip_next, color: Colors.orange, size: 18), label: Text('${skip.length} skipped')),
      ]),
      const SizedBox(height: 8),
      if (r.valid.isNotEmpty) Text('Receipts ${money(r.receipts)} · Payments ${money(r.payments)}', style: const TextStyle(fontWeight: FontWeight.w600)),
      if (ob != null) Text('Opening balance: cash ${money(ob.cash)} · bank ${money(ob.bank)}', style: const TextStyle(fontWeight: FontWeight.w600)),
      if (bad.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Fix these rows in Excel and upload again (they will not be imported):', style: TextStyle(fontSize: 12.5)),
        for (final b in bad.take(50))
          ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline, color: Colors.red),
            title: Text('Row ${b.line}${(b.data['head'] as String).isEmpty ? '' : ' - ${b.data['head']}'}'),
            subtitle: Text(b.errors.join('\n')),
          ),
        if (bad.length > 50) Text('... and ${bad.length - 50} more rows with errors.'),
      ],
      if (skip.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final s in skip.take(20))
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.skip_next, color: Colors.orange), title: Text('Row ${s.line} - ${s.data['head']} ${money(s.data['amount'] as double)}'), subtitle: Text(s.skipReason!)),
        if (skip.length > 20) Text('... and ${skip.length - 20} more skipped.'),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: (r.valid.isEmpty && ob == null) ? null : _import,
        icon: const Icon(Icons.playlist_add_check),
        label: Text('Import ${r.valid.length} entr${r.valid.length == 1 ? 'y' : 'ies'}'),
      ),
    ];
  }
}
