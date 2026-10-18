import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Save bytes to a temp file and open the share sheet (save to Files / Drive / email).
Future<void> shareBytes(BuildContext context, List<int> bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: filename));
}

Future<File?> pickFile({List<String> extensions = const ['xlsx', 'xls']}) async {
  final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: extensions);
  final path = r?.files.single.path;
  return path == null ? null : File(path);
}

/// Bulk import teams / players / matches from the web's Excel templates.
class ExcelImportSheet extends StatefulWidget {
  const ExcelImportSheet({super.key, required this.kind, this.tournamentId});

  /// teams | players | matches
  final String kind;
  final String? tournamentId;

  static Future<bool?> show(BuildContext context, String kind, {String? tournamentId}) =>
      showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => ExcelImportSheet(kind: kind, tournamentId: tournamentId));

  @override
  State<ExcelImportSheet> createState() => _ExcelImportSheetState();
}

class _ExcelImportSheetState extends State<ExcelImportSheet> {
  bool busy = false;
  Map<String, dynamic>? result;

  Future<void> _template() async {
    setState(() => busy = true);
    try {
      final bytes = await context.api.template(widget.kind);
      if (mounted) await shareBytes(context, bytes, 'creaseone-${widget.kind}-template.xlsx');
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _import() async {
    final f = await pickFile();
    if (f == null || !mounted) return;
    setState(() => busy = true);
    try {
      final r = await context.api.importExcel(widget.kind, f, tournamentId: widget.tournamentId);
      if (mounted) setState(() => result = r);
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final errors = asMapList(result?['errors']);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Import ${widget.kind} from Excel', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('1. Download the template  2. Fill it in  3. Upload the .xlsx', style: TextStyle(color: AppColors.textMid)),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: busy ? null : _template, icon: const Icon(Icons.download_rounded), label: const Text('Download template')),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: busy ? null : _import, icon: const Icon(Icons.upload_file_rounded), label: Text(busy ? 'Working…' : 'Upload filled sheet')),
          if (result != null) ...[
            const SizedBox(height: 16),
            Text('Created ${asInt(result!['created'])}${result!['matched'] != null ? ' • matched ${asInt(result!['matched'])}' : ''} • ${errors.length} error(s)',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
            for (final e in errors.take(8)) Text('Row ${e['row']}: ${e['error']}', style: const TextStyle(color: AppColors.live, fontSize: 12)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
          ],
        ]),
      ),
    );
  }
}
