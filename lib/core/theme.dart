import 'package:flutter/material.dart';

/// CreaseOne brand palette (matches the web landing page: deep navy + electric blue).
class AppColors {
  AppColors._();

  static const bg = Color(0xFF060A14);
  static const surface = Color(0xFF0D1424);
  static const surfaceHigh = Color(0xFF131C30);
  static const border = Color(0x1AFFFFFF);
  static const primary = Color(0xFF2F6BFF);
  static const primaryDeep = Color(0xFF1A3FA8);
  static const cyan = Color(0xFF22D3EE);
  static const textHi = Color(0xFFF1F5F9);
  static const textMid = Color(0xFF94A3B8);
  static const textLo = Color(0xFF64748B);

  static const live = Color(0xFFEF4444);
  static const four = Color(0xFF3B82F6);
  static const six = Color(0xFFA855F7);
  static const wicket = Color(0xFFEF4444);
  static const extra = Color(0xFFF59E0B);
  static const dot = Color(0xFF475569);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const ball = Color(0xFFDC2626);

  static const brandGradient = LinearGradient(
    colors: [Color(0xFF1A3FA8), Color(0xFF2F6BFF), Color(0xFF22D3EE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const cardGradient = LinearGradient(
    colors: [Color(0xFF0F1830), Color(0xFF0A1122)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Parse "#RRGGBB" team colours safely.
  static Color fromHex(String? hex, {Color fallback = primary}) {
    if (hex == null) return fallback;
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.cyan,
      surface: AppColors.surface,
      error: AppColors.live,
      onPrimary: Colors.white,
      onSurface: AppColors.textHi,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      brightness: Brightness.dark,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textHi,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textHi, letterSpacing: 0.2),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: const TextStyle(color: AppColors.textMid),
        hintStyle: const TextStyle(color: AppColors.textLo),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textHi,
          minimumSize: const Size(64, 48),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: AppColors.primary.withValues(alpha: 0.25),
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(color: AppColors.textHi, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.textHi,
        unselectedLabelColor: AppColors.textLo,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontWeight: FontWeight.w800),
        dividerColor: AppColors.border,
        tabAlignment: TabAlignment.start,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.textMid),
    );
  }
}
