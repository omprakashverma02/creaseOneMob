import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/api_client.dart';
import 'data/crease_api.dart';
import 'features/auth/complete_profile_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/public/public_home_screen.dart';
import 'features/scoring/scoring_screen.dart';
import 'features/shell/home_shell.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
  ));
  final api = CreaseApi(ApiClient());
  final auth = AuthService(api)..bootstrap();
  runApp(MultiProvider(
    providers: [
      Provider<CreaseApi>.value(value: api),
      ChangeNotifierProvider<AuthService>.value(value: auth),
    ],
    child: const CreaseOneApp(),
  ));
}

class CreaseOneApp extends StatelessWidget {
  const CreaseOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CreaseOne',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final Widget page;
    switch (auth.status) {
      case AuthStatus.loading:
        page = const SplashScreen();
      case AuthStatus.signedOut:
        page = const LoginScreen();
      case AuthStatus.needsProfile:
        page = const CompleteProfileScreen();
      case AuthStatus.guest:
        page = const PublicHomeScreen();
      case AuthStatus.signedIn:
        page = auth.isScorerSession ? ScoringScreen(matchId: auth.scorerMatchId!, scorerOnly: true) : const HomeShell();
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: KeyedSubtree(key: ValueKey(auth.status.name + (auth.scorerMatchId ?? '')), child: page));
  }
}
