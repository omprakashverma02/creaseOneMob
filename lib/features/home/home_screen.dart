import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import '../../widgets/match_card.dart';
import '../matches/create_match_screen.dart';
import '../matches/match_detail_screen.dart';
import '../tournaments/tournament_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  List<MatchView>? _matches;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.api.matches();
      if (!mounted) return;
      setState(() {
        _matches = list.map(MatchView.new).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _openBySeq() async {
    final v = await promptText(context, title: 'Open match', hint: 'Match # e.g. 128', keyboard: TextInputType.number);
    if (v == null || v.isEmpty || !mounted) return;
    final seq = int.tryParse(v);
    try {
      final id = seq != null ? (await context.api.matchBySeq(seq))['id']?.toString() : v;
      if (id == null) throw Exception('Match not found');
      if (mounted) await context.push(MatchDetailScreen(matchId: id));
      _load();
    } catch (e) {
      if (mounted) context.toast('Match not found', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final all = _matches ?? const <MatchView>[];
    final live = all.where((m) => m.isLive).toList();
    final upcoming = all.where((m) => m.status == 'scheduled').toList()
      ..sort((a, b) => (Fmt.parse(a.scheduledAt) ?? DateTime(2100)).compareTo(Fmt.parse(b.scheduledAt) ?? DateTime(2100)));
    final done = all.where((m) => m.isCompleted).toList()
      ..sort((a, b) => (Fmt.parse(b.raw['endedAt'] ?? b.scheduledAt) ?? DateTime(1970)).compareTo(Fmt.parse(a.raw['endedAt'] ?? a.scheduledAt) ?? DateTime(1970)));

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (c, _) => [
          SliverAppBar(
            pinned: true,
            floating: true,
            titleSpacing: 12,
            title: Row(children: [
              Image.asset('assets/images/logo.png', height: 34),
              const SizedBox(width: 10),
              const Text('CreaseOne'),
            ]),
            actions: [
              IconButton(tooltip: 'Open match #', onPressed: _openBySeq, icon: const Icon(Icons.search_rounded)),
              IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
            ],
            bottom: TabBar(
              controller: _tabs,
              tabAlignment: TabAlignment.fill,
              tabs: [
                Tab(text: 'Live${live.isNotEmpty ? ' (${live.length})' : ''}'),
                Tab(text: 'Upcoming${upcoming.isNotEmpty ? ' (${upcoming.length})' : ''}'),
                const Tab(text: 'Results'),
              ],
            ),
          ),
        ],
        body: _matches == null && _error == null
            ? const LoadingView()
            : _error != null && _matches == null
                ? ErrorView(message: _error!, onRetry: _load)
                : TabBarView(controller: _tabs, children: [
                    _list(live, 'No live matches', 'Start scoring a scheduled match to see it here.', header: _hero(user)),
                    _list(upcoming, 'No upcoming matches', 'Create a match to schedule it.'),
                    _list(done, 'No results yet', 'Completed matches will appear here.'),
                  ]),
      ),
      floatingActionButton: (user?.canManage ?? false)
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await context.push<bool>(const CreateMatchScreen());
                if (created == true) _load();
              },
              icon: const Icon(Icons.add),
              label: const Text('New match', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
    );
  }

  Widget _hero(AuthUser? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hi ${user?.name ?? 'there'} 👋', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 4),
              const Text('Ready for the next ball? Score live, share instantly.', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
              if (user?.canManage ?? false) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _heroBtn(Icons.add_circle_outline, 'Match', () async {
                    final created = await context.push<bool>(const CreateMatchScreen());
                    if (created == true) _load();
                  }),
                  _heroBtn(Icons.emoji_events_outlined, 'Tournament', () => context.push(const TournamentFormScreen())),
                ]),
              ],
            ]),
          ),
          const Icon(Icons.sports_cricket, size: 64, color: Colors.white24),
        ]),
      ),
    );
  }

  Widget _heroBtn(IconData i, String t, VoidCallback onTap) => Material(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
          ),
        ),
      );

  Widget _list(List<MatchView> items, String emptyTitle, String emptySub, {Widget? header}) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: (header != null ? 1 : 0) + (items.isEmpty ? 1 : items.length),
        separatorBuilder: (_, __) => const SizedBox(height: 0),
        itemBuilder: (c, i) {
          if (header != null && i == 0) return header;
          final idx = i - (header != null ? 1 : 0);
          if (items.isEmpty) {
            return SizedBox(height: 360, child: EmptyView(icon: Icons.sports_cricket, title: emptyTitle, subtitle: emptySub));
          }
          final m = items[idx];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: MatchCard(
              match: m,
              onTap: () async {
                await context.push(MatchDetailScreen(matchId: m.id));
                _load();
              },
            ),
          );
        },
      ),
    );
  }
}
