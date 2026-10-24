import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import 'tournament_detail_screen.dart';
import 'tournament_form_screen.dart';

class TournamentsScreen extends StatefulWidget {
  const TournamentsScreen({super.key});
  @override
  State<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends State<TournamentsScreen> {
  late Future<List<Map<String, dynamic>>> _future = context.api.tournaments();
  String _q = '';

  void _reload() => setState(() => _future = context.api.tournaments());

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthService>().user?.canManage ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Tournaments'), actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () async {
                final r = await context.push(const TournamentFormScreen());
                if (r != null) _reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('Tournament', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const LoadingView();
          if (s.hasError) return ErrorView(message: s.error.toString(), onRetry: _reload);
          final all = s.data!;
          final list = all.where((t) => (t['name'] ?? '').toString().toLowerCase().contains(_q.toLowerCase())).toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search tournaments'),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const SizedBox(
                  height: 380,
                  child: EmptyView(icon: Icons.emoji_events_outlined, title: 'No tournaments', subtitle: 'Create your first tournament to add teams and schedule matches.'),
                ),
              ...list.map((t) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _TournamentTile(t: t, onChanged: _reload))),
            ]),
          );
        },
      ),
    );
  }
}

class _TournamentTile extends StatelessWidget {
  const _TournamentTile({required this.t, required this.onChanged});
  final Map<String, dynamic> t;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = Fmt.parse(t['startDate']);
    final end = Fmt.parse(t['endDate']);
    final ongoing = start != null && start.isBefore(now) && (end == null || end.add(const Duration(days: 1)).isAfter(now));
    final upcoming = start != null && start.isAfter(now);
    final fmt = [t['oversFormat'] ?? t['type'], t['ballType'], Cricket.tournamentFormats[t['format']]].where((e) => e != null && '$e'.isNotEmpty).join(' • ');
    return GradientCard(
      onTap: () async {
        await context.push(TournamentDetailScreen(tournamentId: t['id'].toString()));
        onChanged();
      },
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        NetImage(t['logoUrl']?.toString(), size: 56, circle: false, fit: BoxFit.contain, fallback: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.emoji_events, color: Colors.white),
        )),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t['name']?.toString() ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text('${Fmt.date(t['startDate'])} – ${Fmt.date(t['endDate'])}', style: const TextStyle(color: AppColors.textMid, fontSize: 12.5)),
            if (fmt.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(fmt, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textLo, fontSize: 12)),
            ],
            if ((t['city'] ?? t['location'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.place_outlined, size: 13, color: AppColors.textLo),
                const SizedBox(width: 3),
                Expanded(child: Text((t['city'] ?? t['location']).toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textLo, fontSize: 12))),
              ]),
            ],
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (ongoing) const Pill('ONGOING', color: AppColors.success) else if (upcoming) const Pill('UPCOMING', color: AppColors.cyan),
          if (t['viewerCanManage'] == true) ...[const SizedBox(height: 6), const Pill('ORGANISER', color: AppColors.warning, icon: Icons.verified_user)],
        ]),
      ]),
    );
  }
}
