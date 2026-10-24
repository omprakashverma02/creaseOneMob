import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import '../tools/excel_import.dart';
import 'player_detail_screen.dart';
import 'player_form_screen.dart';

class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key, this.embedded = false});

  /// Inside the Stats hub: no app bar of its own.
  final bool embedded;
  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  String _q = '';
  String _role = 'all';
  bool _mine = false;
  Timer? _debounce;
  late Future<List<Map<String, dynamic>>> _future = _fetch();

  Future<List<Map<String, dynamic>>> _fetch() {
    final api = context.api;
    if (_q.trim().isNotEmpty) return api.searchPlayers(_q);
    return api.players(mine: _mine, role: _role == 'all' ? null : _role);
  }

  void _reload() => setState(() => _future = _fetch());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthService>().user?.canManage ?? false;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Players'), actions: [
        if (canManage)
          IconButton(
            tooltip: 'Import from Excel',
            icon: const Icon(Icons.upload_file_rounded),
            onPressed: () async {
              await ExcelImportSheet.show(context, 'players');
              _reload();
            },
          ),
      ]),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () async {
                final r = await context.push(const PlayerFormScreen());
                if (r != null) _reload();
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Player', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, mobile, email or ID'),
            onChanged: (v) {
              _q = v;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), _reload);
            },
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            FilterChip(label: const Text('Created by me'), selected: _mine, onSelected: (v) {
              _mine = v;
              _reload();
            }),
            const SizedBox(width: 8),
            for (final r in ['all', ...Cricket.playerRoles])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(r == 'all' ? 'All roles' : Cricket.roleLabel(r)),
                  selected: _role == r,
                  onSelected: (_) {
                    _role = r;
                    _reload();
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) return const LoadingView();
              if (s.hasError) return ErrorView(message: s.error.toString(), onRetry: _reload);
              final list = s.data!;
              if (list.isEmpty) return const EmptyView(icon: Icons.groups_outlined, title: 'No players found');
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 100, top: 4),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(indent: 72),
                  itemBuilder: (c, i) {
                    final p = list[i];
                    return ListTile(
                      leading: PlayerAvatar(name: p['name'] ?? '', imageUrl: p['imageUrl'], size: 44),
                      title: Text(p['name']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        [Cricket.roleLabel(p['role']), p['battingStyle'], if (p['bowlingStyle'] != null && p['bowlingStyle'] != 'None') p['bowlingStyle']]
                            .where((e) => e != null)
                            .join(' • '),
                        style: const TextStyle(fontSize: 12, color: AppColors.textMid),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textLo),
                      onTap: () async {
                        await context.push(PlayerDetailScreen(playerId: p['id'].toString()));
                        _reload();
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
