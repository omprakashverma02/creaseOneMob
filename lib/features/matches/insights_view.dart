import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _inningsColors = [Color(0xFF2F6BFF), Color(0xFFF59E0B), Color(0xFF22D3EE), Color(0xFFEC4899)];

/// Match analytics (web MatchGraphs + ScoreboardInsights): worm, manhattan,
/// run rate, partnerships, run breakdown, dismissals and wagon wheel.
class InsightsView extends StatefulWidget {
  const InsightsView({super.key, required this.matchId, this.refreshKey = 0});
  final String matchId;
  final int refreshKey;
  @override
  State<InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends State<InsightsView> {
  late Future<Map<String, dynamic>?> _future = context.api.insights(widget.matchId);
  String? wagonInnings;

  @override
  void didUpdateWidget(covariant InsightsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) _future = context.api.insights(widget.matchId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done && !s.hasData) return const LoadingView();
        final d = s.data;
        final overSummary = asMap(d?['overSummary']);
        if (d == null || overSummary.isEmpty) {
          return const EmptyView(icon: Icons.insights_outlined, title: 'No insights yet', subtitle: 'Charts appear after the first over is bowled.');
        }
        final innMeta = asMap(d['innings']);
        final keys = overSummary.keys.toList()..sort();
        String label(String k) {
          final m = asMap(innMeta[k]);
          return '${m['battingTeamShort'] ?? m['battingTeamName'] ?? 'Inns $k'}';
        }

        return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
          _legend(keys, label),
          _chartCard('Worm — cumulative runs', _worm(overSummary, keys)),
          _chartCard('Manhattan — runs per over', _manhattan(overSummary, keys)),
          _chartCard('Run rate by over', _runRate(overSummary, keys)),
          ..._partnerships(asMap(d['partnerships']), keys, label),
          _breakdown(asMap(d['teamRunBreakdown']), keys, label),
          _dismissals(asMap(d['dismissals'])),
          _wagon(asMap(d['wagonShots']), keys, label),
          _milestones(asMapList(d['fastestFifty']), 'Fastest fifties'),
          _milestones(asMapList(d['fastestHundred']), 'Fastest hundreds'),
        ]);
      },
    );
  }

  Widget _legend(List<String> keys, String Function(String) label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(spacing: 14, children: [
          for (var i = 0; i < keys.length; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 5, backgroundColor: _inningsColors[i % 4]),
              const SizedBox(width: 6),
              Text(label(keys[i]), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
        ]),
      );

  Widget _chartCard(String title, Widget chart, {double height = 220}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              SizedBox(height: height, child: chart),
            ]),
          ),
        ),
      );

  FlTitlesData _titles({String Function(double)? bottom}) => FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: AppColors.textLo)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (v, m) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(bottom?.call(v) ?? v.toInt().toString(), style: const TextStyle(fontSize: 10, color: AppColors.textLo)),
            ),
          ),
        ),
      );

  FlGridData get _grid => FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
      );

  Widget _worm(Map<String, dynamic> os, List<String> keys) {
    final bars = <LineChartBarData>[];
    for (var i = 0; i < keys.length; i++) {
      final rows = asMapList(os[keys[i]]);
      final spots = [const FlSpot(0, 0), ...rows.map((r) => FlSpot(asDouble(r['over']), asDouble(r['cumulativeRuns'])))];
      bars.add(LineChartBarData(
        spots: spots,
        color: _inningsColors[i % 4],
        barWidth: 3,
        isCurved: true,
        preventCurveOverShooting: true,
        dotData: FlDotData(
          show: true,
          checkToShowDot: (spot, bar) {
            final r = rows.where((x) => asDouble(x['over']) == spot.x).firstOrNull;
            return r != null && asInt(r['wickets']) > 0;
          },
          getDotPainter: (a, b, c, d) => FlDotCirclePainter(radius: 4, color: AppColors.wicket, strokeColor: Colors.white, strokeWidth: 1),
        ),
      ));
    }
    return LineChart(LineChartData(lineBarsData: bars, titlesData: _titles(), gridData: _grid, borderData: FlBorderData(show: false), minY: 0));
  }

  Widget _manhattan(Map<String, dynamic> os, List<String> keys) {
    final maxOver = keys.fold<int>(0, (a, k) => math.max(a, asMapList(os[k]).fold<int>(0, (x, r) => math.max(x, asInt(r['over'])))));
    final groups = <BarChartGroupData>[];
    for (var o = 1; o <= maxOver; o++) {
      final rods = <BarChartRodData>[];
      for (var i = 0; i < keys.length && i < 2; i++) {
        final r = asMapList(os[keys[i]]).where((x) => asInt(x['over']) == o).firstOrNull;
        final w = asInt(r?['wickets']);
        rods.add(BarChartRodData(
          toY: asDouble(r?['runs']),
          color: w > 0 ? AppColors.wicket : _inningsColors[i % 4],
          width: keys.length > 1 ? 5 : 9,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ));
      }
      groups.add(BarChartGroupData(x: o, barRods: rods, barsSpace: 2));
    }
    return BarChart(BarChartData(
      barGroups: groups,
      titlesData: _titles(bottom: (v) => v.toInt() % (maxOver > 20 ? 5 : 2) == 0 ? '${v.toInt()}' : ''),
      gridData: _grid,
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(enabled: true),
    ));
  }

  Widget _runRate(Map<String, dynamic> os, List<String> keys) {
    final bars = <LineChartBarData>[];
    for (var i = 0; i < keys.length; i++) {
      final rows = asMapList(os[keys[i]]);
      bars.add(LineChartBarData(
        spots: rows.map((r) => FlSpot(asDouble(r['over']), asDouble(r['runRate']))).toList(),
        color: _inningsColors[i % 4],
        barWidth: 2.5,
        isCurved: true,
        preventCurveOverShooting: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: _inningsColors[i % 4].withValues(alpha: 0.08)),
      ));
    }
    return LineChart(LineChartData(lineBarsData: bars, titlesData: _titles(), gridData: _grid, borderData: FlBorderData(show: false), minY: 0));
  }

  List<Widget> _partnerships(Map<String, dynamic> ps, List<String> keys, String Function(String) label) {
    final out = <Widget>[];
    for (final k in keys) {
      final rows = asMapList(ps[k]);
      if (rows.isEmpty) continue;
      final maxRuns = rows.fold<int>(1, (a, r) => math.max(a, asInt(r['runs'])));
      out.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Partnerships — ${label(k)}', style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text('${r['bat1']} & ${r['bat2']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                      Text('${asInt(r['runs'])} (${asInt(r['balls'])})', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: asInt(r['runs']) / maxRuns,
                        minHeight: 7,
                        backgroundColor: AppColors.surfaceHigh,
                        color: AppColors.primary,
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ));
    }
    return out;
  }

  Widget _breakdown(Map<String, dynamic> br, List<String> keys, String Function(String) label) {
    final present = keys.where((k) => asMap(br[k]).isNotEmpty).toList();
    if (present.isEmpty) return const SizedBox.shrink();
    const cats = [('dots', 'Dots', AppColors.dot), ('ones', '1s', Color(0xFF64748B)), ('twos', '2s', Color(0xFF0EA5E9)), ('threes', '3s', Color(0xFF14B8A6)), ('fours', '4s', AppColors.four), ('sixes', '6s', AppColors.six)];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Scoring breakdown', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Table(
              columnWidths: const {0: FlexColumnWidth(1.4)},
              children: [
                TableRow(children: [
                  const SizedBox(),
                  for (final c in cats) Center(child: Text(c.$2, style: TextStyle(fontWeight: FontWeight.w900, color: c.$3 == AppColors.dot ? AppColors.textMid : c.$3, fontSize: 12))),
                ]),
                for (final k in present)
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(label(k), style: const TextStyle(fontWeight: FontWeight.w800))),
                    for (final c in cats)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: Text('${asInt(asMap(br[k])[c.$1])}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      ),
                  ]),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _dismissals(Map<String, dynamic> ds) {
    final rows = asMapList(ds['both']);
    if (rows.isEmpty) return const SizedBox.shrink();
    const palette = [Color(0xFFEF4444), Color(0xFFF59E0B), Color(0xFF22D3EE), Color(0xFFA855F7), Color(0xFF22C55E), Color(0xFF3B82F6), Color(0xFFEC4899)];
    return _chartCard(
      'How wickets fell',
      Row(children: [
        Expanded(
          child: PieChart(PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 34,
            sections: [
              for (var i = 0; i < rows.length; i++)
                PieChartSectionData(
                  value: asDouble(rows[i]['count']),
                  color: palette[i % palette.length],
                  title: '${asInt(rows[i]['count'])}',
                  radius: 46,
                  titleStyle: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                ),
            ],
          )),
        ),
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                CircleAvatar(radius: 5, backgroundColor: palette[i % palette.length]),
                const SizedBox(width: 6),
                Text(Cricket.dismissalTypes[rows[i]['type']] ?? '${rows[i]['type']}', style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
        ]),
      ]),
      height: 180,
    );
  }

  Widget _wagon(Map<String, dynamic> ws, List<String> keys, String Function(String) label) {
    final present = keys.where((k) => asMapList(ws[k]).isNotEmpty).toList();
    if (present.isEmpty) return const SizedBox.shrink();
    final sel = present.contains(wagonInnings) ? wagonInnings! : present.first;
    final shots = asMapList(ws[sel]);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Wagon wheel', style: TextStyle(fontWeight: FontWeight.w900))),
              for (final k in present)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(label: Text(label(k)), selected: k == sel, onSelected: (_) => setState(() => wagonInnings = k)),
                ),
            ]),
            const SizedBox(height: 12),
            AspectRatio(aspectRatio: 1, child: CustomPaint(painter: WagonWheelPainter(shots))),
            const SizedBox(height: 8),
            const Wrap(spacing: 12, children: [
              _Lg(AppColors.six, '6s'),
              _Lg(AppColors.four, '4s'),
              _Lg(Color(0xFFE2E8F0), '1-3s'),
              _Lg(AppColors.wicket, 'Wicket'),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _milestones(List<Map<String, dynamic>> rows, String title) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 4), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
          for (final r in rows)
            ListTile(
              dense: true,
              title: Text('${r['playerName']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${r['teamName'] ?? ''}'),
              trailing: Text('${r['balls']} balls', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan)),
            ),
        ]),
      ),
    );
  }
}

class _Lg extends StatelessWidget {
  const _Lg(this.c, this.t);
  final Color c;
  final String t;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 3, color: c),
        const SizedBox(width: 5),
        Text(t, style: const TextStyle(fontSize: 12, color: AppColors.textMid)),
      ]);
}

/// Converts a tap on the wagon wheel into the web's stored polar form.
({double angle, double distance}) wagonPolarFromOffset(Offset local, Size size) {
  final c = size.center(Offset.zero);
  final dx = local.dx - c.dx;
  final dy = local.dy - c.dy;
  var deg = math.atan2(dy, dx) * 180 / math.pi - 90;
  if (deg < 0) deg += 360;
  final maxPx = size.shortestSide / 2;
  final dist = (math.sqrt(dx * dx + dy * dy) / (maxPx * 0.92)).clamp(0.1, 1.0);
  return (angle: deg.roundToDouble() % 360, distance: (dist * 100).round() / 100);
}

/// Shared field painter. `angle` is degrees from straight (bowler end) as stored by the web.
class WagonWheelPainter extends CustomPainter {
  WagonWheelPainter(this.shots, {this.highlight});
  final List<Map<String, dynamic>> shots;
  final Offset? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF14532D));
    canvas.drawCircle(c, r * 0.97, Paint()..color = const Color(0xFF166534));
    canvas.drawCircle(
        c,
        r * 0.55,
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: r * 0.1, height: r * 0.34), const Radius.circular(3)),
      Paint()..color = const Color(0xFFD6C08A),
    );
    for (final s in shots) {
      final angle = asDouble(s['angle']);
      final distRaw = s['distance'];
      final runs = asInt(s['runs']);
      final dist = distRaw == null ? (runs >= 4 ? 1.0 : 0.3 + runs * 0.15) : (asDouble(distRaw) > 1 ? asDouble(distRaw) / 100 : asDouble(distRaw));
      // Web convention: 0° = straight down the ground (bowler end at bottom), 90° = off side (left).
      final rad = angle * math.pi / 180;
      final end = c + Offset(-math.sin(rad), math.cos(rad)) * (r * dist.clamp(0.08, 0.98));
      Color col;
      if (s['isWicket'] == true) {
        col = AppColors.wicket;
      } else if (runs >= 6) {
        col = AppColors.six;
      } else if (runs == 4) {
        col = AppColors.four;
      } else {
        col = const Color(0xFFE2E8F0);
      }
      canvas.drawLine(c, end, Paint()
        ..color = col
        ..strokeWidth = runs >= 4 ? 2.4 : 1.6
        ..strokeCap = StrokeCap.round);
    }
    if (highlight != null) {
      canvas.drawLine(c, highlight!, Paint()
        ..color = AppColors.cyan
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round);
      canvas.drawCircle(highlight!, 6, Paint()..color = AppColors.cyan);
    }
  }

  @override
  bool shouldRepaint(covariant WagonWheelPainter old) => old.shots != shots || old.highlight != highlight;
}
