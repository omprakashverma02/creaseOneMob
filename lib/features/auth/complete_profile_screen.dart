import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';

/// First Google sign-in: pick a role (and player details when role = player).
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});
  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  String role = 'broadcaster';
  final phone = TextEditingController();
  final playerName = TextEditingController();
  final shortName = TextEditingController();
  String playerRole = 'batsman';
  String batting = 'RHB';
  String bowling = 'None';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthService>().pendingUser;
    playerName.text = u?['name']?.toString() ?? '';
  }

  static const _roleIcons = {
    'broadcaster': Icons.emoji_events_outlined,
    'player': Icons.sports_cricket,
    'umpire': Icons.sports,
    'referee': Icons.gavel_rounded,
    'commentator': Icons.mic_none_rounded,
  };

  static const _roleDesc = {
    'broadcaster': 'Create tournaments, teams & matches and score them live',
    'player': 'Track your batting & bowling stats across matches',
    'umpire': 'Officiate matches and follow live scores',
    'referee': 'Oversee matches and review results',
    'commentator': 'Follow ball-by-ball data while you commentate',
  };

  Future<void> _submit() async {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      context.toast('Enter a valid 10 digit mobile number', error: true);
      return;
    }
    if (role == 'player' && playerName.text.trim().isEmpty) {
      context.toast('Player name is required', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      await context.auth.completeProfile(
        role: role,
        contactNumber: digits,
        playerData: role == 'player'
            ? {
                'name': playerName.text.trim(),
                'shortName': shortName.text.trim(),
                'mobileNumber': digits,
                'countryCode': '+91',
                'role': playerRole,
                'battingStyle': batting,
                'bowlingStyle': bowling == 'None' ? null : bowling,
              }
            : null,
      );
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<AuthService>().pendingUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete your profile'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.auth.cancelProfile()),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Welcome${u?['name'] != null ? ', ${u!['name']}' : ''}!', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(u?['email']?.toString() ?? '', style: const TextStyle(color: AppColors.textMid)),
        const SectionTitle('How will you use CreaseOne?', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
        ...AuthUser.roles.entries.where((e) => e.key != 'admin').map((e) {
          final sel = role == e.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GradientCard(
              onTap: () => setState(() => role = e.key),
              gradient: sel ? LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.35), AppColors.surface]) : null,
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(_roleIcons[e.key] ?? Icons.person, color: sel ? AppColors.cyan : AppColors.textMid),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(_roleDesc[e.key] ?? '', style: const TextStyle(color: AppColors.textMid, fontSize: 12.5)),
                  ]),
                ),
                if (sel) const Icon(Icons.check_circle, color: AppColors.cyan),
              ]),
            ),
          );
        }),
        const SizedBox(height: 8),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 ')),
        if (role == 'player') ...[
          const SectionTitle('Player details', padding: EdgeInsets.fromLTRB(0, 20, 0, 10)),
          TextField(controller: playerName, decoration: const InputDecoration(labelText: 'Player name')),
          const SizedBox(height: 10),
          TextField(controller: shortName, decoration: const InputDecoration(labelText: 'Short name (scorecard)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: playerRole,
            decoration: const InputDecoration(labelText: 'Playing role'),
            items: Cricket.playerRoles.map((r) => DropdownMenuItem(value: r, child: Text(Cricket.roleLabel(r)))).toList(),
            onChanged: (v) => setState(() => playerRole = v ?? playerRole),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: batting,
                decoration: const InputDecoration(labelText: 'Batting'),
                items: Cricket.battingStyles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setState(() => batting = v ?? batting),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: bowling,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bowling'),
                items: Cricket.bowlingStyles.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => bowling = v ?? bowling),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Continue'),
        ),
      ]),
    );
  }
}
