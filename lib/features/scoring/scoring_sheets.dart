import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/rules.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../matches/insights_view.dart';

/// Result of the wicket sheet.
class WicketInfo {
  WicketInfo({required this.type, required this.dismissedId, this.fielderIds = const [], this.fielderNames = const [], this.runs = 0, this.countBall = true});
  final String type;
  final String dismissedId;
  final List<String> fielderIds;
  final List<String> fielderNames;
  final int runs;
  final bool countBall;
}

Future<WicketInfo?> showWicketSheet(
  BuildContext context, {
  required Snapshot snap,
  required String strikerId,
  required String nonStrikerId,
  required String bowlerId,
  String? extraType,
  bool freeHit = false,
}) {
  return showModalBottomSheet<WicketInfo>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _WicketSheet(snap: snap, strikerId: strikerId, nonStrikerId: nonStrikerId, bowlerId: bowlerId, extraType: extraType, freeHit: freeHit),
  );
}

class _WicketSheet extends StatefulWidget {
  const _WicketSheet({required this.snap, required this.strikerId, required this.nonStrikerId, required this.bowlerId, this.extraType, this.freeHit = false});
  final Snapshot snap;
  final String strikerId;
  final String nonStrikerId;
  final String bowlerId;
  final String? extraType;
  final bool freeHit;
  @override
  State<_WicketSheet> createState() => _WicketSheetState();
}

class _WicketSheetState extends State<_WicketSheet> {
  String? type;
  late String outId = widget.strikerId;
  final fielders = <String>[];
  int runs = 0;
  bool countBall = false;

  List<String> get allowedTypes {
    final ex = widget.extraType;
    // Free hit: only the dismissals possible off a no-ball remain (no bowled / caught / lbw / stumped / hit wicket).
    if (widget.freeHit) return ['run out', 'obstructing the ball', 'hit the ball twice', 'retired hurt', 'retired out', 'retired', 'absent hurt'];
    if (ex == 'WD') return ['stumped', 'run out', 'hit wicket', 'obstructing the ball', 'run out (mankaded)', 'retired hurt', 'retired out'];
    if (ex == 'NB') return ['run out', 'obstructing the ball', 'hit the ball twice', 'retired hurt', 'retired out'];
    if (ex == 'B' || ex == 'LB') return ['run out', 'obstructing the ball', 'retired hurt', 'retired out'];
    return Cricket.dismissalTypes.keys.toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snap;
    final fieldXi = s.xiFor(s.bowlingTeamId);
    final keeper = fieldXi.where((x) => x['isKeeper'] == true).firstOrNull;
    final needF = type != null && Cricket.needsFielder(type!);
    final multi = type == 'run out';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        const Text('Wicket', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.wicket)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in allowedTypes)
            ChoiceChip(
              label: Text(Cricket.dismissalTypes[t] ?? t),
              selected: type == t,
              selectedColor: AppColors.wicket.withValues(alpha: 0.3),
              onSelected: (_) => setState(() {
                type = t;
                fielders.clear();
                if (Cricket.isKeeperDismissal(t) && keeper != null) fielders.add(keeper['playerId'].toString());
                if (!Cricket.canDismissNonStriker(t)) outId = widget.strikerId;
                countBall = !Cricket.isRetirement(t);
              }),
            ),
        ]),
        if (type != null && Cricket.canDismissNonStriker(type!)) ...[
          const SectionTitle('Who is out?', padding: EdgeInsets.fromLTRB(0, 18, 0, 8)),
          Row(children: [
            for (final id in [widget.strikerId, widget.nonStrikerId])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text('${s.playerName(id)}${id == widget.strikerId ? ' (striker)' : ''}', overflow: TextOverflow.ellipsis),
                    selected: outId == id,
                    onSelected: (_) => setState(() => outId = id),
                  ),
                ),
              ),
          ]),
        ],
        if (needF) ...[
          SectionTitle(multi ? 'Fielder(s) involved' : (type == 'stumped' || type == 'caught behind' ? 'Wicket-keeper' : 'Fielder'), padding: const EdgeInsets.fromLTRB(0, 18, 0, 8)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in fieldXi)
              FilterChip(
                avatar: x['isKeeper'] == true ? const Icon(Icons.sports_handball, size: 16) : null,
                label: Text(asMap(x['player'])['name']?.toString() ?? '-'),
                selected: fielders.contains(x['playerId'].toString()),
                onSelected: (v) => setState(() {
                  final id = x['playerId'].toString();
                  if (!multi) fielders.clear();
                  v ? fielders.add(id) : fielders.remove(id);
                }),
              ),
          ]),
        ],
        if (type != null && Cricket.isRunOut(type!)) ...[
          const SectionTitle('Runs completed before the run out', padding: EdgeInsets.fromLTRB(0, 18, 0, 8)),
          Wrap(spacing: 8, children: [
            for (var r = 0; r <= 4; r++) ChoiceChip(label: Text('$r'), selected: runs == r, onSelected: (_) => setState(() => runs = r)),
          ]),
        ],
        if (type != null && Cricket.isRetirement(type!))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: countBall,
            title: const Text('Count this as a ball'),
            subtitle: const Text('Usually No — a retirement happens when the ball is dead'),
            onChanged: (v) => setState(() => countBall = v),
          ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.wicket),
          // Catches and stumpings need a fielder; run outs may be recorded without one.
          onPressed: type == null || ((type == 'caught' || type == 'stumped') && fielders.isEmpty)
              ? null
              : () {
                  final names = fielders.map((id) => s.playerName(id)).toList();
                  Navigator.pop(
                    context,
                    WicketInfo(
                      type: type == 'c&b' ? 'caught' : type!,
                      dismissedId: outId,
                      fielderIds: type == 'c&b' ? [widget.bowlerId] : List.of(fielders),
                      fielderNames: names,
                      runs: runs,
                      countBall: countBall,
                    ),
                  );
                },
          child: const Text('Confirm wicket'),
        ),
      ]),
    );
  }
}

/// Pick a player from a list with stats subtitle; returns the player id.
Future<String?> pickPlayer(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> xi,
  String Function(Map<String, dynamic>)? subtitle,
  bool Function(Map<String, dynamic>)? disabled,
}) async {
  final r = await pickFromList(
    context,
    title: title,
    items: xi,
    label: (x) => asMap(x['player'])['name']?.toString() ?? '-',
    subtitle: subtitle,
    leading: (x) => PlayerAvatar(name: asMap(x['player'])['name']?.toString() ?? '?', imageUrl: asMap(x['player'])['imageUrl']?.toString(), size: 36),
    disabled: disabled,
  );
  return r?['playerId']?.toString();
}

/// Tap-on-field wagon wheel capture. Returns the stored (RHB-convention) angle, distance and shot name.
Future<({double angle, double distance, String? shotName})?> showWagonPicker(BuildContext context, {required int runs, required String batter, String? hand}) {
  return showModalBottomSheet<({double angle, double distance, String? shotName})>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _WagonPicker(runs: runs, batter: batter, hand: hand),
  );
}

class _WagonPicker extends StatefulWidget {
  const _WagonPicker({required this.runs, required this.batter, this.hand});
  final int runs;
  final String batter;
  final String? hand;
  @override
  State<_WagonPicker> createState() => _WagonPickerState();
}

class _WagonPickerState extends State<_WagonPicker> {
  Offset? tap;
  /// Angle in the stored RHB convention (mirrored from the screen for left-handers).
  double? displayAngle;
  double distance = 0.6;
  String? shot;

  bool get lhb => widget.hand == 'LHB';

  @override
  Widget build(BuildContext context) {
    final area = displayAngle == null ? null : fieldingArea(displayAngle!, distance);
    final shots = displayAngle == null ? const <String>[] : shotsNear(displayAngle!).take(6).toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Where did ${widget.batter} hit the ${widget.runs}?', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          Text('Bowler end at the bottom • ${lhb ? 'Left-hander: off side on the RIGHT' : 'Right-hander: off side on the LEFT'}',
              style: const TextStyle(color: AppColors.textMid, fontSize: 12)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (c, cons) {
            final size = Size.square(cons.maxWidth.clamp(0, 300).toDouble());
            return Stack(children: [
              GestureDetector(
                onTapDown: (d) => setState(() {
                  final p = wagonPolarFromOffset(d.localPosition, size);
                  // Screen angle is what the scorer sees; RHB convention stores the mirrored angle for LHB.
                  displayAngle = lhb ? mirrorForHand(p.angle, 'LHB') : p.angle;
                  distance = widget.runs >= 4 ? 1.0 : p.distance;
                  tap = d.localPosition;
                  shot = null;
                }),
                child: SizedBox.fromSize(size: size, child: CustomPaint(painter: WagonWheelPainter(const [], highlight: tap))),
              ),
              Positioned(left: 6, top: size.height / 2 - 8, child: Text(lhb ? 'LEG' : 'OFF', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white70))),
              Positioned(right: 6, top: size.height / 2 - 8, child: Text(lhb ? 'OFF' : 'LEG', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white70))),
            ]);
          }),
          if (area != null) ...[
            const SizedBox(height: 8),
            Text(area, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.cyan)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              for (final s in shots) ChoiceChip(label: Text(s), selected: shot == s, onSelected: (_) => setState(() => shot = shot == s ? null : s)),
            ]),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Skip'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: displayAngle == null
                    ? null
                    : () => Navigator.pop(context, (angle: displayAngle!, distance: distance, shotName: shot)),
                child: const Text('Save shot'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
