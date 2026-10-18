import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'player_form_screen.dart';

/// Multi-select search over all registered players (name / mobile / email / id).
Future<List<String>?> showPlayerMultiSearch(BuildContext context, {Set<String> exclude = const {}, String title = 'Add players'}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _PlayerSearchSheet(exclude: exclude, title: title),
  );
}

class _PlayerSearchSheet extends StatefulWidget {
  const _PlayerSearchSheet({required this.exclude, required this.title});
  final Set<String> exclude;
  final String title;
  @override
  State<_PlayerSearchSheet> createState() => _PlayerSearchSheetState();
}

class _PlayerSearchSheetState extends State<_PlayerSearchSheet> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> results = [];
  final selected = <String, Map<String, dynamic>>{};
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => loading = true);
    try {
      final r = q.trim().isEmpty ? await context.api.players(mine: true) : await context.api.searchPlayers(q);
      if (mounted) setState(() => results = r);
    } catch (_) {
      if (mounted) setState(() => results = []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (c, sc) => Column(children: [
        Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            controller: _q,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Name, mobile, email or unique ID',
              suffixIcon: loading ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => _search(v));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text(_q.text.isEmpty ? 'Players you created' : '${results.length} found', style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                final p = await context.push<Map<String, dynamic>>(PlayerFormScreen(initialName: _q.text.trim()));
                if (p != null && p['id'] != null) {
                  setState(() {
                    results.insert(0, p);
                    selected[p['id'].toString()] = p;
                  });
                }
              },
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Create new'),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            controller: sc,
            itemCount: results.length,
            itemBuilder: (c, i) {
              final p = results[i];
              final id = p['id'].toString();
              final already = widget.exclude.contains(id);
              return CheckboxListTile(
                value: already || selected.containsKey(id),
                onChanged: already ? null : (v) => setState(() => v == true ? selected[id] = p : selected.remove(id)),
                secondary: PlayerAvatar(name: p['name'] ?? '', imageUrl: p['imageUrl'], size: 40),
                title: Text(p['name']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    [Cricket.roleLabel(p['role']), if (p['mobileNumber'] != null) '••${p['mobileNumber'].toString().length > 4 ? p['mobileNumber'].toString().substring(p['mobileNumber'].toString().length - 4) : p['mobileNumber']}', if (already) 'Already in squad']
                        .join(' • '),
                    style: const TextStyle(fontSize: 12)),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(context, selected.keys.toList()),
              child: Text('Add ${selected.length} player(s)'),
            ),
          ),
        ),
      ]),
    );
  }
}
