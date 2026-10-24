import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../widgets/common.dart';

/// International & franchise cricket feed (via the backend's /api/world proxy),
/// shown next to CreaseOne platform matches — Cricbuzz-style.
class WorldFeedView extends StatefulWidget {
  const WorldFeedView({super.key});
  @override
  State<WorldFeedView> createState() => _WorldFeedViewState();
}

class _WorldFeedViewState extends State<WorldFeedView> with AutomaticKeepAliveClientMixin {
  late Future<Map<String, dynamic>> _future = context.api.worldMatches();
  String filter = 'all';
  Timer? _timer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Live scores refresh; the backend caches to respect the provider's quota.
    _timer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (mounted) setState(() => _future = context.api.worldMatches());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _future = context.api.worldMatches());
    await _future.catchError((_) => <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done && !s.hasData) return const LoadingView(label: 'Fetching world cricket…');
        if (s.hasError) {
          final e = s.error;
          final notConfigured = e is ApiException && e.statusCode == 503;
          return notConfigured
              ? const EmptyView(
                  icon: Icons.public_off_outlined,
                  title: 'World cricket feed not enabled',
                  subtitle: 'Your organiser needs to add a CricketData.org API key (CRICAPI_KEY) to the CreaseOne server.',
                )
              : ErrorView(message: e.toString(), onRetry: _reload);
        }
        final all = asMapList(s.data?['matches']);
        final types = {'all', ...all.map((m) => (m['matchType'] ?? '').toString().toLowerCase()).where((t) => t.isNotEmpty)};
        final list = all.where((m) => filter == 'all' || (m['matchType'] ?? '').toString().toLowerCase() == filter).toList();
        final live = list.where((m) => m['state'] == 'live').toList();
        final upcoming = list.where((m) => m['state'] == 'upcoming').toList();
        final done = list.where((m) => m['state'] == 'result').toList();
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final t in types)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(t == 'all' ? 'All formats' : t.toUpperCase()), selected: filter == t, onSelected: (_) => setState(() => filter = t)),
                  ),
              ]),
            ),
            if (list.isEmpty) const SizedBox(height: 320, child: EmptyView(icon: Icons.public, title: 'No international matches right now')),
            if (live.isNotEmpty) ...[const SectionTitle('Live', padding: EdgeInsets.fromLTRB(0, 10, 0, 8)), for (final m in live) WorldMatchCard(m: m)],
            if (upcoming.isNotEmpty) ...[const SectionTitle('Upcoming', padding: EdgeInsets.fromLTRB(0, 16, 0, 8)), for (final m in upcoming.take(25)) WorldMatchCard(m: m)],
            if (done.isNotEmpty) ...[const SectionTitle('Recent results', padding: EdgeInsets.fromLTRB(0, 16, 0, 8)), for (final m in done.take(25)) WorldMatchCard(m: m)],
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('International data: CricketData.org', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textLo, fontSize: 11)),
            ),
          ]),
        );
      },
    );
  }
}

class WorldMatchCard extends StatelessWidget {
  const WorldMatchCard({super.key, required this.m});
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final teams = asMapList(m['teams']);
    final state = m['state']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GradientCard(
        padding: const EdgeInsets.all(12),
        onTap: () => context.push(WorldMatchScreen(id: m['id'].toString(), title: m['name']?.toString() ?? 'Match')),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${m['matchType'] ?? ''} • ${m['name'] ?? ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMid, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            if (state == 'live') const LiveDot() else if (state == 'result') const Pill('RESULT', color: AppColors.success) else const Pill('UPCOMING', color: AppColors.cyan),
          ]),
          const SizedBox(height: 8),
          for (final t in teams)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                TeamBadge(name: t['name']?.toString() ?? '', logoUrl: t['logoUrl']?.toString(), size: 26),
                const SizedBox(width: 10),
                Expanded(child: Text(t['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                Text(t['score']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w900)),
              ]),
            ),
          const SizedBox(height: 6),
          Text(
            state == 'upcoming' && m['dateTimeGMT'] != null ? '${Fmt.dateTime(m['dateTimeGMT'])}${(m['venue'] ?? '').toString().isNotEmpty ? ' • ${m['venue']}' : ''}' : '${m['status'] ?? ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: state == 'result' ? AppColors.cyan : (state == 'live' ? AppColors.warning : AppColors.textMid), fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ]),
      ),
    );
  }
}

class WorldMatchScreen extends StatefulWidget {
  const WorldMatchScreen({super.key, required this.id, required this.title});
  final String id;
  final String title;
  @override
  State<WorldMatchScreen> createState() => _WorldMatchScreenState();
}

class _WorldMatchScreenState extends State<WorldMatchScreen> {
  late Future<Map<String, dynamic>> _future = context.api.worldMatch(widget.id);
  int inningsIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis), actions: [
        IconButton(onPressed: () => setState(() => _future = context.api.worldMatch(widget.id)), icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: AsyncBuilder<Map<String, dynamic>>(
        future: _future,
        onRetry: () => setState(() => _future = context.api.worldMatch(widget.id)),
        builder: (c, d) {
          final m = asMap(d['match']);
          final teams = asMapList(m['teams']);
          final innings = asMapList(d['innings']);
          final idx = innings.isEmpty ? 0 : inningsIndex.clamp(0, innings.length - 1);
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
            GradientCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m['matchType'] ?? ''} • ${m['venue'] ?? ''}', style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
                const SizedBox(height: 10),
                for (final t in teams)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      TeamBadge(name: t['name']?.toString() ?? '', logoUrl: t['logoUrl']?.toString(), size: 36),
                      const SizedBox(width: 12),
                      Expanded(child: Text(t['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                      Text(t['score']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ]),
                  ),
                const SizedBox(height: 8),
                Text('${m['status'] ?? ''}', style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800)),
                if (d['tossWinner'] != null)
                  Text('Toss: ${d['tossWinner']} chose to ${d['tossChoice'] ?? ''}', style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
              ]),
            ),
            if (innings.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(icon: Icons.list_alt_rounded, title: 'Scorecard not available yet')),
            if (innings.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (var i = 0; i < innings.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text('${innings[i]['title']}'), selected: idx == i, onSelected: (_) => setState(() => inningsIndex = i)),
                    ),
                ]),
              ),
              _inningsCard(innings[idx]),
            ],
          ]);
        },
      ),
    );
  }

  Widget _inningsCard(Map<String, dynamic> inn) {
    const head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.textMid);
    Widget n(Object? v, {double w = 34, bool bold = false}) =>
        SizedBox(width: w, child: Text('${v ?? '-'}', textAlign: TextAlign.right, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600)));
    return Column(children: [
      Card(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(children: [
              const Expanded(child: Text('BATTER', style: head)),
              for (final h in ['R', 'B', '4s', '6s']) SizedBox(width: 34, child: Text(h, textAlign: TextAlign.right, style: head)),
              const SizedBox(width: 50, child: Text('SR', textAlign: TextAlign.right, style: head)),
            ]),
          ),
          const Divider(),
          for (final b in asMapList(inn['batting']))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('${b['dismissal']}', style: const TextStyle(color: AppColors.textMid, fontSize: 11.5)),
                  ]),
                ),
                n(b['runs'], bold: true),
                n(b['balls']),
                n(b['fours']),
                n(b['sixes']),
                n(b['sr'], w: 50),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Card(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(children: [
              const Expanded(child: Text('BOWLER', style: head)),
              for (final h in ['O', 'M', 'R', 'W']) SizedBox(width: 34, child: Text(h, textAlign: TextAlign.right, style: head)),
              const SizedBox(width: 46, child: Text('ECO', textAlign: TextAlign.right, style: head)),
            ]),
          ),
          const Divider(),
          for (final b in asMapList(inn['bowling']))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                Expanded(child: Text('${b['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                n(b['overs']),
                n(b['maidens']),
                n(b['runs']),
                n(b['wickets'], bold: true),
                n(b['economy'], w: 46),
              ]),
            ),
        ]),
      ),
    ]);
  }
}
