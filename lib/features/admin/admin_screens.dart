import 'package:flutter/material.dart';

import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../matches/match_detail_screen.dart';
import '../tools/excel_import.dart';
import '../tournaments/tournament_admin_screen.dart';

/// Admin dashboard (web AdminDashboard.tsx): users and roles.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String role = 'all';
  String q = '';
  late Future<List<Map<String, dynamic>>> f = _load();
  Future<List<Map<String, dynamic>>> _load() => context.api.users(role: role == 'all' ? null : role, q: q.isEmpty ? null : q);
  void _reload() => setState(() => f = _load());

  Future<void> _editRole(Map<String, dynamic> u) async {
    final r = await pickFromList(context, title: 'Role for ${u['name'] ?? u['email']}', items: [
      for (final e in AuthUser.roles.entries) {'k': e.key, 'v': e.value},
    ], label: (m) => m['v']);
    if (r == null || !mounted) return;
    try {
      await context.api.updateUser(u['id'].toString(), {'role': r['k']});
      _reload();
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    String newRole = 'broadcaster';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('New user'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 8),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: newRole,
              items: AuthUser.roles.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setS(() => newRole = v ?? newRole),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.api.createUser({'name': name.text.trim(), 'email': email.text.trim(), 'contactNumber': phone.text.trim(), 'role': newRole});
      _reload();
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin — users')),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(Icons.person_add_alt_1)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, email or mobile'),
            onSubmitted: (v) {
              q = v.trim();
              _reload();
            },
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final r in ['all', ...AuthUser.roles.keys, 'pending'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(r == 'all' ? 'All' : (AuthUser.roles[r] ?? r)),
                  selected: role == r,
                  onSelected: (_) {
                    role = r;
                    _reload();
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: AsyncBuilder<List<Map<String, dynamic>>>(
            future: f,
            onRetry: _reload,
            builder: (c, users) => users.isEmpty
                ? const EmptyView(icon: Icons.people_outline, title: 'No users')
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const Divider(indent: 72),
                    itemBuilder: (c, i) {
                      final u = users[i];
                      return ListTile(
                        leading: PlayerAvatar(name: '${u['name'] ?? u['email']}', size: 40),
                        title: Text('${u['name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('${u['email']} • ${u['contactNumber'] ?? ''}'),
                        trailing: Pill(AuthUser.roles[u['role']] ?? '${u['role']}', color: u['role'] == 'admin' ? AppColors.live : AppColors.cyan),
                        onTap: () => _editRole(u),
                        onLongPress: () async {
                          if (!await confirmDialog(context, title: 'Delete ${u['email']}?', danger: true, ok: 'Delete')) return;
                          try {
                            await context.api.deleteUser(u['id'].toString());
                            _reload();
                          } catch (e) {
                            if (context.mounted) context.toast(e.toString(), error: true);
                          }
                        },
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

/// Plans & subscription (web SubscriptionManager.tsx).
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key, required this.onChanged});
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plans')),
      body: AsyncBuilder<List<Map<String, dynamic>>>(
        future: Future.wait([context.api.billingPlansRaw(), context.api.billingStatus().catchError((_) => <String, dynamic>{})])
            .then((r) => [r[0], r[1]]),
        builder: (c, r) {
          final plans = asMapList(r[0]['plans']);
          final sub = asMap(r[1]['subscription']);
          return ListView(padding: const EdgeInsets.all(16), children: [
            GradientCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Your plan', style: TextStyle(color: AppColors.textMid)),
                Text(sub['planName']?.toString() ?? 'Free — online scoring', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                if (sub['expiresAt'] != null) Text('Valid until ${Fmt.dateTime(sub['expiresAt'])}', style: const TextStyle(color: AppColors.textMid)),
                const SizedBox(height: 6),
                const Text('Free: online scoring + public scorecards. Paid passes unlock the broadcast console, ticker graphics and scorer sharing on the web.',
                    style: TextStyle(color: AppColors.textMid, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 12),
            for (final p in plans)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium, color: Color(0xFFF59E0B)),
                  title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('${p['description'] ?? p['type'] ?? ''}'),
                  trailing: FilledButton(
                    onPressed: () async {
                      if (!await confirmDialog(context, title: 'Activate ${p['name']}?', message: '₹${p['price']} — activates immediately on your account.', ok: 'Activate')) return;
                      try {
                        await context.api.subscribe(p['id'].toString());
                        await onChanged();
                        if (context.mounted) {
                          context.toast('${p['name']} activated', success: true);
                          Navigator.pop(context);
                        }
                      } catch (e) {
                        if (context.mounted) context.toast(e.toString(), error: true);
                      }
                    },
                    child: Text('₹${p['price']}'),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// Join a team squad with an invite code (web joinTeamViaInvite).
Future<void> joinTeamWithCode(BuildContext context) async {
  final v = await promptText(context, title: 'Paste the team invite code', hint: 'CO1-…');
  if (v == null || v.isEmpty || !context.mounted) return;
  final parsed = parseInviteCode(v);
  if (parsed == null) {
    context.toast('That does not look like a CreaseOne invite code', error: true);
    return;
  }
  try {
    final r = await context.api.joinTeamInvite(parsed.$1, parsed.$2);
    if (context.mounted) {
      context.toast(r['alreadyMember'] == true ? 'You are already in ${r['teamName'] ?? 'this team'}' : 'Joined ${r['teamName'] ?? 'the team'} in ${r['tournamentName'] ?? 'the tournament'}', success: true);
    }
  } catch (e) {
    if (context.mounted) context.toast(e.toString(), error: true);
  }
}

/// Upload a finished match scorecard (PDF / image / JSON) — parsed server-side with Gemini (admin only).
class HistoricalUploadScreen extends StatefulWidget {
  const HistoricalUploadScreen({super.key});
  @override
  State<HistoricalUploadScreen> createState() => _HistoricalUploadScreenState();
}

class _HistoricalUploadScreenState extends State<HistoricalUploadScreen> {
  bool busy = false;
  Map<String, dynamic>? result;

  Future<void> _pick() async {
    final f = await pickFile(extensions: const ['pdf', 'png', 'jpg', 'jpeg', 'json', 'txt']);
    if (f == null || !mounted) return;
    setState(() => busy = true);
    try {
      final r = await context.api.uploadHistoricalMatch(f);
      setState(() => result = r);
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = result?['matchId']?.toString() ?? asMap(result?['match'])['id']?.toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Upload past match')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Upload a completed match scorecard (PDF, photo or JSON). It is read with AI on the server and saved as a completed match with full stats.',
            style: TextStyle(color: AppColors.textMid)),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: busy ? null : _pick, icon: const Icon(Icons.upload_file), label: Text(busy ? 'Reading scorecard…' : 'Choose scorecard file')),
        if (result != null) ...[
          const SizedBox(height: 16),
          GradientCard(child: Text(result!['message']?.toString() ?? (result!['success'] == true ? 'Match imported' : 'Done'))),
          if (id != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton(onPressed: () => context.push(MatchDetailScreen(matchId: id)), child: const Text('Open imported match')),
            ),
        ],
      ]),
    );
  }
}

/// Player format profiles (T20 / ODI / TEST career numbers) via Excel — web PlayerFormatProfilesUpload.
class FormatProfilesScreen extends StatefulWidget {
  const FormatProfilesScreen({super.key});
  @override
  State<FormatProfilesScreen> createState() => _FormatProfilesScreenState();
}

class _FormatProfilesScreenState extends State<FormatProfilesScreen> {
  String format = 'T20';
  final selected = <String>{};
  bool busy = false;
  late final Future<List<Map<String, dynamic>>> players = context.api.players(mine: true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Format profiles upload')),
      body: AsyncBuilder<List<Map<String, dynamic>>>(
        future: players,
        builder: (c, list) => ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'T20', label: Text('T20')), ButtonSegment(value: 'ODI', label: Text('ODI')), ButtonSegment(value: 'TEST', label: Text('Test'))],
            selected: {format},
            onSelectionChanged: (v) => setState(() => format = v.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy || selected.isEmpty
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          final bytes = await context.api.formatProfilesTemplate(format, selected.toList());
                          if (context.mounted) await shareBytes(context, bytes, 'player-profiles-$format.xlsx');
                        } catch (e) {
                          if (context.mounted) context.toast(e.toString(), error: true);
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                icon: const Icon(Icons.download),
                label: Text('Template (${selected.length})'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final f = await pickFile();
                        if (f == null || !context.mounted) return;
                        setState(() => busy = true);
                        try {
                          final r = await context.api.uploadFormatProfiles(format, f);
                          if (context.mounted) context.toast('Updated ${r['updated'] ?? r['count'] ?? ''} profiles', success: true);
                        } catch (e) {
                          if (context.mounted) context.toast(e.toString(), error: true);
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                icon: const Icon(Icons.upload),
                label: const Text('Upload'),
              ),
            ),
          ]),
          const SectionTitle('Players for the template', padding: EdgeInsets.fromLTRB(0, 18, 0, 6)),
          for (final p in list)
            CheckboxListTile(
              value: selected.contains(p['id'].toString()),
              onChanged: (v) => setState(() => v == true ? selected.add(p['id'].toString()) : selected.remove(p['id'].toString())),
              title: Text('${p['name']}'),
              subtitle: Text(Cricket.roleLabel(p['role'])),
            ),
        ]),
      ),
    );
  }
}
