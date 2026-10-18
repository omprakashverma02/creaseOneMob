import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/cricket.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';
import '../../widgets/server_settings.dart';
import '../admin/admin_screens.dart';
import '../players/player_detail_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final u = auth.user;
    if (u == null) return const SizedBox.shrink();
    final sub = u.subscription;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: auth.refreshMe,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.white24,
                child: Text(Fmt.initials(u.name), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text(u.email, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)),
                    child: Text(AuthUser.roles[u.role] ?? u.role, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Name'),
                subtitle: Text(u.name),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _edit(context, u, 'name', 'Name', u.name),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text('Mobile'),
                subtitle: Text(u.contactNumber == null || u.contactNumber!.startsWith('google-') ? 'Not set' : u.contactNumber!),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _edit(context, u, 'contactNumber', 'Mobile number', u.contactNumber?.startsWith('google-') == true ? '' : u.contactNumber),
              ),
              if (u.playerId != null) ...[
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.sports_cricket),
                  title: const Text('My player profile & stats'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(PlayerDetailScreen(playerId: u.playerId!)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.group_add_outlined, color: AppColors.cyan),
                title: const Text('Join a team'),
                subtitle: const Text('Paste an invite code from your organiser'),
                onTap: () => joinTeamWithCode(context),
              ),
              if (u.canManage) ...[
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.table_view_outlined, color: AppColors.cyan),
                  title: const Text('Player format profiles'),
                  subtitle: const Text('T20 / ODI / Test career numbers via Excel'),
                  onTap: () => context.push(const FormatProfilesScreen()),
                ),
              ],
              if (u.isAdmin) ...[
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.live),
                  title: const Text('Admin — users & roles'),
                  onTap: () => context.push(const AdminUsersScreen()),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.history_edu_outlined, color: AppColors.live),
                  title: const Text('Upload a past match scorecard'),
                  onTap: () => context.push(const HistoricalUploadScreen()),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              ListTile(
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(PlansScreen(onChanged: auth.refreshMe)),
                leading: const Icon(Icons.workspace_premium_outlined, color: Color(0xFFF59E0B)),
                title: const Text('Plan'),
                subtitle: Text(sub.isEmpty
                    ? 'Free — online scoring'
                    : '${sub['planName'] ?? sub['plan'] ?? sub['tier'] ?? 'Active plan'}${sub['expiresAt'] != null ? ' • until ${Fmt.date(sub['expiresAt'])}' : ''}'),
              ),
              const Divider(indent: 56),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Broadcast graphics'),
                subtitle: Text('Ticker overlays & OBS graphics are managed from the CreaseOne web Broadcast Console.'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Server'),
                subtitle: Text(AppConfig.apiBase, style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => showServerSettings(context, onChanged: () => context.auth.signOut()),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.live),
                title: const Text('Sign out', style: TextStyle(color: AppColors.live, fontWeight: FontWeight.w800)),
                onTap: () async {
                  if (await confirmDialog(context, title: 'Sign out?', ok: 'Sign out', danger: true)) {
                    if (context.mounted) context.auth.signOut();
                  }
                },
              ),
            ]),
          ),
          const SizedBox(height: 24),
          const Center(child: AppLogo(height: 70)),
          const SizedBox(height: 6),
          const Center(child: Text('CreaseOne v1.0.0', style: TextStyle(color: AppColors.textLo, fontSize: 12))),
        ]),
      ),
    );
  }

  Future<void> _edit(BuildContext context, AuthUser u, String field, String title, String? initial) async {
    final v = await promptText(context, title: title, initial: initial, keyboard: field == 'contactNumber' ? TextInputType.phone : null);
    if (v == null || v.isEmpty || !context.mounted) return;
    try {
      await context.api.updateMyProfile(u.id, {field: v});
      if (context.mounted) await context.auth.refreshMe();
    } catch (e) {
      if (context.mounted) context.toast(e.toString(), error: true);
    }
  }
}
