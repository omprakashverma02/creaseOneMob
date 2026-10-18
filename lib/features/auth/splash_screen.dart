import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(colors: [Color(0xFF10224D), AppColors.bg], radius: 1.1),
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AppLogo(height: 170),
              const SizedBox(height: 28),
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(height: 14),
              Text(AppConfig.tagline.toUpperCase(), style: const TextStyle(color: AppColors.textMid, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}
