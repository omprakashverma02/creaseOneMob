import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import '../tools/excel_import.dart';
import 'team_detail_screen.dart';
import 'team_form_screen.dart';

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});
  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  late Future<List<Map<String, dynamic>>> _future = context.api.teams();
  String _q = '';
  void _reload() => setState(() => _future = context.api.teams());

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthService>().user?.canManage ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Teams'), actions: [
        if (canManage)
          IconButton(
            tooltip: 'Import from Excel',
            icon: const Icon(Icons.upload_file_rounded),
            onPressed: () async {
              await ExcelImportSheet.show(context, 'teams');
              _reload();
            },
          ),
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
      ]),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () async {
                final r = await context.push(const TeamFormScreen());
                if (r != null) _reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('Team', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const LoadingView();
          if (s.hasError) return ErrorView(message: s.error.toString(), onRetry: _reload);
          final list = s.data!
              .where((t) => '${t['name']} ${t['shortName'] ?? ''} ${t['city'] ?? ''}'.toLowerCase().contains(_q.toLowerCase()))
              .toList()
            ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
              TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search teams'), onChanged: (v) => setState(() => _q = v)),
              const SizedBox(height: 12),
              if (list.isEmpty) const SizedBox(height: 380, child: EmptyView(icon: Icons.shield_outlined, title: 'No teams', subtitle: 'Create teams and add players to their squads.')),
              for (final t in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GradientCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    onTap: () async {
                      await context.push(TeamDetailScreen(teamId: t['id'].toString()));
                      _reload();
                    },
                    child: Row(children: [
                      TeamBadge(name: t['name'] ?? '', logoUrl: t['logoUrl'], color: t['themeColor'], size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
                          const SizedBox(height: 2),
                          Text([t['shortName'], t['city']].where((e) => e != null && '$e'.isNotEmpty).join(' • '),
                              style: const TextStyle(color: AppColors.textMid, fontSize: 12.5)),
                        ]),
                      ),
                      Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.fromHex(t['themeColor']))),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, color: AppColors.textLo),
                    ]),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
