import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import '../players/players_screen.dart';
import '../profile/profile_screen.dart';
import '../teams/teams_screen.dart';
import '../tournaments/tournaments_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  final _pages = const [HomeScreen(), TournamentsScreen(), TeamsScreen(), PlayersScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => index = 0);
      },
      child: Scaffold(
        body: IndexedStack(index: index, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.sports_cricket_outlined), selectedIcon: Icon(Icons.sports_cricket), label: 'Matches'),
            NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Tournaments'),
            NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Teams'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Players'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
